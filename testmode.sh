#!/bin/bash
#
# System test script
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

camera_menu ()
{
    idx="$1"
    i=$((idx - 1))
    sw="${RACS_CAMERA_POWER[i]}"

    while :; do
        if power_test $sw; then
            power=("Off" "Turn camera off")
        else
            power=("On" "Turn camera on")
        fi

        choice=$(whiptail --title "Camera-${idx} Test" \
                          --backtitle "RACS 2.0" \
                          --nocancel \
                          --menu "Choose an option" 15 45 8 \
                          "<--Back" "Exit this menu" \
                          "${power[@]}" \
                          "Snapshot" "Take a snapshot" 3>&1 1>&2 2>&3)
        [[ "$?" = "0" ]] || return

        case "$choice" in
            "<--Back")
                return
                ;;
            On)
                power_on $sw
                wait_for_camera -v "camera-${idx}" $RACS_CAMERA_BOOTTIME |\
                    whiptail --gauge "Waiting for camera to start..." 6 50 0
                camera_up "camera-${idx}" || {
                    whiptail --title ERROR \
                             --backtitle "RACS 2.0" \
                             --msgbox "Camera-${idx} not found!" 8 50
                    power_off $sw
                }
                ;;
            Off)
                power_off $sw
                ;;
            Snapshot)
                if power_test $sw; then
                    snapshot.sh -v camera-$idx 2> /tmp/snap.out |\
                        whiptail --title Snapshot \
                                 --backtitle "RACS 2.0" \
                                 --gauge "Taking a snapshot ..." 6 50 0
                    whiptail --title "Snapshot complete" \
                             --backtitle "RACS 2.0" \
                             --textbox /tmp/snap.out 15 60
                else
                    whiptail --title ERROR \
                             --backtitle "RACS 2.0" \
                             --msgbox "You must power-on the camera first!" \
                             8 50
                fi
                ;;
        esac
    done
}

main_menu ()
{
    if ppp_check; then
        ppp=("PPP-down" "Stop PPP connection")
    else
        ppp=("PPP-up" "Start PPP connection")
    fi

    cameras=()
    for ((i = 0; i < RACS_NCAMERAS; i++)); do
        idx=$((i+1))
        cameras+=("Camera-${idx}" "Test camera $idx")
    done

    choice=$(whiptail --title "Test Menu" \
                      --backtitle "RACS 2.0" \
                      --cancel-button "Exit" \
                      --menu "Choose an option" 15 45 8 \
                      "${cameras[@]}" \
                      "${ppp[@]}" \
                      "Upload" "Upload contents of OUTBOX" \
                      "ADC" "Read A/D data" 3>&1 1>&2 2>&3)
    rval=$?
    echo "$choice"
    return $rval
}

start_ppp ()
{
    [[ -e /dev/ttyUSB0 ]] || {
        power_on PA9
        file_wait -v /dev/ttyUSB0 30 |\
            whiptail --gauge "Waiting for USB-serial adapter..." 6 50 0
    }

    [[ ! -e /dev/ttyUSB0 ]] && {
        whiptail --title ERROR \
                 --backtitle "RACS 2.0" \
                 --msgbox "USB-serial device not found!" 8 50
        return 1
    }

    power_on "$RACS_MODEM_POWER"
    sudo pon iridium persist
    ppp_wait -v 120 |\
        whiptail --gauge "Waiting for PPP link..." 6 50 0
    ppp_check || {
        whiptail --title ERROR \
                 --backtitle "RACS 2.0" \
                 --msgbox "PPP link failed!" 8 50
        sudo poff iridium
        return 1
    }

    return 0
}

stop_ppp ()
{
    sudo poff iridium
}

adc ()
{
    t="${1:-10}"
    n=$((t * 2))
    adcfg=
    [[ -f "$CFGDIR/adc.yml" ]] && adcfg="$CFGDIR/adc.yml"
    adread --interval=1s $adcfg > $OUTBOX/adc.csv &
    child=$!
    for ((i = 0; i < n; i++)); do
        sleep 0.5
        echo $(( i*100/(n-1) ))
    done | whiptail --gauge "Collecting $t seconds of A/D data ..." 6 50 0
    kill $child
    wait $child
    whiptail --title "A/D Output" \
             --backtitle "RACS 2.0" \
             --textbox $OUTBOX/adc.csv 15 60
}

upload_outbox ()
{
    (
        cd $OUTBOX
        zip_non_jpeg
        wput --tries=1 -v --disable-tls \
             -B -R * ftp://$RACS_FTP_SERVER/incoming/$ID/
    )
}

choice=$(main_menu)
while [[ $? = 0 ]]; do
    case "$choice" in
        Camera-*)
            idx=$(cut -f2 -d- <<< "$choice")
            camera_menu $idx
            ;;
        PPP-up)
            start_ppp
            ;;
        PPP-down)
            stop_ppp
            ;;
        Upload)
            upload_outbox
            ;;
        ADC)
            adc 10
            ;;
    esac
    choice=$(main_menu)
done

rm -f $RACS_SESSION_LOG
