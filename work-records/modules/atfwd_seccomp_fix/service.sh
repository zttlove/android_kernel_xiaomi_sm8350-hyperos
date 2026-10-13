#!/system/bin/sh
# 补查后续模块是否重新写入属性，只执行一次，不建立常驻进程。
MODDIR=${0%/*}
/system/bin/sh "$MODDIR/control.sh" apply
