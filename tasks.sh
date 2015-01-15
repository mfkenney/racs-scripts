#!/bin/bash
#
# Run all RACS tasks
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

camera_up ()
{
    curl --connect-timeout 2 -s -X HEAD http://$1/index.html > /dev/null
}

power_on ()
{
    for arg
    do
        tsctl @localhost DIO setasync "$arg" HIGH
    done
}

power_off ()
{
    for arg
    do
        tsctl @localhost DIO setasync "$arg" LOW
    done
}

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[ -e $CFGDIR/settings ] && . $CFGDIR/settings
[ -e $HOME/bin/library.sh ] && . $HOME/bin/library.sh

if [ -e /tmp/INHIBIT ]
then
    log_event "INFO" "Autonomous operation inhibited"
    exit 1
fi

# Remove old files from the OUTBOX
clean_dir "$OUTBOX" "$RACS_MAX_AGE"

# Start the A/D monitor
# TODO: add A/D config file
adread --interval=5s > $OUTBOX/adc.csv &
child=$!

# Power on the ethernet switch
power_on $RACS_ENET_POWER
# Power on the cameras
log_event "INFO" "Powering on cameras"
power_on "${RACS_CAMERA_POWER[@]}"

# Wait for all cameras to boot
up=()
n_up=0
for ((i = 1; i <= RACS_NCAMERAS; i++))
do
    name="camera-${i}"
    if wait_for_camera $name $RACS_CAMERA_BOOTTIME
    then
        up+=("$name")
        ((n_up++))
    fi
done

if ((n_up == 0))
then
    log_event "ERROR" "No cameras available!"
else
    # Allow additional warm-up time
    sleep $RACS_CAMERA_WARMUP
    # Take a snapshot from each one and power it off
    for c in "${up[@]}"
    do
        idx=$(cut -f2 -d- <<< "$c")
        i=$((idx - 1))
        snapshot.sh "$c" "${RACS_CAMERA_POWER[i]}"
    done
fi

# Make sure the cameras are powered off
power_off "${RACS_CAMERA_POWER[@]}"

# If we are in autonomous mode, it's safe to power off
# the ethernet switch.
if [ -z "$RACS_NOSLEEP" ]
then
    power_off "$RACS_ENET_POWER"
    log_event "INFO" "Ethernet switch powered off"
fi

power_on "$RACS_MODEM_POWER"
log_event "INFO" "Modem powered on"
# TODO: Establish PPP link
log_event "INFO" "Initiating PPP link"

# Download configuration updates and the list of
# requested full-res images to the INBOX
if [ -n "$RACS_FTP_SERVER" ]
then
    ftp -p $RACS_FTP_SERVER<<EOF
cd outgoing/$ID
lcd $INBOX
get updates
delete updates
get fullres.txt
delete fullres.txt
EOF
    [ -e "$INBOX/updates" ] && mv "$INBOX/updates" "$CFGDIR"
fi

# Locate full-res images and add to OUTBOX
if [ -e "$INBOX/fullres.txt" ]
then
    while read name
    do
        findimg.sh "$name"
    done <"$INBOX/fullres.txt"
    rm -f "$INBOX/fullres.txt"
fi

# Stop the A/D monitor and save the output to the OUTBOX
if [ -n "$child" ]
then
    kill -TERM $child
    wait $child
fi

# Sync clock with ntpdate
sudo ntpdate -b $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

# Upload files from the OUTBOX. Files are removed after
# they are successfully transfered.
if [ -n "$RACS_FTP_SERVER" ]
then
    (
        cd $OUTBOX
        zip_non_jpeg
        wput -nv --disable-tls -B -R * ftp://$RACS_FTP_SERVER/incoming/$ID/
    )
fi

# Shutdown until next sample time
if [ -n "$RACS_NOSLEEP" ]
then
    :
else
    set_alarm.sh $RACS_INTERVAL
fi
