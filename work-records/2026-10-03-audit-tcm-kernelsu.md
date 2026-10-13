# TCM Socket SELinux 拒绝：统一模块修复记录

日期：2026-10-03（北京时间）
类型：非内核设备侧修复，使用已有 KernelSU 统一模块 `atfwd_seccomp_fix`，不修改内核源码。

## 设备与基线

| 项目 | 值 |
| --- | --- |
| 设备 | Xiaomi 11 Pro / `mars` |
| 系统 | Android 17 / HyperOS `OS4.0.0.26.XKACNXM` |
| SELinux | `Enforcing` |
| 相关服务 | `dpmd`、`dpmQmiMgr` |
| Socket | `/dev/socket/tcm`，标签 `vendor_dpmtcm_socket` |
| 应用 | `com.miui.passwords`，`TcmReceiver` |
| 模块版本 | `2.5.0-test`，`versionCode=9` |

## 根因证据

关闭 TCM 开关时，最近五分钟检测到 26 条相关拒绝。内核日志显示多个 `TcmReceiver` 调用域对 `/dev/socket/tcm` 执行 `sock_file write` 被拒绝，并造成 `audit_lost` 和 `audit: rate limit exceeded`。

实测确认的调用域为：

```text
platform_app_36
bluetooth
joyose_app
```

## 最小修复

TCM 开关开启后，模块在下次开机由 KernelSU 加载以下三条规则：

```text
allow platform_app_36 vendor_dpmtcm_socket sock_file write;
allow bluetooth vendor_dpmtcm_socket sock_file write;
allow joyose_app vendor_dpmtcm_socket sock_file write;
```

KernelSU 的 `sepolicy.rule` 语法要求将目标类型和 class 分开，不能使用标准 `.te` 中的 `target:class` 写法。初次测试的冒号格式被 KernelSU 忽略，已修正并重新验证。

规则受设备、ROM、Socket 标签、`dpmd` 和应用存在性检查保护。关闭开关只删除内容完全匹配的本模块规则；不关闭 SELinux，不修改 vendor 原文件，不写入系统分区，不修改用户数据。

## 实机验证

1. 模块默认新增 `tcm_enabled=0`，WebUI 提供独立的“MiuiPasswords TCM Socket 修复”开关。
2. 用户确认后开启开关，生成规则并重启设备。
3. 重启后状态为：

```text
tcm_enabled=1
tcm_rule=1
tcm_active=1
SELinux=Enforcing
```

4. 观察约 75 秒，`TcmReceiver` 与 `vendor_dpmtcm_socket` 匹配日志数量为 `0`，三个调用域均未再产生该类拒绝。
5. `audit_lost` 仍有增长，原因是系统中其他独立 SELinux 拒绝，例如 `com.miui.home` 连接 zygote、应用读取受限属性和 QQ 访问 proc/net；这些不属于本次 TCM 修复范围。

## 当前结论

TCM Socket 的三条最小规则已加载并通过本次窗口验证，原 TCM 拒绝日志已停止。`audit: rate limit exceeded` 不是全局消失，因为系统仍存在其他未处理的 SELinux 拒绝；不能将其余审计问题归因于 TCM 规则失败。

本记录不代表其他 SELinux 拒绝、系统耗电或内核源码问题已经修复。
