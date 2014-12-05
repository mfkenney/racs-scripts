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

camera="$1"
[ -z "$camera" ] && exit 1

# Full pathname for the snapshot file
img="$SNAPSHOTDIR/${camera}.jpg"
# Remove it if it already exists. VLC will overwrite an
# exiting file but will not update the creation time
# which will result in an erroneous EXIF timestamp.
rm -f $img

logger -p "local0.info" "Taking a snapshot from $camera"
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
    jhead -mkexif -dsft $img
    # Rescale for upload
    djpeg "$img" | pnmscale $RACS_SCALE | cjpeg > $OUTBOX/$base
    # Transfer EXIF header to the scaled image
    jhead -te $img $OUTBOX/$base
    # Archive the snapshot using a date/time based directory
    # scheme.
    here=$(pwd)
    cd $SNAPSHOTDIR
    jhead -nf$ARCHIVEDIR/%f/%Y/%m/%d/%f_%Y%m%d_%H%M%S $base
    cd $here
    # Rename the scaled image to match
    cd $OUTBOX
    jhead -nf%f_%Y%m%d_%H%M%S $base
    cd $here
    logger "Archived snapshot from $camera"
else
    logger -p "local0.warning" "Snapshot failed ($camera)"
    exit 2
fi

exit 0
