ARG BASE_VERSION=latest
FROM jstrader/airprint-cloudprint:$BASE_VERSION

RUN apt-get update \
    && apt-get install -y samba-client \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/* \
    # setup default cups config
    && cp -R /usr/etc/cups/* /etc/cups/ \
    # dhcp hooks trigger timesyncd requesting to start systemd
    && rm -rf /etc/dhcp/

COPY cups/cupsd.conf cups/printers.conf /etc/cups/
COPY ppd/Epson-RX520.ppd /etc/cups/ppd/
COPY healthcheck.sh /
COPY start-cups.sh /root/
RUN chmod +x /healthcheck.sh /root/start-cups.sh

HEALTHCHECK --interval=10s --timeout=3s CMD /healthcheck.sh

ENV TZ="GMT"
ENV CUPS_ENV_DEBUG=no
ENV CUPS_ADMIN_USER=admin
ENV CUPS_ADMIN_PASSWORD=secr3t
ENV CUPS_WEBINTERFACE=yes
ENV CUPS_REMOTE_ADMIN=no
# defaults to $(hostname -i)
ENV CUPS_IP=""
