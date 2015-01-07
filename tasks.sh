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

logger -p "local0.info" "Powering on cameras"

# Start the A/D monitor
# TODO: add A/D config file
adread --interval=5s > $OUTBOX/adc.csv &
child=$!
# Power on the ethernet switch
power_on $RACS_ENET_POWER
# Power on the cameras
power_on "${RACS_CAMERA_POWER[@]}"

# Wait for all cameras to boot
n_up=0
twait=$(($(date +%s) + RACS_CAMERA_BOOTTIME))
while (("${#down[@]}" > 0))
do
    for host in "${down[@]}"
    do
        if camera_up $host
        then
            logger -p "local0.info" "$host ready"
            ((n_up++))
            up=("${up[@]}" "$host")
        else
            pool=("${pool[@]}" "$host")
        fi
    done
    # Exit the loop when all cameras are up or time has expired
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

# Power off the cameras
power_off "${RACS_CAMERA_POWER[@]}"
logger -p "local0.info" "Cameras powered off"

# TODO: Establish PPP link

# Sync clock with ntpdate
sudo ntpdate -b $RACS_NTP_SERVER 1> $OUTBOX/ntp.out 2>&1

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
    [ -e $INBOX/updates ] mv $INBOX/updates $CFGDIR
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

# Save the last 30 lines of the log to the OUTBOX
tail -n 30 /var/log/app.log > $OUTBOX/app.log

# Stop the A/D monitor and save the output to the OUTBOX
[ -n "$child" ] && kill -TERM $child

# Upload files from the OUTBOX. Files are removed after
# they are successfully transfered.
(
    if [ -n "$RACS_FTP_SERVER" ]
    then
        cd $OUTBOX
        gzip adc.csv app.log
        wput --disable-tls -B -R * ftp://$RACS_FTP_SERVER/incoming/$ID/
    fi
)

# Shutdown until next sample time
if [ -n "$RACS_NOSLEEP" ]
then
    :
else
    set_alarm.sh $RACS_INTERVAL
fi
