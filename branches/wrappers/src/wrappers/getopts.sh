SYNOPSIS=${SYNOPSIS:-"[-o output_file] [-h] [input_file]..."}

outfile=
while getopts o:h opt; do
    case $opt in
    o) outfile="$OPTARG" ;;
    ?|h) usage "$SYNOPSIS"; exit 2 ;;
    esac
done

shift $(($OPTIND - 1))
