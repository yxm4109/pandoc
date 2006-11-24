SYNOPSIS=${SYNOPSIS:-"[-h|?] [input_file]..."}

while getopts o:h opt; do
    case $opt in
    ?|h) usage "$SYNOPSIS"; exit 2 ;;
    esac
done

shift $(($OPTIND - 1))
