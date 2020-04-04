#!/bin/bash
set -e

### Enable debug if debug flag is true ###
[ "yes" == "${CUPS_ENV_DEBUG}" ] && set -x

### variable defaults
CUPS_IP=${CUPS_IP:-$(hostname -i)}
CUPS_ADMIN_USER=${CUPS_ADMIN_USER:-"admin"}
CUPS_ADMIN_PASSWORD=${CUPS_ADMIN_PASSWORD:-"secr3t"}
CUPS_WEBINTERFACE=${CUPS_WEBINTERFACE:-"yes"}
CUPS_REMOTE_ADMIN=${CUPS_REMOTE_ADMIN:-"yes"}

[ -n "${CUPS_ENV_DEBUG}" ] && export -n

### check for valid input
if printf '%s' "${CUPS_ADMIN_PASSWORD}" | LC_ALL=C grep -q '[^ -~]\+'; then
  RETURN=1; REASON="CUPS password contain illegal non-ASCII characters, aborting!"; exit;
fi

### create admin user if it does not exist
if [[ $(grep -ci ${CUPS_ADMIN_USER} /etc/shadow) -eq 0 ]]; then
    useradd ${CUPS_ADMIN_USER} --system -g lpadmin --no-create-home --password $(mkpasswd ${CUPS_ADMIN_PASSWORD})
    if [[ ${?} -ne 0 ]]; then RETURN=${?}; REASON="Failed to set password ${CUPS_ADMIN_PASSWORD} for user root, aborting!"; exit; fi
fi

### prepare cups configuration
sed -i 's/^.*AccessLog .*/AccessLog stderr/' /etc/cups/cups-files.conf
sed -i 's/^.*ErrorLog .*/ErrorLog stderr/' /etc/cups/cups-files.conf
sed -i 's/^.*PageLog .*/PageLog stderr/' /etc/cups/cups-files.conf

### prepare avahi-daemon configuration
sed -i 's/^.*enable\-reflector=.*/enable\-reflector\=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^.*reflect\-ipv=.*/reflect\-ipv\=yes/' /etc/avahi/avahi-daemon.conf
sed -i 's/^.*enable-dbus=.*/enable-dbus=no/' /etc/avahi/avahi-daemon.conf

### Start automatic printer refresh for avahi ###
/opt/airprint/printer-update.sh &

### Start avahi instance ###
/etc/init.d/avahi-daemon start

### Start the Google Cloud Print Connector ###
if [[ -f /tmp/cloud-print-connector.sh-monitor.sock ]]; then
    rm /tmp/cloud-print-connector.sh-monitor.sock
fi
/etc/init.d/cloud-print-connector start

cat <<EOF
===========================================================
The dockerized CUPS instance is now ready for use! The web
interface is available here:
URL:       http://${CUPS_IP}:631/
Username:  ${CUPS_ADMIN_USER}
Password:  ${CUPS_ADMIN_PASSWORD}
===========================================================
EOF

### configure CUPS (background subshell, wait till cups is running...)
(
until cupsctl > /dev/null 2>&1; do sleep 1; done; 
[ "yes" == "${CUPS_ENV_DEBUG}" ] && cupsctl _debug_logging=1
[ "yes" == "${CUPS_REMOTE_ADMIN}" ] && cupsctl _remote_admin=1 || cupsctl _remote_admin=0
[ "yes" == "${CUPS_WEBINTERFACE}" ] && cupsctl WebInterface=yes || cupsctl WebInterface=No
) &


### Start CUPS instance ###
/usr/sbin/cupsd -f
