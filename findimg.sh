#!/bin/bash
#
# Locate an image in the archive and copy to the OUTBOX
#
# Exit status:
#    0  success
#    1  image name not provided
#    2  image not found
#
export PATH=$HOME/bin:$PATH

CFGDIR="$HOME/config"
ARCHIVEDIR="$HOME/archive"
OUTBOX="$HOME/OUTBOX"

[[ -e $CFGDIR/settings ]] && . $CFGDIR/settings
[[ -e $HOME/bin/library.sh ]] && . $HOME/bin/library.sh

name="$1"
[[ "$name" ]] || exit 1

# Name is of the form <CAMERA>_<YYYYmmdd>_<HHMMSS>.jpg
# Extract the components
set -- $(basename $name .jpg | tr '_' ' ')
d="$(date -d $2 +%Y/%m/%d)"
img="$ARCHIVEDIR/$1/$d/$name"

if [[ -e "$img" ]]; then
    cp $img $OUTBOX
else
    log_event "WARNING" "Image not found ($name)"
    exit 2
fi

exit 0
