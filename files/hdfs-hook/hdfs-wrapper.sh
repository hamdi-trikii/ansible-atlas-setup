#!/bin/bash
LINEAGE_CMD="/opt/apache-atlas-2.4.0/extractors/bin/hdfs-lineage.sh"
SUPPORTED_OPS="put copyFromLocal cp mv rm"

# Set Atlas env vars
export ATLAS_CONF_DIR="/opt/apache-atlas-2.4.0/conf"
export ATLAS_LOG_DIR="/opt/apache-atlas-2.4.0/logs"
export BASEDIR="/opt/apache-atlas-2.4.0/extractors"

echo "Wrapper called with args: $@"
operation=$(echo "$1" | sed 's/^-//')
src_path="$2"
dest_path="$3"
echo "Operation: $operation, Src: $src_path, Dest: $dest_path"

run_lineage() {
    op="$1"
    src="$2"
    dest="$3"
    echo "Running lineage for op: $op, src: $src, dest: $dest"
    if [ "$op" = "rm" ]; then
        "$LINEAGE_CMD" "-$op" "$src"
    else
        "$LINEAGE_CMD" "-$op" "$src" "$dest"
    fi
}

if echo "$SUPPORTED_OPS" | grep -w "$operation" > /dev/null; then
    if [ "$operation" = "rm" ] && [ -n "$src_path" ] && [ -z "$dest_path" ]; then
        echo "Calling run_lineage for rm"
        run_lineage "$operation" "$src_path"
    elif [ -n "$src_path" ] && [ -n "$dest_path" ]; then
        echo "Calling run_lineage for $operation"
        run_lineage "$operation" "$src_path" "$dest_path"
    else
        echo "Usage: hdfs dfs -$operation /srcPath [/destPath]"
        exit 1
    fi
else
    echo "Unsupported op, passing to hdfs: $@"
    /opt/hadoop-3.3.2/bin/hdfs dfs "$@"
fi
