# As we may allow multiple filenames with white spaces we should
# extract the PANDOC_OPTS part sensitively.
NEWLINE='
'
OLDIFS="$IFS"
IFS="$NEWLINE"

infile_all=
while [ $# -gt 0 ]; do
    case "$1" in
    --)
	shift
	PANDOC_OPTS="$@"
	break ;;
    "")	;; # skip "" arguments
     *)	infile_all="${infile_all}${NEWLINE}${1}" ;;
    esac
    shift
done

set -- $infile_all
IFS="$OLDIFS"
# Now "$@" holds the filenames without '--' delimiter.

PANDOC_OPTS=${PANDOC_OPTS:+$PANDOC_OPTS}

infile="$1"
if [ -n "$SINGLE_FILE_INPUT" ]; then
    if [ -n "$2" ]; then
	shift
	echo >&2 "Warning:  excessive arguments '$@' will be ignored."
    fi
else
    for f; do
	if [ -n "$f" ] && ! [ -f "$f" ]; then
	    echo >&2 "'$f' not found"
	    exit 1
	fi
    done
fi

if [ -z "$outfile" ]; then
    if [ -n "$1" ]; then
        outfile="${1%.*}$EXTENSION"
    else
        outfile="stdin$EXTENSION" # input is STDIN, since no argument given
    fi
else
    case "$outfile" in
    *.*) ;; # skip appending extension if one is already present
    *)   outfile="${outfile%.*}${EXTENSION}";;
    esac
fi
