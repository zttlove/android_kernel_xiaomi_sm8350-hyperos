# BakaSU 35218 临时实机测试与回滚记录

## 授权和目标

- 用户在源码更新、UAPI 4 → 5 升级及编译验证后要求实机测试，并明确确认：临时替换配套 ksud，测试结束恢复旧 ksud／工具，重启回原内核。
- 设备：Xiaomi 11 Pro，`mars / M2102K1AC`，序列号 `40df69bc`，HyperOS `OS4.0.0.26.XKACNXM` / Android 17；活动槽位始终为 `_a`。
- 测试内核：`5.4.302-Dynamic-gf1e6db0`，候选源码提交 `f1e6db0a11917136a17df3cd72f67b15cfd033ea`，上游 BakaSU 提交 `373303c525d05c8b47801305f506ef9124dbd6e6`。
- 管理器：用户自行安装的官方 35218 APK。本次没有安装 APK、模块、编译环境或其他软件，没有提交、推送或发布。

## 启动前检查与备份

测试前手机运行 `5.4.302-Dynamic-ga4f8add`，内核驱动 35149 / UAPI 4，ksud 为 `4.2.0-rc2-14-g6d18926a / UAPI 4`，统一模块为 `2.6.2-test`。五个修复开关均为用户原有的开启状态，测试未切换开关。

当前 `boot_a` 与较早备份哈希不同，因此重新读取当前 192 MiB 分区，不使用旧备份替代当前启动内容。只读备份了原 ksud、工具、Root 授权／功能配置和统一模块；备份和原始日志只保存在本地验证目录，不纳入源码提交。

| 文件 | SHA-256 |
| --- | --- |
| 本次 Image | `99fbedcd77be7e27ada9a13535afd699a22f0b76497abbb7e397cee8c2bccd67` |
| 当前原始 boot_a | `9909a511a5783a66e63960ed803c9c92903da3a88cd1f4c1005092f958f500ed` |
| 临时启动 boot | `e1f56306c23afa56aa5346022a649fcb817ef98ea553d4dc8a943a0fae79d4d8` |
| 原 ksud | `85c027fc07f45a7b505714b2f506955b601e163225ef6b656d851b2144cf583a` |
| 官方 APK 内配套 ksud | `f95423ed1421593b6645bb00d1bf8a5d1cd02f3e99180a7adcac42f2f4aed19d` |

使用仓库已有 boot v3 重封装／验证脚本，只替换 kernel payload。临时镜像为 69,230,592 字节；压缩 ramdisk 21,404,810 字节、cpio 字节流及 894 个条目的内容、权限、属主、时间均保持原样，启动 header 除允许的 kernel size 字段外不变。没有生成 AK3，没有改变 DTB/DTBO、vendor_boot 或 vbmeta。

## 临时启动与结果

北京时间 2026-10-08 22:36:25 完成配套 ksud 核对；之后执行 `adb reboot bootloader`，读取 `fastboot getvar current-slot` 确认为 `a`，通过 `fastboot boot` 临时启动候选镜像。没有执行 `fastboot flash`、切槽或清数据。

新版本最终采样时间为 22:50:46，启动后运行 807.81 秒，约 13 分钟。不能把旧版本的累计运行时长算入新版本。

| 检查项 | 结果和证据 |
| --- | --- |
| Android 启动 | `sys.boot_completed=1`，实际内核为 `5.4.302-Dynamic-gf1e6db0` |
| Root 与协议配套 | root shell 正常；驱动 35218、UAPI 5；ksud `4.2.0-rc3-47-g373303c5 / UAPI 5` |
| 管理器 | 首页显示“工作中 / Built-in”，驱动和管理器均为 `35218/5`，SUSFS `2.3.0`；原有 9 个超级用户、13 个模块可显示 |
| SELinux | 保持 Enforcing；TCM 三个既有域和 RTC 权限查询均确认生效 |
| 统一模块 | 五个原开关保留；ATFWD、traced、主 GNSS 服务 PID 在两次采样间保持稳定，对应修复状态正常 |
| 重复 service 事件 | 再次调用 `/data/adb/ksud services` 返回“services already started, skipping”；模块事件日志及三个服务 PID 未改变，未重复执行模块服务脚本 |
| ARM32 / ARM64 | 在确认 8 核可用的短负载条件下，每核执行及系统调用共 16/16 通过 |
| 日常使用 | 用户解锁后简单测试触控滑动、相机预览和音频，反馈“没有问题” |
| 启动及最终日志 | 未匹配到新增 panic、Oops、CPU SANITY CHECK、unsupported variation、RCU stall／原子上下文睡眠或 UAPI mismatch；crash 缓冲为空 |

