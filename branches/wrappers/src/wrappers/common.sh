THIS=${0##*/}

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

_iconv () {
    if [ -z "$ICONV_AVAIL" ] || pathfind iconv; then
	ICONV_AVAIL=yes
    fi

    if [ -z "$1" ]; then
	set --
    fi

    if [ "$ICONV_AVAIL" = "yes" ]; then
	iconv "$@"
    else
	cat "$1"
    fi
}

safein () {
    _iconv "$1" -t utf-8
}

safeout () {
    if [ -z "$1" ]; then
	_iconv -f utf-8
	return
    fi

    if [ -z "$2" ]; then
	src=${TMPDIR-/tmp}/${THIS}.$$
	dest="$1"
	trap "status=$?; rm -rf $src; exit $status" EXIT INT TERM
	_iconv -f utf-8 >$src
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

    printf "Created $dest" >&2
    [ -z "$is_target_exists" ] || {
	printf " (previous file has been backed up as '$dest~')" >&2
    }
    echo >&2 .
}

for p in pandoc $REQUIRED; do
    pathfind $p || {
        echo >&2 "You need '$p' to use this program!"
        exit 1
    }
done
