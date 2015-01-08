#!/bin/bash
#
# Take a snapshot from one of the cameras, archive it, and save
# a scaled-down version to the OUTBOX.
#
export PATH=$HOME/bin:$PATH

CFGDIR="$HOME/config"
SNAPSHOTDIR="$HOME/snapshots"
ARCHIVEDIR="$HOME/archive"
OUTBOX="$HOME/OUTBOX"
RACS_SCALE="0.5"
RACS_STREAM_TIME=1

[ -e $CFGDIR/settings ] && . $CFGDIR/settings

status ()
{
    msg="$1"
    pct="$2"
    logger -p "local0.info" "$msg"
    if [ -n "$pct" ]
    then
        echo "$pct"
        echo "XXX"
        echo "$msg"
        echo "XXX"
    fi
}

camera="$1"
[ -z "$camera" ] && exit 1

verbose="$2"

# Full pathname for the snapshot file
img="$SNAPSHOTDIR/${camera}.jpg"
# Remove it if it already exists. VLC will overwrite an
# exiting file but will not update the creation time
# which will result in an erroneous EXIF timestamp.
rm -f $img

status "Taking a snapshot from $camera" ${verbose:+0}
cvlc -I dummy -q --run-time=$RACS_STREAM_TIME \
     "http://${camera}/nph-mjpeg.cgi?0" \
     --vout=dummy \
     --video-filter=scene \
     --scene-format=jpg \
     --scene-prefix=${camera} \
     --scene-replace \
     --scene-path=$SNAPSHOTDIR \
     vlc://quit 2> /dev/null

if [ -e "$img" ]
then
    base="$(basename $img)"
    # Add EXIF date/time to the image file
    status "Adding EXIF header" ${verbose:+50}
    jhead -mkexif -dsft $img 1>&2
    # Rescale for upload
    status "Rescaling image" ${verbose:+55}
    djpeg "$img" | pnmscale $RACS_SCALE | cjpeg > $OUTBOX/$base 1>&2
    # Transfer EXIF header to the scaled image
    jhead -te $img $OUTBOX/$base 1>&2
    # Archive the snapshot using a date/time based directory
    # scheme.
    status "Archiving original image" ${verbose:+95}
    here=$(pwd)
    cd $SNAPSHOTDIR
    jhead -nf$ARCHIVEDIR/%f/%Y/%m/%d/%f_%Y%m%d_%H%M%S $base 1>&2
    cd $here
    # Rename the scaled image to match
    cd $OUTBOX
    jhead -nf%f_%Y%m%d_%H%M%S $base 1>&2
    cd $here
    status "Archived snapshot from $camera" ${verbose:+100}
else
    logger -p "local0.warning" "Snapshot failed ($camera)"
    exit 2
fi

exit 0
