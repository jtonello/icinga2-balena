#!/bin/bash
/bin/bash /usr/src/app/wait-for-it.sh 10.128.1.209:80 -t 0 -s -- /bin/bash /usr/src/app/icinga-script.sh
