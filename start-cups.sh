#!/bin/bash
set -e

### Enable debug if debug flag is true ###
[ "yes" = "${CUPS_ENV_DEBUG}" ] && set -x

### variable defaults
CUPS_IP=${CUPS_IP:-$(hostname -i)}
CUPS_HOSTNAME=${CUPS_HOSTNAME:-$(hostname -f)}
CUPS_ADMIN_USER=${CUPS_ADMIN_USER:-"admin"}
CUPS_ADMIN_PASSWORD=${CUPS_ADMIN_PASSWORD:-"secr3t"}
CUPS_WEBINTERFACE=${CUPS_WEBINTERFACE:-"yes"}
CUPS_SHARE_PRINTERS=${CUPS_SHARE_PRINTERS:-"yes"}
CUPS_REMOTE_ADMIN=${CUPS_REMOTE_ADMIN:-"yes"}
CUPS_ACCESS_LOGLEVEL=${CUPS_ACCESS_LOGLEVEL:-"config"}
CUPS_LOGLEVEL=${CUPS_LOGLEVEL:-"warn"}
CUPS_SSL_CERT=${CUPS_SSL_CERT:-""}
CUPS_SSL_KEY=${CUPS_SSL_KEY:-""}
GCP_ENABLE_LOCAL=${GCP_ENABLE_LOCAL:-"false"}
GCP_ENABLE_CLOUD=${GCP_ENABLE_CLOUD:-"false"}
GCP_XMPP_JID=${GCP_XMPP_JID:-""}
GCP_REFRESH_TOKEN=${GCP_REFRESH_TOKEN:-""}
GCP_PROXY_NAME=${GCP_PROXY_NAME:-""}
[ "yes" = "${CUPS_ENV_DEBUG}" ] && export -n

### check for valid input
if printf '%s' "${CUPS_ADMIN_PASSWORD}" | LC_ALL=C grep -q '[^ -~]\+'; then
  RETURN=1; REASON="CUPS password contain illegal non-ASCII characters, aborting!"; exit;
fi

### create admin user if it does not exist
if [ $(grep -ci ${CUPS_ADMIN_USER} /etc/shadow) -eq 0 ]; then
    useradd ${CUPS_ADMIN_USER} --system -g lpadmin --no-create-home --password $(mkpasswd ${CUPS_ADMIN_PASSWORD})
    if [[ ${?} -ne 0 ]]; then RETURN=${?}; REASON="Failed to set password ${CUPS_ADMIN_PASSWORD} for user root, aborting!"; exit; fi
fi

### prepare cups configuration: log everything to stderr
sed -i 's/^.*AccessLog .*/AccessLog stderr/' /etc/cups/cups-files.conf
sed -i 's/^.*ErrorLog .*/ErrorLog stderr/' /etc/cups/cups-files.conf
sed -i 's/^.*PageLog .*/PageLog stderr/' /etc/cups/cups-files.conf
if [ "yes" = "${CUPS_REMOTE_ADMIN}" ]; then
  sed -i 's/Listen localhost:631/Listen \*:631/' /etc/cups/cupsd.conf
fi
# own SSL cert:
# CreateSelfSignedCerts no
# host.name.crt & host.name.key -> /etc/cups/ssl/
if [ -n "${CUPS_SSL_CERT}" -a -n "${CUPS_SSL_KEY}" ]; then
  [ -z "$(grep CreateSelfSignedCerts /etc/cups/cups-files.conf)" ] && 
    echo "CreateSelfSignedCerts no" >> /etc/cups/cups-files.conf || 
    sed -i 's/^.*CreateSelfSignedCerts.*/CreateSelfSignedCerts no/' /etc/cups/cups-files.conf
  echo -e "${CUPS_SSL_CERT}" > /etc/cups/ssl/${CUPS_HOSTNAME}.crt
  echo -e "${CUPS_SSL_KEY}" > /etc/cups/ssl/${CUPS_HOSTNAME}.key
fi

# smbspool fix for smb auth bug: https://bugzilla.redhat.com/show_bug.cgi?id=1700791
mv /usr/bin/smbspool /usr/bin/smbspool.orig
echo '#!/bin/sh
cat <&0| /usr/bin/smbspool.orig $DEVICE_URI "$1" "$2" "$3" "$4" "$5"
exit 0
' > /usr/bin/smbspool
chmod +x /usr/bin/smbspool