### 测试中遇到的情况

1. **CPU 亲和性探针**：无负载扫描中部分 `taskset` 调用报 `affinity: Invalid argument`，该错误发生在执行 ARM 探针之前。首次 CPU6 失败未保留 stderr，立即复测通过；随后完整保存的冷态扫描捕获 CPU5／7 的亲和性错误，CPU6 连续复测 10 次通过。沿用此前实机测试的 6 秒短负载，使 8 核可用后，ARM32／ARM64 16 项全部通过。未修改 CPU、热控或 cpuset 配置。瞬时可用核心／调度约束的具体来源未单独定位，不将这些调度准备失败描述成 ARM 程序崩溃，也不声称已修复热插拔行为。
2. **界面采集**：一次 UI 自动化读取因未达到 idle 状态失败，未据此判定管理器异常；之后确认前台为管理器，再读取截图，核对版本及工作状态。非测试目标的临时截图已立即清理。
3. **既有内核警告**：旧版本和新版本各出现一次 `msm_drm_bind → kthread_queue_work → kthread_insert_work` 启动 WARN；`tainted` 都是 512。本次没有修复这个已知显示初始化问题。日志仍可能含其他原有系统／驱动错误，不能将指定异常未匹配到写成“全部错误消失”。

## 非内核运行时改动与回滚

这是配套用户空间的临时测试记录，不把手机文件替换算作内核源码修复。

- 临时把 `/data/adb/ksud` 替换为已安装官方 APK 内的 UAPI 5 ksud；官方启动／管理器流程同步了 `ksu_susfs` 硬链接、resetprop 链接及配套工具。没有调用 boot patch、安装模块或更改用户开关。
- 测试后停止管理器，恢复原 ksud 和 `ksu/bin`、`ksu/lib` 的普通工具文件，逐项校验原始 SHA-256，并恢复原 SUSFS 硬链接和 SELinux 标签。
- 手机 `tar` 拒绝恢复三条指向目录外的绝对路径软链接，首次恢复因此暂停，未直接重启。普通文件已恢复；随后按启动前记录核对 ksud、resetprop、znctl 目标，恢复链接标签，确认 SUSFS 硬链接 inode 一致后再重启。没有跟随链接向第三方模块目录写入。失败日志和恢复记录保留。
- 普通重启后，23:00:51 采样确认回到 `5.4.302-Dynamic-ga4f8add`，驱动及 ksud 均恢复 UAPI 4，Root 和五项原修复状态正常；`boot_a` 哈希仍为上表原值。
- Root 授权文件及统一模块的配置／代码等 20 个文件逐字节一致。`.feature_config` 文件字节顺序不同，按源码中的二进制格式解析后，五个功能 ID 的数值逐项相同：`0=1, 1=1, 2=0, 3=1, 4=1`。原因是 HashMap 保存顺序变化，未重写用户配置，也没有丢失选择。
- 用户安装的管理器 APK 仍为 35218；内核与 ksud 回滚是本次明确授权的收尾。不能把此次临时测试描述成手机已永久升级到 BakaSU 35218。

## 结论、边界与证据

**本次基础实机验证和配套回滚通过。** 新版本的启动、Root、UAPI 5 配套、既有模块加载、重复 service 保护和基础使用已检查；本次核验未发现更新导致的新关键内核异常。

未覆盖长期待机、受控温度／续航／性能、全部应用、全部多管理器签名、室外完整定位、小米 11 Ultra 或永久安装。使用的是官方 APK 中的 ksud，未编译本仓库用户空间版本，因此本地 `KSU_SUKISU` 环境标识兼容和用户空间版本读取适配不算已实机验证。测试阶段没有发布准入结论，也没有推送或发布；用户随后授权的提交及发布另见 [源码同步与发布记录](2026-10-08-bakasu-35218-update.md)。

详细证据保存在 `D:/codex/dynamic-kernel-for-sm8350/update-work/20261008-bakasu-35218/device-test/`：

- `offline-boot-verification.json`、`backup-receipt.json`、`temporary-boot-command.json`、`temporary-boot.log`；
- `service-repeat-verification.json`、`abi-regression-cold.json`、`abi-regression.json`、`manager-home.png`；
- `final-log-analysis.json`、`runtime-restore-completed.txt`、`rollback-runtime.txt`；
- `user-state-rollback-verification.json`、`device-test-verification.json`；
- 本次原始 boot、ksud／工具／模块备份，以及必要启动和错误日志。

核对回滚后，按工作规则只清理本次手机临时测试目录及本地重复 APK、重复日志和恢复中间归档。保留当前 Image、源码、Git、回滚备份和失败证据，不删除环境或历史 Release 文件。
