#!/usr/bin/env bash

inotifywait -m -e close_write,moved_to,create /etc/cups |

[ "yes" = "${CUPS_FRIENDLY_DESC}" ] && FLAGS="-x"

while read -r directory events filename; do
	if [ "$filename" = "printers.conf" ]; then
    rm -rf /etc/avahi/services/AirPrint-*.service
		/opt/airprint/airprint-generate.py -d /etc/avahi/services ${FLAGS}
	fi
done
