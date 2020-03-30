#!/bin/bash

# if webinterface:
curl -I -q -k -f https://127.0.0.1:631/printers/ || exit 1

# else
cupsctl || exit 1