### prepare avahi-daemon configuration (dbus disabled by default)
sed -i 's/^.*enable\-reflector=.*/enable\-reflector\=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^.*reflect\-ipv=.*/reflect\-ipv\=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^.*enable-dbus=.*/enable-dbus=no/' /etc/avahi/avahi-daemon.conf

# start automatic printer refresh for avahi
/opt/airprint/printer-update.sh &

# start dbus, if required by gcp-connector
if [ "true" = "${GCP_ENABLE_LOCAL}" -o "true" = "${GCP_ENABLE_CLOUD}" ]; then
  sed -i 's/^.*enable-dbus=.*/enable-dbus=yes/' /etc/avahi/avahi-daemon.conf

  # delete services that might depend on systemd
  rm /usr/share/dbus-1/system.d/org.freedesktop.systemd1.conf
  rm /usr/share/dbus-1/system.d/org.freedesktop.login1.conf
  rm /usr/share/dbus-1/system-services/org.freedesktop.login1.service
  rm /usr/share/dbus-1/system.d/org.freedesktop.timesync1.conf
  rm /usr/share/dbus-1/system-services/org.freedesktop.timesync1.service

  # run in background, but not as daemon as this implies syslog
  # dbus needs ~90sec to run into a timeout - no clue how to fix this.
  # AUTH EXTERNAL - dbus-daemon[9239]: [system] Connection has not authenticated soon enough, closing it (auth_timeout=5000ms, elapsed: 90026ms))
  /usr/bin/dbus-daemon --system --nosyslog --nofork &
  sleep 2
fi

# start avahi instance in background (but not as daemon as this implies syslog)
/usr/sbin/avahi-daemon &

# setup and start the Google Cloud Print Connector
if [ "true" = "${GCP_ENABLE_LOCAL}" -o "true" = "${GCP_ENABLE_CLOUD}" ]; then
  echo '{
    "local_printing_enable": '${GCP_ENABLE_LOCAL}',
    "cloud_printing_enable": '${GCP_ENABLE_CLOUD}',
    "xmpp_jid": "'${GCP_XMPP_JID}'",
    "robot_refresh_token": "'${GCP_REFRESH_TOKEN}'",
    "proxy_name": "'${GCP_PROXY_NAME}'",
    "log_level": "INFO",
    "log_file_name": "/tmp/cloud-print-connector"
  }' > /etc/gcp-connector/gcp-cups-connector.config.json
  chown gcp-connector /etc/gcp-connector/gcp-cups-connector.config.json
  /etc/init.d/gcp-connector start
fi


### configure CUPS (background subshell, wait till cups http is running...)
(
until cupsctl -h localhost:631 --share-printers > /dev/null 2>&1; do echo -n "."; sleep 1; done; 
echo "--> CUPS ready"
[ "yes" = "${CUPS_ENV_DEBUG}" ] && cupsctl --debug-logging || cupsctl --no-debug-logging
[ "yes" = "${CUPS_REMOTE_ADMIN}" ] && cupsctl --remote-admin --remote-any || cupsctl --no-remote-admin
[ "yes" = "${CUPS_SHARE_PRINTERS}" ] && cupsctl --share-printers || cupsctl --no-share-printers
[ "yes" = "${CUPS_WEBINTERFACE}" ] && cupsctl WebInterface=yes || cupsctl WebInterface=No
cupsctl ServerName=${CUPS_HOSTNAME}
cupsctl LogLevel=${CUPS_LOGLEVEL}
cupsctl AccessLogLevel=${CUPS_ACCESS_LOGLEVEL}
# setup printers (run each CUPS_LPADMIN_PRINTER* command)
echo "--> adding printers"
for v in $(set |grep ^CUPS_LPADMIN_PRINTER |sed -e 's/^\(CUPS_LPADMIN_PRINTER[^=]*\).*/\1/' |sort |tr '\n' ' '); do
  echo "$v = $(eval echo "\$$v")"
  eval $(eval echo "\$$v")
done
echo "--> CUPS configured"
) &

(sleep 2;
cat <<EOF
===========================================================
The dockerized CUPS instance is now ready for use! The web
interface is available here:
URL:       http://${CUPS_IP}:631/ or http://${CUPS_HOSTNAME}:631/
Username:  ${CUPS_ADMIN_USER}
Password:  ${CUPS_ADMIN_PASSWORD}

Google Cloud Print
local: ${GCP_ENABLE_LOCAL}
cloud: ${GCP_ENABLE_CLOUD}
===========================================================
EOF
) &

### Start CUPS instance ###
/usr/sbin/cupsd -f
