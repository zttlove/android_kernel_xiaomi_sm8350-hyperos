#!/bin/sh
# SPDX-License-Identifier: GPL-2.0

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
	echo "用法: $0 <.config 路径> [旧版本号]" >&2
	echo "示例: $0 out/.config" >&2
	exit 2
fi

config_file=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_tree=$(CDPATH= cd -- "$script_dir/.." && pwd)

if [ ! -f "$config_file" ]; then
	echo "配置文件不存在: $config_file" >&2
	exit 2
fi

if [ -n "${SOURCE_COMMIT:-}" ]; then
	commit_full=$SOURCE_COMMIT
else
	commit_full=$(git -C "$source_tree" rev-parse --verify HEAD)
fi

case "$commit_full" in
	*[!0-9A-Fa-f]*|'')
		echo "源码提交标识必须是十六进制 Git 哈希" >&2
		exit 2
		;;
	???????*) ;;
	*)
		echo "无法取得至少 7 位的源码提交标识" >&2
		exit 2
		;;
esac

commit_id=$(printf '%.7s' "$commit_full")
local_version="-Dynamic-g${commit_id}"

bash "$source_tree/scripts/config" --file "$config_file" \
	--set-str LOCALVERSION "$local_version" \
	--disable LOCALVERSION_AUTO

echo "CONFIG_LOCALVERSION=$local_version"
echo "预期内核名称: <内核版本>${local_version}"
