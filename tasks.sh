#!/bin/bash
#
# Run all RACS tasks
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

t_session=$(date +%s)
CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ARCHIVEDIR="$HOME/archive"
# Temporary storage of outbound full-res images
FULLRES="$HOME/FULLRES"
ID="$(hostname -s)"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh
adc_pid=
ftp_pid=

cleanup_and_shutdown ()
{
    logger -s -p "local0.info" "Shutting down"
    [[ "$adc_pid" ]] && kill $adc_pid 2> /dev/null
    [[ "$ftp_pid" ]] && kill $ftp_pid 2> /dev/null
    # Bring down PPP link and power-off the modem
    sudo poff iridium
    power_off "$RACS_MODEM_POWER"

    # Shutdown until next sample time
    [[ "$RACS_NOSLEEP" ]] || set_alarm.sh $RACS_INTERVAL
    exit 0
}

if [[ -e /tmp/INHIBIT ]]; then
    logger -s -p "local0.info" "Autonomous operation inhibited"
    exit 1
fi

# Remove old files from the OUTBOX
clean_dir "$OUTBOX" "$RACS_MAX_AGE"
# Remove old files from archive
[[ "$RACS_MAX_ARCHIVE_AGE" ]] && \
    clean_dir "$ARCHIVEDIR" "$RACS_MAX_ARCHIVE_AGE"

# Start the A/D monitor and store the output in the OUTBOX.
adcfg=
[[ -f "$CFGDIR/adc.yml" ]] && adcfg="$CFGDIR/adc.yml"
adread --interval=$RACS_ADC_INTERVAL $adcfg > $OUTBOX/adc.csv &
adc_pid=$!
sleep 1

# Power on the ethernet switch and cameras
(( RACS_NCAMERAS > 0 )) && {
    power_on $RACS_ENET_POWER
    log_event "INFO" "Powering on cameras"
    power_on "${RACS_CAMERA_POWER[@]}"
}

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
    procs=()
    for c in "${up[@]}"; do
        idx=$(cut -f2 -d- <<< "$c")
        i=$((idx - 1))
        snapshot.sh "$c" "${RACS_CAMERA_POWER[i]}" &
        procs+=($!)
    done
    # Wait for the snapshot processes to finish
    for p in "${procs[@]}"; do
        wait $p
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

if [[ "$RACS_USE_USB" ]]; then
    # Enable USB
    power_on PA9
    # Allow some time for USB-serial device node initialization
    file_wait /dev/ttyUSB0 $RACS_USB_STARTTIME || {
        logger -s -p "local0.emerg" "No USB-serial device"
        # No need to bail-out here, as it might "appear" before
        # the PPP process starts. If it doesn't exist, the PPP
        # link will fail and the script will exit.
    }
fi

power_on "$RACS_MODEM_POWER"
log_event "INFO" "Modem powered on"
sleep $RACS_MODEM_WARMUP

# Establish PPP link
log_event "INFO" "Initiating PPP link"
sudo pon iridium persist

# Wait for link to be established
if ppp_wait $RACS_PPP_LINKTIME; then
    log_event "INFO" "PPP link up"
    logger -s -p "local0.info" "PPP link up"
else
    logger -s -p "local0.emerg" "Cannot establish PPP link"
    cleanup_and_shutdown
    exit 1
fi

# Set a time limit for the rest of the script to finish
trap cleanup_and_shutdown ALRM INT QUIT TERM
sleep $RACS_PPP_TIMELIMIT && kill -ALRM $$ 2> /dev/null &
alarm_pid=$!

# Check for updates transferred during the previous call
if [[ -e "$INBOX/updates" ]]; then
    mv "$INBOX/updates" "$CFGDIR"
    . $CFGDIR/settings
fi

# Locate full-res images and add to a separate OUTBOX
mkdir -p "$FULLRES"
if [[ -e "$INBOX/fullres.txt" ]]; then
    while read name; do
        findimg.sh "$name" "$FULLRES"
    done <"$INBOX/fullres.txt"
    rm -f "$INBOX/fullres.txt"
fi

# Stop the A/D monitor
if [[ "$adc_pid" ]]; then
    kill -TERM $adc_pid
    wait $adc_pid
    adc_pid=
fi

# Sync clock with ntpdate
sudo ntpdate -b -t $RACS_NTP_TIMEOUT $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

# Upload files from the OUTBOX. Files are removed after
# they are successfully transfered.
if [[ "$RACS_FTP_SERVER" ]]; then
    # Command file for lftp
    cmdfile="/tmp/lftp.cmds"
    sort_arg="${RACS_REV_SORT:+-r}"

    cd $OUTBOX
    [[ -e "$CFGDIR/updates" ]] && cp $CFGDIR/updates $OUTBOX
    { df -h /dev/mmcblk0p4; du -s -h $ARCHIVEDIR; } > disk_usage.txt
    ls -lt *.jpg *.zip > /tmp/outbox_listing.txt
    cp /tmp/outbox_listing.txt .

    # Archive all of the non-image files
    zip_non_jpeg

    # Sort OUTBOX files in timestamp order, newest first by
    # default. The creation timestamp is incorporated into the
    # filename so we use that rather than the filesystem time.
    files=()
    while read; do
        files+=("$REPLY")
    done < <(for f in *; do
                 t=$(cut -f2-3 -d_ <<< "${f%.*}")
                 [[ $t ]] && echo "$t $f"
             done | sort $sort_arg | cut -f2- -d' ')

    # Move the most recent file from the FULLRES directory
    # to the OUTBOX and make it the first file in the upload
    # list. If the upload fails, this file will end up being
    # sorted with the rest on the next attempt.
    firstfile="$(ls -t -1 $FULLRES | tail -n 1)"
    [[ $firstfile ]] && {
        mv -v "$FULLRES/$firstfile" "$OUTBOX"
        touch "$OUTBOX/$firstfile"
    }

    cat<<EOF > $cmdfile
set ftp:ssl-allow no
set ftp:use-abor no
set ftp:use-allo no
set ftp:use-feat no
set ftp:use-size yes
set ftp:sync-mode off
set net:timeout 1m
set xfer:log no
open $RACS_FTP_SERVER
cd /outgoing/$ID
mget -E -O $INBOX/ updates fullres.txt
cd /incoming/$ID
mput -c -E $firstfile ${files[*]}
bye
EOF

    # Start the file transfer
    lftp -f $cmdfile &

    # Wait for the file transfer to complete. Running lftp
    # asynchronously allows us to be interrupted by the
    # PPP_TIMELIMIT alarm immediately.
    ftp_pid=$!
    wait $ftp_pid
    ftp_pid=
fi

# Cancel the time-limit alarm
trap - ALRM
kill $alarm_pid 2> /dev/null

cleanup_and_shutdown
