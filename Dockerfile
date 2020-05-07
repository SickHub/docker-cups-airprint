ARG UBUNTU_VERSION=xenial
FROM ubuntu:$UBUNTU_VERSION
MAINTAINER drpsychick

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update \
    && apt-get -y install \
      cups-daemon \
      cups-client \
      printer-driver-all \
      avahi-daemon \
      google-cloud-print-connector \
      libnss-mdns \
# for mkpasswd
      whois \
      curl \
      inotify-tools \
      libpng16-16 \
      python3-cups \
      samba-client \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# remove unneeded cups backends
RUN rm /usr/lib/cups/backend/parallel \
    && rm /usr/lib/cups/backend/serial \
    && rm /usr/lib/cups/backend/usb

# TODO: really needed?
#COPY mime/ /etc/cups/mime/

# setup airprint and google cloud print scripts
COPY airprint/ /opt/airprint/
COPY gcp-connector /etc/init.d/
RUN useradd -s /usr/sbin/nologin -r -M gcp-connector \
    && mkdir /etc/gcp-connector \
    && chown gcp-connector /etc/gcp-connector \
    && chmod +x /etc/init.d/gcp-connector \
    && mkdir /var/run/dbus

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

# google cloud print config
# run `gcp-connector-util init` and take the values from the resulting json file
ENV GCP_XMPP_JID="" \
    GCP_REFRESH_TOKEN="" \
    GCP_PROXY_NAME="" \
    GCP_ENABLE_LOCAL="false" \
    GCP_ENABLE_CLOUD="false"

ENTRYPOINT ["/root/start-cups.sh"]
