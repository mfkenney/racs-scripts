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

logger -p "local0.info" "Starting photo sequence"
# Power on the cameras
# Wait for cameras to boot
sleep $RACS_CAMERA_BOOTTIME
# Verify that cameras are reachable on the network
cameras=
for i in $(seq $RACS_NCAMERAS)
do
    host="camera-${i}"
    if camera_up $host
    then
        cameras="$cameras $host"
    else
        logger -p "local0.warn" "$host not reachable"
    fi
done
# Allow cameras to warm-up
sleep $RACS_CAMERA_WARMUP

# Take a snapshot from each one
for c in $cameras
do
    logger -p "local0.info" "Snapshot from $c"
    snapshot.sh "$c" || \
        logger -p "local0.warning" "Snapshot failed ($c)"
done
# Power off the cameras
logger -p "local0.info" "Cameras powered off"
# Collect the metadata
# Establish PPP link
# Sync clock with ntpdate
sudo ntpdate -b $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1
# Download configuration updates
# Download list of full-res images
# Locate full-res images and add to OUTBOX
# Package-up files in OUTBOX and upload
# Clean OUTBOX if upload was successful
# Shutdown until next sample time
set_alarm.sh $RACS_INTERVAL
