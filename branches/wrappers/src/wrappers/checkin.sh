for f; do
    if [ -n "$f" ] && ! [ -f "$f" ]; then
        err "'$f' not found"
        exit 1
    fi
done
