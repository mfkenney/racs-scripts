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

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

# Log a status message and optionally write a
# "percent done" value to stdout. The latter
# item is used when running this script from
# whiptail or dialog (TUI programs)
status ()
{
    msg="$1"
    pct="$2"
    log_event "INFO" "$msg"
    [[ "$pct" ]] && echo "$pct"
}

# Create an Exiv2 command file to add metadata to
# each snapshot image. The file is only created
# if it doesn't already exist.
create_metadata ()
{
    camera="$1"
    mf="$CFGDIR/metadata_${camera}.txt"
    if [[ ! -e "$mf" ]]; then
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

verbose=
if [[ "$1" = "-v" ]]; then
    verbose="yes"
    shift
fi

camera="$1"
[[ "$camera" ]] || exit 1

# Optional power-switch name. If specified we will power
# the camera off after grabbing an image.
sw="$2"

mf=$(create_metadata "$camera")

# Full pathname for the snapshot file
img="$SNAPSHOTDIR/${camera}.jpg"

status "Taking a snapshot from $camera" ${verbose:+0}
curl -s -X GET "http://${camera}/nph-jpeg.cgi" > $img

if [[ "$sw" ]]; then
    log_event "INFO" "Power-off $camera"
    power_off "$sw"
fi

if [[ -e "$img" ]]; then
    base="$(basename $img)"
    # Add EXIF date/time to the image file
    status "Adding EXIF header" ${verbose:+25}
    jhead -mkexif -dsft $img 1>&2
    # Use exiv2 to add some additional metadata
    exiv2 -k -m "$mf" $img 1>&2
    # Rescale for upload
    status "Rescaling image" ${verbose:+50}
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
