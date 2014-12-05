#!/bin/bash
#
# Run all RACS tasks and power the system off.
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

camera_up ()
{
    curl --connect-timeout 2 -s -X HEAD http://$1/index.html > /dev/null
}

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"

[ -e $CFGDIR/settings ] && . $CFGDIR/settings

if [ -e /tmp/INHIBIT ]
then
    logger -p "local0.info" "Autonomous operation inhibited"
    exit 1
fi

# List of camera hosts that are up
declare -a up
# List of camera hosts that are down
declare -a down
# Temporary list
declare -a pool

# Start with all hosts in the down list. Note that Camera N
# *must* have the hostname "camera-N" assigned in /etc/hosts.
for i in $(seq $RACS_NCAMERAS)
do
    down=("${down[@]}" "camera-${i}")
done

logger -p "local0.info" "Starting photo sequence"

# TODO: Power on the cameras

# Wait for all cameras to boot
n_up=0
twait=$(($(date +%s) + RACS_CAMERA_BOOTTIME))
while (("${#down[@]}" > 0))
do
    for host in "${down[@]}"
    do
        if camera_up $host
        then
            ((n_up++))
            up=("${up[@]}" "$host")
        else
            pool=("${pool[@]}" "$host")
        fi
    done
    ((n_up == RACS_NCAMERAS || $(date +%s) > twait)) && break
    down=("${pool[@]}")
    pool=()
    sleep 5
done

if ((n_up == 0))
then
    logger -p "local0.emerg" "No cameras available!"
else
    # Allow additional warm-up time
    sleep $RACS_CAMERA_WARMUP
    # Take a snapshot from each one
    for c in "${up[@]}"
    do
        snapshot.sh "$c"
    done
fi

# TODO: Power off the cameras
logger -p "local0.info" "Cameras powered off"

# TODO: Collect the metadata
# TODO: Establish PPP link

# Sync clock with ntpdate
sudo ntpdate -b $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

# TODO: Download configuration updates
# TODO: Download list of full-res images
# TODO: Locate full-res images and add to OUTBOX

# Save the last 30 lines of the log to the OUTBOX
tail -n 30 /var/log/app.log > $OUTBOX/app.log

# TODO: Package-up files in OUTBOX and upload
# TODO: Clean OUTBOX if upload was successful

# Shutdown until next sample time
if [ -n "$RACS_NOSLEEP" ]
then
    :
else
    set_alarm.sh $RACS_INTERVAL
fi
