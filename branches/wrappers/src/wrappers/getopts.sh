outfile=
while getopts o:h opt; do
    case $opt in
    o) outfile="$OPTARG" ;;
    h) echo >&2 "Usage: $THIS [-o output_file] [-h] [input_file]"; exit 2 ;;
    esac
done

shift $(($OPTIND - 1))

infile=
ignored=
while [ -n "$1" ]; do
    case "$1" in
    --)
	shift
	PANDOC_OPTS="$@"
	break ;;
    *)
	if [ -z "$infile" ]; then
	    infile="$1"
	else
	    ignored="$ignored$1"
	fi ;;
    esac
    shift
done

if [ -n "$ignored" ]; then
    echo >&2 "Excessive arguments '$ignored' will be ignored!"
fi

PANDOC_OPTS=${PANDOC_OPTS:+$PANDOC_OPTS}

if [ -n "$infile" ] && ! [ -f "$infile" ]; then
    echo >&2 "'$infile' not found"
    exit 1
fi
