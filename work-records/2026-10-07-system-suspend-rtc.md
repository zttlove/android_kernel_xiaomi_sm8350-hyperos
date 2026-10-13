# `system_suspend` RTC 读取权限修复记录

日期：2026-10-07（北京时间）

类型：非内核设备侧修复，合并到已有 KernelSU 统一模块 `atfwd_seccomp_fix`。

模块版本：`2.6.0-test`，`versionCode=10`。

## 设备与基线

| 项目 | 值 |
| --- | --- |
| 设备 | Xiaomi 11 Pro / `mars` / `M2102K1AC` |
| 系统 | Android 17 / HyperOS `OS4.0.0.26.XKACNXM` |
| SELinux | `Enforcing` |
| 运行服务 | `/system/bin/hw/android.system.suspend-service`，域 `u:r:system_suspend:s0` |
| RTC | `rtc-pm8xxx`，`/sys/class/rtc/rtc0/wakeup16`，标签 `sysfs_rtc` |
| 当前内核 | `5.4.302-Dynamic-g2b51a08` 临时测试内核 |
| 源码分支 | `dynamic` |

## 根因证据

内核日志反复出现：

```text
avc: denied { read } ... comm="android.system."
scontext=u:r:system_suspend:s0
tcontext=u:object_r:sysfs_rtc:s0
```

被拒绝的文件包括 `name`、`active_count`、`last_change_ms`、`max_time_ms`、`total_time_ms`、`active_time_ms`、`event_count` 等 RTC 唤醒统计节点。同期出现：

```text
audit_lost=...
audit_rate_limit=5
audit_backlog_limit=64
audit: rate limit exceeded
```

`system_suspend` 的用户空间程序和 RTC sysfs 节点均正常存在，问题来自 ROM SELinux 策略缺少 `system_suspend -> sysfs_rtc` 文件读取权限。当前仓库内核配置和挂起实现不是这项拒绝的根因。

## 最小修复

在已有统一模块中新增独立开关“system_suspend RTC 读取权限”，只允许：

```te
allow system_suspend sysfs_rtc file getattr;
allow system_suspend sysfs_rtc file open;
allow system_suspend sysfs_rtc file read;
```

规则不允许写入、创建、删除、重标记或其他类型访问。开启前校验设备、Android 版本、SELinux 状态、`system_suspend` 服务和 `sysfs_rtc` 节点。开启后使用设备已有 `/data/adb/ksud sepolicy patch` 实时应用，同时写入模块策略供下次开机加载；关闭只撤销下次开机规则，当前开机已经合并的 SELinux 规则需要重启后恢复。

## 修改文件

- `work-records/modules/atfwd_seccomp_fix/control.sh`
- `work-records/modules/atfwd_seccomp_fix/module.prop`
- `work-records/modules/atfwd_seccomp_fix/customize.sh`
- `work-records/modules/atfwd_seccomp_fix/config/suspend_enabled`
- `work-records/modules/atfwd_seccomp_fix/webroot/app.js`
- `work-records/modules/atfwd_seccomp_fix/webroot/index.html`
- `work-records/modules/atfwd_seccomp_fix/README.md`
- `work-records/README.md`

没有修改内核源码、defconfig、`scripts/ak3`、系统分区或用户数据。

## 验证计划

1. 在 WSL 中执行 `bash -n control.sh`，检查脚本语法。
2. 使用当前 KernelSU 执行 `ksud sepolicy check`，确认三条规则可解析。
3. 更新同一模块文件，不创建第二个模块。
4. 设置 RTC 开关为 `1`，实时应用规则。
5. 检查 `ksud sepolicy patch` 成功、SELinux 仍为 `Enforcing`。
6. 观察新的 `dmesg`，确认 `system_suspend` 的 `sysfs_rtc` AVC 拒绝停止或明显减少。
7. 读取 `dumpsys suspend_control_internal`，确认 RTC 唤醒统计可读取。
8. 保持其他四个开关和现有服务状态不变。

## 未完成项目

- 还未完成重启后的持久化验证。
- 还未验证关闭开关并重启后原策略是否完全恢复。
- `audit_lost` 可能继续受到其他独立 SELinux 拒绝影响；不能仅以全局计数归零作为本项唯一验收条件。
- 当前手机仍运行临时测试内核，不能据此宣称最终 Release 内核已验证。

## 当前实机验证结果（2026-10-07 01:53，Asia/Shanghai）

- 已更新现有 `atfwd_seccomp_fix` 模块，版本为 `2.6.0-test`，没有创建第二个模块。
- 保留原有 ATFWD、traced、GNSS、TCM 开关和当前状态；新增 `suspend_enabled=1`。
- 当前模块策略文件为 6 条规则：原有 3 条 TCM 规则，加上本记录的 3 条 RTC 读取规则。
- `ksud sepolicy check` 通过；`ksud sepolicy patch` 实时应用成功。
- SELinux 仍为 `Enforcing`。
- SELinux 访问决策查询返回 `system_suspend -> sysfs_rtc:file` 已包含 `getattr`、`open`、`read` 权限。
- 开启前最后一批 `system_suspend` RTC AVC 拒绝出现在 dmesg 单调时间约 `9605.815`；随后连续观察约 20 秒，没有新增同类拒绝。
- 最后一次与该批拒绝同时出现的 `audit_lost`/`audit: rate limit exceeded` 也在约 `9605.815`；随后观察窗口没有新的全局 audit 超限记录。
- 模块只读诊断返回：`suspend_errors=0`；logcat 当前缓冲区未发现新的 `Error opening kernel wakelock stats`。
- `dumpsys suspend_control_internal` 可以读取 `alarmtimer` 和 PMIC RTC 唤醒统计表。
- 没有重启手机、刷写分区、修改内核源码或修改用户数据。

这证明实时策略已生效并停止了当前窗口内的 RTC 读取拒绝；重启后的持久化和关闭回滚仍需单独验证。
