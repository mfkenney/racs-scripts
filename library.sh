#!/bin/bash

: ${TSCTL=/usr/local/bin/tsctl}

: ${RACS_SESSION_LOG="$HOME/OUTBOX/session.log"}

camera_up ()
{
    curl --connect-timeout 2 -s -X HEAD http://$1/index.html > /dev/null
}

power_on ()
{
    local arg

    for arg
    do
        $TSCTL @localhost DIO setasync "$arg" HIGH
    done
}

power_off ()
{
    local arg

    for arg
    do
        $TSCTL @localhost DIO setasync "$arg" LOW
    done
}

power_test ()
{
    local state

    state=$($TSCTL @localhost DIO getasync $1|cut -f2 -d= 2> /dev/null)
    [ "$state" = "HIGH" ]
}

wait_for_camera ()
{
    local cam twait verbose limit

    verbose=
    if [[ "$1" = "-v" ]]; then
        verbose=1
        shift
    fi
    cam="$1"
    twait="$2"

    limit=$(($(date +%s) + twait))

    until camera_up $cam
    do
        (($(date +%s) > limit)) && break
        [[ "$verbose" ]] && \
            echo "$(( 100 - (limit - $(date +%s))*100/twait ))"
        sleep 2
    done
    [[ "$verbose" ]] && echo "100"
    camera_up $cam
}

log_event ()
{
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" >> $RACS_SESSION_LOG
}

# Remove all files more than $age (days, hours, or minutes) old
clean_dir ()
{
    local dir age val opt mult

    dir="$1"
    age="$2"
    val="${age%[a-z]*}"
    opt="-mtime"
    mult=1

    case "$arg" in
        *m)
            opt="-mmin"
            mult=1
            ;;
        *d)
            opt="-mtime"
            mult=1
            ;;
        *h)
            opt="-mmin"
            mult=60
            ;;
    esac

    find "$dir" -type f $opt "+$((val * mult))" -exec rm -f {} \;
}

# Archive all non-JPEG files in the current directory.
zip_non_jpeg ()
{
    local prefix name files

    prefix="${1:-metadata}"
    name="${prefix}_$(date +'%Y%m%d_%H%M%S').zip"
    files=()
    for f in *; do
        case "$f" in
            *.jpg|*.zip);;
            *)files+=("$f") ;;
        esac
    done
    zip -m -T "$name" "${files[@]}" 1>&2 && echo "$name"
}

# Wait for PPP link or timeout
ppp_wait ()
{
    local n verbose limit

    verbose=
    if [[ "$1" = "-v" ]]; then
        verbose=1
        shift
    fi

    n=$1
    [[ $n ]] || return 1
    limit=$n
    while sleep 1; do
        /sbin/ifconfig ppp0 2> /dev/null | grep addr 1> /dev/null 2>&1 && break
        if ((--n <= 0)); then
            return 1
        fi
        [[ "$verbose" ]] && \
            echo "$(( (limit - n)*100/limit ))"
    done
    [[ "$verbose" ]] && echo "100"
    return 0
}

ppp_check ()
{
    /sbin/ifconfig ppp0 2> /dev/null | grep addr 1> /dev/null 2>&1
}

# Wait for a file to appear or timeout
file_wait ()
{
    local n file verbose limit

    verbose=
    if [[ "$1" = "-v" ]]; then
        verbose=1
        shift
    fi

    file="$1"
    n=$2
    [[ $file && $n ]] || return 1
    limit=$n
    while sleep 1; do
        [[ -e "$file" ]] && break
        if ((--n <= 0)); then
            return 1
        fi
        [[ "$verbose" ]] && \
            echo "$(( (limit - n)*100/limit ))"
    done
    [[ "$verbose" ]] && echo "100"
    return 0
}
