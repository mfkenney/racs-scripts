#!/bin/bash
#
# Merge A/D data with session log. This is useful for
# correlating the battery current measurements with
# various events.
#

LOG=session.log
ADC=adc.csv

# Need to use GNU date
if which gdate 1> /dev/null 2>&1; then
    DATE=gdate
else
    DATE=date
fi

# Convert date/time in session-log to POSIX timestamps
# and merge with ADC data file. CSV header is removed.
while IFS=, read dt event; do
    secs=$($DATE -d "$dt" --utc +%s)
    echo "$secs,0,$event"
done < <(sed -e 's/\[\(.*\)\] \(.*\)$/\1,\2/' $LOG) |\
    sort -m --key=1,1 -n --field-separator=, - <(sed -n -e '2,$p' $ADC)
