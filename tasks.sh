#!/bin/bash
#
# Run all RACS tasks
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

cleanup_and_shutdown ()
{
    logger -s -p "local0.info" "Shutting down"
    # Bring down PPP link and power-down the modem
    sudo poff iridium
    power_off "$RACS_MODEM_POWER"

    # Shutdown until next sample time
    [[ "$RACS_NOSLEEP" ]] || set_alarm.sh $RACS_INTERVAL
}

if [[ -e /tmp/INHIBIT ]]; then
    logger -s -p "local0.info" "Autonomous operation inhibited"
    exit 1
fi

# Remove old files from the OUTBOX
clean_dir "$OUTBOX" "$RACS_MAX_AGE"

# Start the A/D monitor and store the output in the OUTBOX.
adcfg=
[[ -f "$CFGDIR/adc.yml" ]] && adcfg="$CFGDIR/adc.yml"
adread --interval=5s $adcfg > $OUTBOX/adc.csv &
child=$!

# Power on the ethernet switch
power_on $RACS_ENET_POWER
# Power on the cameras
log_event "INFO" "Powering on cameras"
power_on "${RACS_CAMERA_POWER[@]}"

# Wait for all cameras to boot
up=()
n_up=0
for ((i = 1; i <= RACS_NCAMERAS; i++)); do
    name="camera-${i}"
    if wait_for_camera $name $RACS_CAMERA_BOOTTIME; then
        up+=("$name")
        ((n_up++))
    fi
done

if ((n_up == 0)); then
    log_event "ERROR" "No cameras available!"
else
    # Allow additional warm-up time
    sleep $RACS_CAMERA_WARMUP
    # Take a snapshot from each one and power it off
    for c in "${up[@]}"; do
        idx=$(cut -f2 -d- <<< "$c")
        i=$((idx - 1))
        snapshot.sh "$c" "${RACS_CAMERA_POWER[i]}"
    done
fi

# Make sure the cameras are powered off
power_off "${RACS_CAMERA_POWER[@]}"

# If we are in autonomous mode, it's safe to power off
# the ethernet switch.
if [[ ! "$RACS_NOSLEEP" ]]; then
    power_off "$RACS_ENET_POWER"
    log_event "INFO" "Ethernet switch powered off"
fi

power_on "$RACS_MODEM_POWER"
log_event "INFO" "Modem powered on"
# Establish PPP link
log_event "INFO" "Initiating PPP link"
sudo pon iridium persist

# Wait for link to be established
if ppp_wait $RACS_PPP_LINKTIME; then
    log_event "INFO" "PPP link up"
    sudo ip route add $RACS_FTP_SERVER/32 dev ppp0
    sudo ip route add $RACS_NTP_SERVER/32 dev ppp0
else
    logger -s -p "local0.emerg" "Cannot establish PPP link"
    # If the link cannot be established, power off the
    # modem and bailout. If we are in autonomous mode,
    # shutdown until the next interval.
    sudo poff iridium
    power_off "$RACS_MODEM_POWER"
    [[ "$RACS_NOSLEEP" ]] && exit 1
    set_alarm.sh $RACS_INTERVAL
fi

# Set a time limit for the rest of the script to finish
trap cleanup_and_shutdown ALRM
sleep $RACS_PPP_TIMELIMIT && kill -ALRM $$ &

# Download configuration updates and the list of
# requested full-res images to the INBOX
if [[ "$RACS_FTP_SERVER" ]]; then
    ftp -p $RACS_FTP_SERVER<<EOF
cd outgoing/$ID
lcd $INBOX
get updates
delete updates
get fullres.txt
delete fullres.txt
EOF
    if [[ -e "$INBOX/updates" ]]; then
        mv "$INBOX/updates" "$CFGDIR"
        . $CFGDIR/settings
    fi

    # Locate full-res images and add to OUTBOX
    if [[ -e "$INBOX/fullres.txt" ]]; then
        while read name; do
            findimg.sh "$name"
        done <"$INBOX/fullres.txt"
        rm -f "$INBOX/fullres.txt"
    fi
fi

# Stop the A/D monitor
if [[ "$child" ]]; then
    kill -TERM $child
    wait $child
fi

# Sync clock with ntpdate
sudo ntpdate -b -t $RACS_NTP_TIMEOUT $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

# Upload files from the OUTBOX. Files are removed after
# they are successfully transfered.
if [[ "$RACS_FTP_SERVER" ]]; then
    (
        filelist="/tmp/uploads"
        sort_arg="${RACS_REV_SORT:+-r}"
        cd $OUTBOX
        df -h /dev/mmcblk0p4 > disk_usage.txt

        # Archive all of the non-image files
        zip_non_jpeg

        # Sort files in timestamp order, oldest first by default. The
        # creation timestamp is incorporated into the filename so we
        # use that rather than the filesystem time.
        for f in *; do
            t=$(cut -f2-3 -d_ <<< "${f%.*}")
            [[ $t ]] && echo "$t $f"
        done | sort $sort_arg | cut -f2- -d' ' > $filelist

        # Start the file upload
        wput -nv --tries=1 \
             --disable-tls -B -R -i $filelist \
             ftp://$RACS_FTP_SERVER/incoming/$ID/ &

        # Wait for the file transfer to complete. Running wput
        # asynchronously allows us to be interrupted by the
        # PPP_TIMELIMIT alarm immediately.
        child=$!
        wait $child
    )
fi

cleanup_and_shutdown
