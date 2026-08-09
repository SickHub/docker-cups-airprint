ARG UBUNTU_VERSION=noble

FROM ubuntu:$UBUNTU_VERSION as kyocera-builder
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y upgrade
RUN apt-get -y install \
      libcupsimage2-dev \
      libcups2-dev \
      libc6-dev \
      gcc \
      cmake \
      git
RUN git clone https://github.com/eLtMosen/rastertokpsl-re.git
WORKDIR /rastertokpsl-re
RUN git checkout cbac20651fe1a40ad258397dc055254b92490054
RUN cat >> src/rastertokpsl.h << 'SIGSET_PATCH_EOF'
#if defined(__linux__) && defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 32))
#include <signal.h>
#ifndef sigset
static inline int sigset(int sig, void (*disp)(int)) {
    struct sigaction sa;
    sa.sa_handler = disp;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    return sigaction(sig, &sa, (struct sigaction *)0);
}
#endif
#endif
SIGSET_PATCH_EOF
RUN sed -i 's/target_link_libraries(rastertokpsl-re ${CUPS_LIB} ${CUPSIMAGE_LIB})/target_link_libraries(rastertokpsl-re ${CUPS_LIB} ${CUPSIMAGE_LIB} m dl)/' src/CMakeLists.txt
RUN cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -B_build -H. && cmake --build _build/

FROM ubuntu:$UBUNTU_VERSION as arm64-base
FROM ubuntu:$UBUNTU_VERSION as arm-base
FROM ubuntu:$UBUNTU_VERSION as amd64-base
COPY --from=kyocera-builder --chmod=0555 /rastertokpsl-re/bin/rastertokpsl-re /usr/lib/cups/filter/rastertokpsl
RUN mkdir -p /usr/share/cups/model/Kyocera
COPY --from=kyocera-builder /rastertokpsl-re/*.ppd /usr/share/cups/model/Kyocera/

FROM ${TARGETARCH}-base
LABEL org.opencontainers.image.authors="drpsychick@drsick.net"
LABEL org.opencontainers.image.description="Simple AirPrint bridge for local printers via CUPS and Avahi"
LABEL org.opencontainers.image.source="https://github.com/SickHub/docker-cups-airprint"

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y upgrade
ARG UBUNTU_VERSION
RUN apt-get -y install \
      cups-daemon \
      cups-client \
      printer-driver-all \
      openprinting-ppds \
      hpijs-ppds \
      hp-ppd \
      hplip \
      avahi-daemon \
      libnss-mdns \
# for mkpasswd
      whois \
      curl \
      inotify-tools \
      $(if [ "noble" = "$UBUNTU_VERSION" -o "latest" = "$UBUNTU_VERSION" ]; then \
      echo "libpng16-16t64"; else echo "libpng16-16"; fi) \
      python3-cups \
      samba-client \
      cups-tea4cups \
    # cups-pdf was dropped from the archive in newer Ubuntu releases;
    # install it when available and skip it otherwise (CUPS >= 2.4 ships its own pdf backend).
    && (apt-get install -y cups-pdf || printf 'cups-pdf not available, skipping\n') \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# TODO: really needed?
#COPY mime/ /etc/cups/mime/

# setup airprint scripts
COPY airprint/ /opt/airprint/

COPY healthcheck.sh /
COPY start-cups.sh /root/
COPY pre-init-script.sh /root/
RUN chmod +x /healthcheck.sh /root/start-cups.sh /root/pre-init-script.sh
HEALTHCHECK --interval=10s --timeout=3s CMD /healthcheck.sh

ENV TZ="GMT" \
    CUPS_ADMIN_USER="admin" \
    CUPS_ADMIN_PASSWORD="secr3t" \
    CUPS_WEBINTERFACE="yes" \
    CUPS_SHARE_PRINTERS="yes" \
    CUPS_REMOTE_ADMIN="yes" \
    CUPS_ENV_DEBUG="no" \
    # defaults to $(hostname -i)
    CUPS_IP="" \
    CUPS_ACCESS_LOGLEVEL="config" \
    # example: lpadmin -p Epson-RX520 -D 'my RX520' -m 'gutenprint.5.3://escp2-rx620/expert' -v smb://user:pass@host/Epson-RX520"
    CUPS_LPADMIN_PRINTER1=""

ENTRYPOINT ["/root/start-cups.sh"]
