THIS=${0##*/}

err ()  { echo "$*"   | fold -s -w ${COLUMNS:-80} >&2; }
errn () { printf "$*" | fold -s -w ${COLUMNS:-80} >&2; }

usage () {
    synopsis="$@"
    err "Usage:  $THIS $synopsis"
    err "See $THIS(1) man file for details."
}

# Portable which(1).
pathfind () {
    ifs_save="$IFS"
    IFS=:
    for _p in $PATH; do
        if [ -x "$_p/$*" ] && [ -f "$_p/$*" ]; then
            IFS="$OLDIFS"
            return 0
        fi
    done
    IFS="$ifs_save"
    return 1
}

if pathfind iconv; then
    alias to_utf8='iconv -t utf-8'
    alias from_utf8='iconv -t utf-8'
else
    err "Warning:  iconv not present.  Assuming UTF-8 character encoding."
    alias to_utf8='cat'
    alias from_utf8='cat'
fi

for p in pandoc $REQUIRED; do
    pathfind $p || {
        err "You need '$p' to use this program!"
        exit 1
    }
done
