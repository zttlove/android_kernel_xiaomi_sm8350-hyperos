# ReKernel-X 内核树集成

## 结构

- `rkx.c`：模块入口
- `rkx_genl.c`：Generic Netlink 通信
- `rkx_binder.c`：Binder 钩子
- `rkx_binder_kp.c`：Binder 异步缓存清理（kprobe）
- `rkx_free_async.c`：异步清理管理
- `rkx_signal.c`：信号钩子
- `rkx_netfilter.c`：网络钩子
- `rkx_netuid.c`：网络监控 UID 管理
- `rkx_frozen.c`：进程冻结状态判断
- `rkx.h`：公共头文件与 ABI 定义
- `rkx_log.h`：日志宏
- `Makefile`：内核树编译规则

本目录来自官方 `myflavor/ReKernel-X` v1.6 的 `LKM-Source`，已经接入本仓库的
Kconfig/Makefile。`CONFIG_REKERNEL_X=y` 时会编译进内核，启动时直接注册
`rekernel_x2` Generic Netlink 家族；设为 `m` 时才会生成可加载模块。

本设备使用 5.4.302 内核。官方项目声明的最低版本是 5.10，因此本目录包含
针对本内核 Binder hook 签名和头文件顺序的兼容处理；必须先通过目标内核的
编译和临时启动测试，不能把上游的 5.10+ 兼容性说明直接当作 5.4 的稳定性保证。

## 编译

可通过 `ddk-lkm.yml` 工作流编译，或在 DDK 容器中手动编译

如需单独构建模块，可将配置改为 `CONFIG_REKERNEL_X=m` 后执行：

```sh
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    drivers/rekernel_x/built-in.a
```

## Dynamic Android 17 compatibility update

Upstream release: `1.6`, commit `afb5e6bc62c6b9702c823009566a58b2e53b7797`
(published 2026-09-20). This imports the LKM source, not a userspace APK or
loadable module. The in-tree 5.4 Binder hook signature and header prerequisites
remain adapted to this Xiaomi tree. The upstream Binder async worker now holds
a process temporary reference until cleanup completes and leaves transactions
queued when work allocation fails.

The network compatibility fix resolves the receiving IPv4/IPv6 TCP socket when
early demux did not attach one. Loopback always resolves the receiver because an
attached socket can belong to the sender. A referenced lookup is released with
sock_gen_put, and only full sockets expose their cached sk_uid. Existing TCP
payload/SYN/FIN/RST notification semantics and the monitored UID filter remain;
pure ACK, UDP and unmonitored UIDs do not trigger network events. Validating TCP
header lengths precedes the new lookup. All paths still return NF_ACCEPT.

NoActive must register the app UID and consume the existing rekernel_x2/events
ABI; ReKernel-X reports events, while NoActive decides whether to thaw apps.
No system settings, NoActive rules, userspace modules or device partitions are
changed by this source update.

Initial device baseline: mars, Android 17 / HyperOS .26,
5.4.302-Dynamic-gdb11dd6. Generic Netlink family 23/group 10 was available;
Binder events were observed. A monitored synthetic UID 19999 received 16 TCP
bytes on loopback, but generated zero network events. The temporary monitor UID
was removed after the test. WeChat was frozen and had CLOSE_WAIT sockets with
unread bytes. The synthetic result proves a missed event path; actual WeChat
notification recovery and regressions must be checked on the candidate kernel
before declaring the user-visible problem fixed or publishing it.
