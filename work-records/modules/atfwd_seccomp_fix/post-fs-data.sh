#!/system/bin/sh
# 在挂载覆盖文件之前选择策略；此阶段不调用会等待 init 的服务控制命令。
MODDIR=${0%/*}
/system/bin/sh "$MODDIR/control.sh" boot
