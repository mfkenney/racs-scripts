#!/bin/bash
#
# Test power switch of RACS peripheral devices
#
export PATH=$HOME/bin:/usr/local/bin:$PATH

CFGDIR="$HOME/config"
OUTBOX="$HOME/OUTBOX"
INBOX="$HOME/INBOX"
ID="$(hostname -s)"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

tags=("Camera-1" "Camera-2" "EnetSwitch" "Modem" "Spare-1" "Spare-2" "Spare-3" "Spare-4")
switches=(${RACS_CAMERA_POWER[0]} ${RACS_CAMERA_POWER[1]} $RACS_ENET_POWER $RACS_MODEM_POWER 8160_LCD_D4 8160_LCD_D5 8160_LCD_D6 8160_LCD_D7)

check_state ()
{
    [[ "$1" ]] || return 1
    if power_test "$1"; then
        echo "ON"
    else
        echo "OFF"
    fi
}

# Find the index associated with a tag
find_index ()
{
    [[ "$1" ]] || return 1
    i=0
    for tag in "${tags[@]}"; do
        if [[ "$tag" = "$1" ]]; then
            echo $i
            return 0
        fi
        ((i++))
    done
    return 1
}

while :; do
    list=()
    for i in "${!tags[@]}"; do
        list+=("${tags[i]}" " " $(check_state "${switches[i]}"))
    done

    choice=$(whiptail --title "Power Switches" \
                      --backtitle "RACS 2.0" \
                      --cancel-button "Exit" \
                      --ok-button "Apply" \
                      --checklist "Set power-switch state" 15 50 12 \
                      "${list[@]}" 3>&1 1>&2 2>&3)
    [[ $? = 0 ]] || break

    # Create a bitmask containing the desired state of
    # each switch
    mask=0
    for tag in $choice; do
        # The selected tag values returned from whiptail
        # are quoted. We need to strip the quotes before
        # doing the string match in find_index.
        idx=$(find_index $(tr -d '"' <<<"$tag"))
        [[ $idx ]] && mask=$((mask | (1 << idx)))
    done

    # Use the mask to set the new state of the power
    # switches.
    for i in "${!switches[@]}"; do
        state=$((mask & (1 << i)))
        if ((state == 0)); then
            power_off "${switches[i]}"
        else
            power_on "${switches[i]}"
        fi
    done

done
