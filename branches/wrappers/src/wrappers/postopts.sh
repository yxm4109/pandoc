# Parse wrapper and wrappee (pandoc) arguments by taking
# into account that they may have white spaces.
pick="WRAPPER_ARGS"
while [ $# -gt 0 ]; do
    if [ "$pick" = "WRAPPER_ARGS" ]; then
        case "$1" in
        -*) pick="WRAPPEE_ARGS" ;;
        *)  cur=$(($cur + 1))
            if [ -n "$THIS_NARG" ] && [ $cur -gt $THIS_NARG ]; then
                err "Warning:  extra argument '$1' will be ignored."
                shift
                continue
            fi ;;
        esac
    fi
    # Pack args with NEWLINE to preserve spaces,
    # and put them into the picked variable.
    eval "$pick=\"\$${pick}${NEWLINE}${1}\""
    shift
done

# Honor PANDOC_OPTS if not overwritten in the command line.
if [ -z "$WRAPPEE_ARGS" ] && [ -n "$PANDOC_OPTS" ]; then
    eval "set -- $PANDOC_OPTS"
    # Pack opts with NEWLINE as the repack procedure expects this form.
    for opt; do
        WRAPPEE_ARGS="${WRAPPEE_ARGS}${NEWLINE}${opt}"
    done
fi

# Unpack filename arguments.  Now "$@" will hold the filenames.
oldifs="$IFS"; IFS="$NEWLINE"; set -- $WRAPPER_ARGS; IFS="$oldifs"
