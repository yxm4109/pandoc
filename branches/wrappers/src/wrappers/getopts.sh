outfile=
while getopts o:h opt; do
    case $opt in
    o) outfile="$OPTARG" ;;
    h) echo >&2 "Usage: $THIS [-o output_file] [-h] [input_file]"; exit 2 ;;
    esac
done

shift $(($OPTIND - 1))
