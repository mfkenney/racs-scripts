#!/bin/bash

: ${TSCTL=/usr/local/bin/tsctl}

: ${RACS_SESSION_LOG="$HOME/OUTBOX/session.log"}

camera_up ()
{
    curl --connect-timeout 2 -s -X HEAD http://$1/index.html > /dev/null
}

power_on ()
{
    for arg
    do
        $TSCTL @localhost DIO setasync "$arg" HIGH
    done
}

power_off ()
{
    for arg
    do
        $TSCTL @localhost DIO setasync "$arg" LOW
    done
}

power_test ()
{
    state=$($TSCTL @localhost DIO getasync $1|cut -f2 -d= 2> /dev/null)
    [ "$state" = "HIGH" ]
}

wait_for_camera ()
{
    cam="$1"
    twait="$2"
    verbose="$3"
    limit=$(($(date +%s) + twait))

    until camera_up $cam
    do
        (($(date +%s) > limit)) && break
        [ -n "$verbose" ] && \
            echo "$(( 100 - (limit - $(date +%s))*100/twait ))"
        sleep 2
    done
    [ -n "$verbose" ] && echo "100"
    camera_up $cam
}

log_event ()
{
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" >> $RACS_SESSION_LOG
}

clean_dir ()
{
    dir="$1"
    age="$2"
    find "$dir" -type f -mtime "$age" -exec rm -f {} \;
}
