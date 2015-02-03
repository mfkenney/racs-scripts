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
    local arg
    for arg; do
        tsctl @localhost DIO setasync "$arg" HIGH
    done
}

power_off ()
{
    local arg
    for arg; do
        tsctl @localhost DIO setasync "$arg" LOW
    done
}

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

if [[ -e /tmp/INHIBIT ]]; then
    logger -p "local0.info" "Autonomous operation inhibited"
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
if ppp_wait $RACS_PPP_TIMELIMIT; then
    log_event "INFO" "PPP link up"
    sudo ip route add $RACS_FTP_SERVER/32 dev ppp0
    sudo ip route add $RACS_NTP_SERVER/32 dev ppp0
else
    logger -p "local0.emerg" "Cannot establish PPP link"
    # If the link cannot be established, power off the
    # modem and bailout. If we are in autonomous mode,
    # shutdown until the next interval.
    sudo poff iridium
    power_off "$RACS_MODEM_POWER"
    [[ "$RACS_NOSLEEP" ]] && exit 1
    set_alarm.sh $RACS_INTERVAL
fi

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
sudo ntpdate -b $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

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

        # Set a time limit for the file transfer to complete
        child=$!
        n=$RACS_FTP_TIMELIMIT
        while sleep 1; do
            kill -0 $child 2> /dev/null || break
            if ((--n <= 0)); then
                kill $child
                break
            fi
        done
        wait $child
    )
fi

# Bring down PPP link and power-down the modem
sudo poff iridium
power_off "$RACS_MODEM_POWER"

# Shutdown until next sample time
[[ "$RACS_NOSLEEP" ]] || set_alarm.sh $RACS_INTERVAL
