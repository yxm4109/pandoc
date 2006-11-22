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
    alias _to_utf8='iconv -t utf-8'
    alias _from_utf8='iconv -t utf-8'
else
    err "Warning:  iconv not present.  Assuming UTF-8 character encoding."
    alias _to_utf8='cat'
    alias _from_utf8='cat'
fi

THIS_TEMPDIR=
trap '
    exitcode=$?
    [ -z $THIS_TEMPDIR ] || rm -rf $THIS_TEMPDIR ||:
    exit $exitcode
' INT QUIT TERM EXIT

ensure_tempdir () {
    while [ -z "$THIS_TEMPDIR" ]; do
        set -- $1
        t=${1:-$THIS.$$}
        if ! [ -d ${TMPDIR-/tmp}/$t ]; then
            THIS_TEMPDIR=${TMPDIR-/tmp}/$t
	    mkdir $THIS_TEMPDIR || THIS_TEMPDIR=
        fi
        break
    done

    if [ -z "$THIS_TEMPDIR" ]; then
        err "Couldn't create a temporary directory; aborting"
        exit 1
    fi
}

safein () {
    [ -n "$1" ] || set --  # safe-guarded against an "" argument
    _to_utf8 "$@"
}

safeout () {
    # No argument: source is stdin, destination is stdout
    # Single argument: source is stdin, destination is $1
    # Two arguments: sourc is $1, destination is $2
    if [ -z "$1" ]; then
	_from_utf8
	return
    fi

    if [ -z "$2" ]; then
        ensure_tempdir
	src=$THIS_TEMPDIR/STDIN.$$
	dest="$1"
	_from_utf8 >$src
    else
	src="$1"
	dest="$2"
    fi

    is_target_exists=
    if [ -f "$dest" ]; then
	is_target_exists=1
	mv -f "$dest" "$dest~"
    fi

    mv -f "$src" "$dest"

    errn "Created '$dest'"
    [ -z "$is_target_exists" ] || {
	errn " (previous file has been backed up as '$dest~')"
    }
    err .
}

for p in pandoc $REQUIRED; do
    pathfind $p || {
        err "You need '$p' to use this program!"
        exit 1
    }
done
