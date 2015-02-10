#!/bin/bash
#
# Decide whether to enter Autonomous Mode based on whether the control
# computer is connected to the Ethernet switch.
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

CTRL_HOST=10.13.0.100

# Wait for Ethernet switch to be powered-on
n=20
while sleep 1; do
    power_test $RACS_ENET_POWER && break
    if ((--n <= 0)); then
        # If the switch is not powered-on by now, something
        # has gone wrong in the boot process. The safest
        # thing to do is proceed as if the control host
        # is connected.
        #
        # This is *very* unlikely to happen...
        logger -p "local0.emerg" "Ethernet switch not powered"
        echo "$HOME/bin/tasks.sh 1> /dev/null 2>&1" |\
            /usr/bin/at 'now + 2 minutes'
        exit 1
    fi
done

# Allow for Ethernet switch start-up time
sleep 2

# Allow ~10 seconds for the control host to appear. Ping will
# timeout after 2-3 seconds if the host is not on-line.
n=4
while ! ping -q -c 1 -n $CTRL_HOST 1> /dev/null 2>&1; do
    if ((--n <= 0)); then
        exec $HOME/bin/tasks.sh
    fi
done

logger -p "local0.info" "Control host detected, delaying start-up"

# Control host found, allow 2 minutes for user to log-in
echo "$HOME/bin/tasks.sh 1> /dev/null 2>&1" |\
    /usr/bin/at 'now + 2 minutes'

exit 0
