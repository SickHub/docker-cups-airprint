#!/usr/bin/env bash

[ "yes" = "${AVAHI_FRIENDLY_DESC}" ] && FLAGS="-x" || FLAGS=""

inotifywait -m -e close_write,moved_to,create /etc/cups |

while read -r directory events filename; do
	if [ "$filename" = "printers.conf" ]; then
    rm -rf /etc/avahi/services/AirPrint-*.service
		/opt/airprint/airprint-generate.py -d /etc/avahi/services ${FLAGS}
	fi
done
