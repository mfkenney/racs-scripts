#!/bin/bash
#
# Set an alarm to restart the system at the next sample
# interval and power down.
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings

t=$(date +%s)
tnext=$(((1 + t/RACS_INTERVAL)*RACS_INTERVAL))
tsleep=$((tnext - $(date +%s)))

if ((tsleep > 0)); then
    logger -p "local0.info" "Sleeping until $(date -d@$tnext)"
    which ts4200ctl 1> /dev/null && ts4200ctl --setrtc 1> /dev/null
    sleep 1
    sudo sync
    sudo sync
    sudo ts8160ctl --sleep=$tsleep
fi
