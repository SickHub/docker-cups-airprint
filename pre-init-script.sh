#!/bin/bash
PRE_INIT_HOOK=${PRE_INIT_HOOK:="/root/pre-init-script.sh"}

echo "This is an example/dummy pre-init script. It does nothing by default.
If you want to execute your own code & logic (e.g., installing a printer driver via a shell script or apt)
before everything initializes and starts up 
then:
    a) Replace this file via a volume mount (-v /path/to/host/script:${PRE_INIT_HOOK})
or  
    b) Change the environment variable 'PRE_INIT_HOOK' to your custom path or command 
       that should be executed inside the container."