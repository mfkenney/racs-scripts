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
[ -e $HOME/bin/library.sh ] && . $HOME/bin/library.sh

# Log a status message and optionally write a
# "percent done" value to stdout. The latter
# item is used when running this script from
# whiptail or dialog (TUI programs)
status ()
{
    msg="$1"
    pct="$2"
    log_event "INFO" "$msg"
    if [ -n "$pct" ]
    then
        echo "$pct"
    fi
}

# Create an Exiv2 command file to add metadata to
# each snapshot image. The file is only created
# if it doesn't already exist.
create_metadata ()
{
    camera="$1"
    mf="$CFGDIR/metadata_${camera}.txt"
    if [ ! -e "$mf" ]
    then
        src="$(hostname -s):$camera"
        cat<<EOF > "$mf"
set Exif.Image.Make Ascii "Stardot"
set Exif.Image.Model Ascii "Stardot Netcam XL"
set Iptc.Application2.Program String "RACS"
set Iptc.Application2.ProgramVersion String "2.0"
set Iptc.Application2.Source String $src
set Exif.Photo.UserComment Comment charset=Ascii Taken by $src
EOF
    fi
    echo "$mf"
}


camera="$1"
[ -z "$camera" ] && exit 1

verbose="$2"

mf=$(create_metadata "$camera")

# Full pathname for the snapshot file
img="$SNAPSHOTDIR/${camera}.jpg"
# Remove it if it already exists. VLC will overwrite an
# existing file but will not update the creation time
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
    comment="$(hostname -s):$camera"
    base="$(basename $img)"
    # Add EXIF date/time to the image file
    status "Adding EXIF header" ${verbose:+50}
    jhead -mkexif -dsft $img 1>&2
    # Use exiv2 to add some additional metadata
    exiv2 -k -m "$mf" $img 1>&2
    # Rescale for upload
    status "Rescaling image" ${verbose:+55}
    djpeg "$img" | pnmscale $RACS_SCALE | cjpeg > $OUTBOX/$base
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
    jhead -nf%f_%Y%m%d_%H%M%S_scaled $base 1>&2
    cd $here
    status "Archived snapshot from $camera" ${verbose:+100}
else
    log_event "Snapshot failed ($camera)"
    exit 2
fi

exit 0
