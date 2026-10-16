# Android 17 系统更新后的内核与模块修复

日期：2026-10-16（Asia/Shanghai）。适配设备：小米 11 Pro / mars / M2102K1AC，系统 OS4.0.0.19.XKACNXM。

## epoll_pwait2 与锁屏闪烁

更新系统后，原项目内核启动时 SystemUI 的 GrallocUploadTh 反复以 `RenderThread Looper POLL_ERROR!` 退出。strace 确认其调用 441 号系统调用返回 ENOSYS，随后 SIGABRT。441 对应 epoll_pwait2，原项目内核未提供；临时恢复本次系统原内核后，用户确认锁屏停止闪烁。

修复提交：`3c304f2808d5fb8cbebf4a91f9404d19adcd0178`。为 ARM64 和 ARM32 compat 补齐 epoll_pwait2，复用既有 epoll 等待、信号掩码和错误处理，保留原有零超时锁语义。参考 Linux 上游提交 `58169a52ebc9a733aeb5bea857bc5daa71a301bb`。

- 构建内核：`5.4.302-Dynamic-g3c304f2`，Clang/LLD 17.0.6。
- 配置：`vendor/mars_hyperos4_a17_defconfig`；与此前候选配置相比仅 CONFIG_LOCALVERSION 变化，功能配置未调整。
- Image：47,819,264 字节，SHA-256 `8caee6016e8a401886d778679ad65a2c2f5e838204b04aa7c00dd91e2e97cedc`。
- 完整编译成功；补丁 checkpatch 为 0 errors / 0 warnings，不能据此声称整个既有内核构建无警告。
- 42 项直接接口验证通过：18 项 ARM64、18 项 ARM32 time64、6 项信号语义，覆盖超时、就绪事件、参数错误、信号屏蔽、EINTR 和旧 epoll_pwait 回归。
- 使用当前系统原 boot 的 ramdisk，仅替换 kernel，执行 fastboot boot 临时启动；boot_a、boot_b、vendor_boot_a、dtbo_a、vbmeta_a 前后哈希一致。
- SystemUI PID 5879 连续观察约两分钟不变，未发现新增 POLL_ERROR 或 SystemUI 崩溃；后续抽查仍稳定。
- 用户确认：锁屏、解锁、触控、相机和声音均正常。
- KernelSU UAPI 5 与当前 ksud 匹配，root 正常，SELinux Enforcing；运行配置与构建配置一致。

既有显示启动 kthread_insert_work WARN、厂商 module_layout 不匹配及部分 ROM 启动日志仍需另行分析；本次不宣称修复这些问题。没有永久刷写、创建 Release 或生成新 AK3。

## 模块 .19 兼容修复

模块 ID：`atfwd_seccomp_fix`。版本更新至 `2.6.4-test` / versionCode 14。

- GNSS 保留 .26 的精确版本、vendor 指纹与三个文件哈希检查，增加已核对的 .19 对应版本及指纹；只控制 loc_sys_service 的既有跳过属性与辅助服务，保留主 gnss_service。
- TCM 无法开启的根因是 control.sh 仍仅接受 .26。当前 .19 实机确认 Socket 标签、dpmd、应用检查及同类 TcmReceiver 写入拒绝后，运行脚本和安装脚本同步增加 .19 精确组合。原有三个域的 sock_file write 权限不变。
- RTC 后端和 WebUI 关闭确认、重新开启均通过；未确认独立缺陷，没有修改其原有三条读取权限或接口。
- 两个脚本 bash -n、差异格式检查及 12 项实际版本判断检查通过；精确组合通过，交叉与未知版本拒绝。
- 完整模块 ZIP 共 20 个文件，CRC 检查通过，新安装五项默认值仍为 0；升级保留用户合法选择。
- 包 SHA-256：`e08b26b57daaed8f79d82347479a3b2cc876736cefadb554b3a1eab0553b82f0`。
- 手机 WebUI 实测 TCM 可开启、规则已准备；RTC 关闭后移除持久化规则，重新开启后即时读取权限核实通过。前三项服务保持正常。
- 完整 ZIP 安装成功，活动与待升级目录关键文件哈希一致，五项已保存选择和六条规则一致。
- GNSS 本次内核启动后跳过属性与辅助服务状态已验证；室外导航未测试。TCM 尚待下次开机加载，新模块首次重启持久化尚未验收。

第 5 项保留为可选 RTC 统计兼容修复，没有将其描述为已验证的省电功能。Millet 与 ReKernel-X 本次只读检查，未修改其开关或源码。

## 深度休眠验收边界

本次开机一直连线或使用，挂起尝试与失败均为 0，USB 唤醒源持续活跃。实际 sleep_disabled=N，mem_sleep 已选 deep，rail-pc 有进入记录。这些结果不足以确认拔线待机正常或异常；45 分钟拔线息屏静置对照尚待完成，没有为了检测强制休眠、清空统计或重启。

构建清单、启动日志、完整接口测试、原 boot 和分区哈希备份保存在本地 release-work/20261016-system-update；模块备份、安装输出及 WebUI 验证保存在 module-work/20261016-switch-fix。上述设备镜像、完整日志及二进制未作为源码提交附件。
