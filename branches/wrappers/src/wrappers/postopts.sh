# As we may allow multiple filenames with white spaces we should
# extract the PANDOC_OPTS part sensitively.
NEWLINE='
'
OLDIFS="$IFS"

infile_all=
ncur=$#
while [ $# -gt 0 ]; do
    case "$1" in
    -*)
        PANDOC_OPTS="$@"
        break ;;
     *)
        if [ -z "$THIS_NARG" ] || [ $(($ncur - $#)) -lt $THIS_NARG ]; then
            [ -n "$1" ] || continue # skip empty arguments
            infile_all="${infile_all}${NEWLINE}${1}"
        else
            err "Warning:  extra argument '$1' will be ignored."
        fi ;;
    esac
    shift
done

IFS="$NEWLINE"; set -- $infile_all; IFS="$OLDIFS"
# Now "$@" holds the filenames.
