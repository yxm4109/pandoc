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
        # If reached here reset (overwrite) PANDOC_OPTS and collect options.
        PANDOC_OPTS=
        for opt; do
	    PANDOC_OPTS="${PANDOC_OPTS}${OLDIFS}${opt}"
        done
	break ;;
    "")	;; # skip "" arguments
     *)	infile_all="${infile_all}${NEWLINE}${1}" ;;
    esac
    shift
done

set -- $infile_all
IFS="$OLDIFS"
# Now "$@" holds the filenames without '--' delimiter.

infile="$1"
if [ -n "$SINGLE_FILE_INPUT" ]; then
    if [ -n "$2" ]; then
	shift
	echo >&2 "Warning:  extra arguments '$@' will be ignored."
    fi
else
    for f; do
	if [ -n "$f" ] && ! [ -f "$f" ]; then
	    echo >&2 "'$f' not found"
	    exit 1
	fi
    done
fi

if [ -n "$outfile" ]; then
  case "$outfile" in
    *.*) ;; # skip appending extension if one is already present
    *)   outfile="${outfile%.*}${EXTENSION}";;
  esac
fi
