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
