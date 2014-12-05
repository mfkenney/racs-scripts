#!/bin/bash
#
# Run all RACS tasks and power the system off.
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

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
logger -p "local0.info" "Cameras powered on"
# Take a snapshot from each one
for i in $(seq $RACS_NCAMERAS)
do
    logger -p "local0.info" "Snapshot from camera-${i}"
    snapshot.sh "camera-${i}" || \
        logger -p "local0.warning" "Snapshot failed (camera-${i})"
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
