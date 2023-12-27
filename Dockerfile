ARG UBUNTU_VERSION=jammy

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
RUN cmake -B_build -H. && cmake --build _build/

FROM ubuntu:$UBUNTU_VERSION
MAINTAINER drpsychick@drsick.net

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -y upgrade
RUN apt-get -y install \
      cups-daemon \
      cups-client \
      cups-pdf \
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
      libpng16-16 \
      python3-cups \
      samba-client \
      cups-tea4cups \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

COPY --from=kyocera-builder --chmod=0555 /rastertokpsl-re/bin/rastertokpsl-re /usr/lib/cups/filter/rastertokpsl
RUN mkdir -p /usr/share/cups/model/Kyocera
COPY --from=kyocera-builder /rastertokpsl-re/*.ppd /usr/share/cups/model/Kyocera/

# TODO: really needed?
#COPY mime/ /etc/cups/mime/

# setup airprint scripts
COPY airprint/ /opt/airprint/

COPY healthcheck.sh /
COPY start-cups.sh /root/
RUN chmod +x /healthcheck.sh /root/start-cups.sh
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
