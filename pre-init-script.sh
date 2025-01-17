#!/bin/bash

echo "This is an example/dummy pre-init script. It does nothing by default.
If you want to execute your own code & logic (e.g., installing a printer driver via a shell script or apt)
before everything initializes and starts up 
then:
    a) Replace this file via a volume mount (-v /path/to/host/script:/root/pre-init-script.sh)
or  
    b) Change the environment variable 'PRE_INIT_HOOK' to your custom (mounted) path or command 
       that should be executed inside the container."
