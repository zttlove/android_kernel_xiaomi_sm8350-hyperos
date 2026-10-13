# 非内核问题修复工作记录

本目录记录无法通过当前内核仓库源码直接修复的问题，以及在用户明确授权后使用 KernelSU 模块进行的设备侧临时修复。这里的模块文件用于复现、验证、回滚和追溯，不属于内核源码、defconfig、AK3 模板或手机系统镜像。

## 使用边界

- 只有在根因位于 `vendor`、`system_ext`、`product`、用户空间服务、厂商 seccomp 策略、init 配置、VINTF 清单或 ROM 组件，而当前仓库不包含相应源码时，才考虑使用模块临时处理。
- 模块不能把缺失的厂商接口变成内核功能，也不能替代应在完整 Android/vendor 源码中完成的永久修复。
- 模块只使用设备已有的 KernelSU 能力和系统命令，不私自安装依赖，不刷写 `boot`、`vendor`、`product`、`vbmeta`，不修改用户数据。
- 每个功能必须有独立开关、适配校验、日志证据、回滚方式和未测试范围；发现 ROM、设备、服务接口或文件哈希变化时应停止应用并重新分析。
- 模块文件中的脚本、策略和 WebUI 页面均按源码文件审查；启用、停用、重启服务和实机验证必须有用户授权。

## 当前记录

| 文件 | 内容 | 性质 |
| --- | --- | --- |
| `2026-10-01-vendor-atfwd-kernelsu.md` | `vendor.atfwd` seccomp 重启循环、`traced` 通道异常和统一模块的验证记录 | 非内核设备侧临时修复 |
| `2026-10-02-gnss-unified-module.md` | GNSS AIDL 客户端与 vendor HIDL 接口不匹配的分析、统一模块处理和回滚记录 | 非内核设备侧临时修复 |
| `2026-10-07-system-suspend-rtc.md` | `system_suspend` 读取 `sysfs_rtc` 被 SELinux 拒绝的证据、统一模块最小规则和实机验证记录 | 非内核设备侧临时修复 |
| `2026-10-07-module-default-off.md` | 统一模块新安装全部关闭、升级保留选择和日志建议边界，以及隔离验证结果 | 非内核模块行为修正 |
| `2026-10-07-module-policy-status.md` | TCM/RTC 重启提示误判、真实权限查询、旧备份禁用和本地/实机验证记录 | 非内核模块状态修正 |
| `modules/atfwd_seccomp_fix/` | 对应的 KernelSU 模块源码、五个独立开关、中文 WebUI、内核日志读取和只读诊断脚本 | 可审查的测试/回滚载荷 |

## 已记录的模块功能

- **ATFWD**：只在确认 ROM 策略哈希匹配时覆盖 `atfwd@2.0.policy`，增加已验证的 `gettid: 1` 规则，以处理服务的 seccomp `SIGSYS` 重启循环。
- **traced**：只处理已确认的 `traced.relay_producer_port=vsock://-1:2010`，保留本地追踪能力，不关闭 `persist.traced.enable`。
- **GNSS**：针对当前 ROM 中请求不存在的 `vendor.qti.gnss.ILocAidlGnss/default` 的 `loc_sys_service`，使用 ROM 已提供的跳过属性抑制无效请求，保留实际运行的 HIDL GNSS 服务；不声称实现 AIDL 接口。
- **内核日志与诊断**：只读取限定大小的 `dmesg`/`logcat` 快照，不清空、不轮询、不落盘，也不根据日志自动切换开关。

## 验证与限制

详细记录包含适配机型、系统版本、文件哈希、开关行为、日志证据、测试包哈希和回滚命令。当前记录中的 GNSS 实际定位、重启持久化和长期功耗仍需按记录所列范围单独验收；模块验证结果不能推导出内核源码问题已经修复。

模块默认配置和历史版本只用于追溯。正式发布内核时，不得将该目录中的模块文件误放入 `scripts/ak3` 或作为内核 `Image` 的替代物。
