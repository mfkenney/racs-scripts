#!/bin/bash
#
# System test script
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[ -e $CFGDIR/settings ] && . $CFGDIR/settings
[ -e $HOME/bin/library.sh ] && . $HOME/bin/library.sh

camera_menu ()
{
    idx="$1"
    i=$((idx - 1))
    sw="${RACS_CAMERA_POWER[i]}"

    while true
    do
        if power_test $sw
        then
            state="Off"
            label="Turn camera off"
        else
            state="On"
            label="Turn camera on"
        fi
        choice=$(whiptail --title "Camera-${idx} Test" \
                          --menu "Choose an option" 15 45 8 \
                          "<--Back" "Exit this menu" \
                          "$state" "$label" \
                          "Snapshot" "Take a snapshot" 3>&1 1>&2 2>&3)
        [ "$?" = "0" ] || return

        case "$choice" in
            "<--Back")
                return
                ;;
            On)
                power_on $sw
                wait_for_camera "camera-${idx}" $RACS_CAMERA_BOOTTIME yes |\
                    whiptail --gauge "Waiting for camera to start..." 6 50 0
                ;;
            Off)
                power_off $sw
                ;;
            Snapshot)
                if power_test $sw
                then
                    out="$(snapshot.sh camera-${idx} 2>&1)"
                    whiptail --title "Snapshot output" \
                             --msgbox "$out" 10 50
                else
                    whiptail --title ERROR \
                             --msgbox "You must power-on the camera first!" \
                             8 50
                fi
                ;;
        esac
    done
}

main_menu ()
{
    if /sbin/ifconfig ppp0 1> /dev/null 2>&1
    then
        op="PPP up"
        label="Start PPP connection"
    else
        op="PPP down"
        label="Stop PPP connection"
    fi
    choice=$(whiptail --title "RACS 2.0 Test Menu" \
                      --menu "Choose an option" 15 45 8 \
                      "Camera 1" "Test camera 1" \
                      "Camera 2" "Test camera 2" \
                      "Camera 3" "Test camera 3" \
                      "$op" "$label" \
                      "ADC" "Read A/D data" 3>&1 1>&2 2>&3)
    echo "$choice"
}
