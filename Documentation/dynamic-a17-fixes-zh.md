# Dynamic Kernel：修复 Lahaina TDM 采样率映射

本次修复小米 11 Pro 音频通路中“系统请求 96 kHz，内核实际配置为 32 kHz”的驱动错误。只修改 `techpack/audio/asoc/lahaina.c` 的两个采样率转换函数，使其与现有 ALSA 七项枚举一致。两颗 CS35L41 的 DSP 心跳和启停 mailbox 应答在实机对照中恢复正常。

## 本次功能修复

`tdm_sample_rate_text[]` 对外提供 8 / 16 / 32 / 48 / 96 / 176.4 / 352.8 kHz 七个选项，但旧 `tdm_get_sample_rate()` 和 `tdm_get_sample_rate_val()` 使用另一套十三项索引。系统的 `KHZ_96` 对应索引 4，旧代码却把它解释为 32000 Hz；读回时又将 32000 转回索引 4，使 mixer 显示仍为 96 kHz。

手机 `/vendor/etc/audio/sku_lahaina/mixer_paths_overlay_static.xml` 明确要求 TERT_TDM_RX_0、TX_0、RX_1 使用 KHZ_96。修复恢复了与现有七项枚举一致的双向映射，参考 MiYume 提交 `1dbf6a0fe1dcd62ad91a5d363125e93ac54ee19e` 中这两个函数的实现。

| 请求值 | 修复前实际值 | 修复后实际值 |
| --- | --- | --- |
| 8 kHz | 8 kHz | 8 kHz |
| 16 kHz | 11.025 kHz | 16 kHz |
| 32 kHz | 16 kHz | 32 kHz |
| 48 kHz | 22.05 kHz | 48 kHz |
| 96 kHz | 32 kHz | 96 kHz |
| 176.4 kHz | 44.1 kHz | 176.4 kHz |
| 352.8 kHz | 48 kHz | 352.8 kHz |

没有提高功放增益，没有修改保护、固件、调音文件、静音渐变、全局 ASoC 顺序或其他接口的采样率。最终功能修复不包含诊断插桩。七项转换及默认回退的检查可通过 `python3 scripts/dynamic/test_tdm_sample_rates.py` 重现。

## 本次实机验证与边界

- 实测机型和系统：小米 11 Pro / mars / M2102K1AC，HyperOS OS4.0.0.26.XKACNXM.D00 / Android 17。
- 在保持相同诊断插桩的 A/B 对照中，实际参数由 32 kHz / 8.192 MHz 恢复为 96 kHz / 24.576 MHz。两颗功放在播放期间的 DSP 心跳由停滞恢复为持续增长。
- 去重后的已保存样本：修复前 29 次 mailbox 应答有 27 次失败，修复诊断候选 14 次应答全部成功。两个采集窗口长度不同，不是故障率统计。
- 移除插桩后的候选 `5.4.302-Dynamic-gf2a7683` 正常启动；已保存的 24 次功放上、下电事件没有再出现原有超时或 AMP event 失败。该候选与最终发布的内核功能源码相同；最终提交接上三次规范文档更新，并整理说明、测试和离线打包验证，版本和二进制哈希不同，不能称为同一个实机产物。
- 实机测试使用 `fastboot boot` 临时启动；当前 boot 的只读副本只替换 kernel payload，其他字节保留。测试前后 `boot_a` 哈希相同，没有永久写入分区。
- 用户曾在只增加诊断日志、尚未修正采样率的版本反馈一次“扫码声音正常”。该反馈不能作为修复后声音的确认。无插桩候选的最终音量、扫码听感及本轮双击、触控、振动、Edge、网络回归尚未获得完整人工反馈。
- 未完成：小米 11 Ultra 实机验证、最终发布二进制再次临时启动、此次 AK3 在 Recovery/Horizon 中的实际安装、通话/听筒/蓝牙/耳机专项测试、声压与失真测量、长期稳定性和功耗测试。修复 DSP 异常不等于已量化证明所有低音量或杂音现象完全消失。

## 已有功能与兼容实现

以下功能从发布基线保留，本次没有修改其实现；历史通过结果不等同于本次重新全量测试。

- 息屏双击唤醒：fts_spi 使用 Xiaomi 主屏幕通知，处理 POWERDOWN、AOD LP1/LP2、ON，并保留用户手势开关和 IRQ wake。
- Android 17 / Edge：补齐 CAP_CHECKPOINT_RESTORE=40 的 capability UAPI 与 SELinux 名称映射，避免原生 zygote 查询能力 40 返回 EINVAL。原权限检查、SELinux 和 seccomp 保留。
- Android 17 BPF 兼容、Tasks Trace RCU、netbpfload 专用版本兼容路径，以及 hrtimer CPU 热插拔初始化修复。普通 uname 保持真实 5.4.302 版本。
- ReKernel-X v1.6（来源提交 afb5e6bc62c6b9702c823009566a58b2e53b7797）、Xiaomi 5.4 Binder hook 和引用保护、IPv4/IPv6 网络事件及 UID 过滤。此前微信未通知已确认与 NoActive 未配置网络解冻有关，不能将本次音频修复描述为通知修复。
- ReSukiSU v4.2.0-rc2 内核驱动（35149）、SUSFS v2.3.0；管理器 APK 不随内核包安装。
- AW8697 振动接口、RAM 固件延迟加载、波形序列清理及既有增益控制，自动固件 fallback 保持关闭。
- schedutil/WALT、ZRAM lz4p、F2FS/EROFS、seccomp/filter、BPF syscall/JIT。
- CONFIG_SCHEDSTATS=y 和已有启动配置；ROM 可以在启动后改变运行时 schedstats 开关，本次不承诺始终关闭或产生性能、功耗收益。

## AK3 安装范围和流程

- 固定使用用户确认的 `HoshinoNeko_Star_Stable2_Any3Kernel.zip`，SHA-256：`590627e556f15e49f243ab692bc07246242901aed21eacfb3cf8938b151263db`。
- 唯一机型准入：小米 11 Pro（mars / M2102K1AC）和小米 11 Ultra（star / M2102K1G）。不增加 Recovery、Horizon、Bootloader、Android 版本、ROM、Root 状态或新旧内核等长检查。Ultra 在白名单内不等于本次已实机验证。
- 沿用模板 `split_boot` + `flash_boot`，只替换 kernel payload，保留原 ramdisk cpio 和启动语义；`slot_select=active`、`patch_vbmeta_flag=0`，不切槽、不自动重启。
- 没有 ramdisk/、patch/、modules/、DTB/DTBO、完整 boot 或其他分区载荷。模板保留的 Phantom 代码没有附带模块载荷，因此不会安装 Phantom 模块。
- 读写失败、boot 无法解析、重封装失败、分区容量不足属于执行错误，正常报错。
- 打包器按模板原始顺序保留 ZIP 条目及元数据；该离线打包修正不改变手机上的安装器逻辑。Image、anykernel.sh 的允许差异之外，模板条目逐字节保留。

## 构建与复现

在区分大小写的 Linux 文件系统中检出 Release 对应源码提交，使用 Ubuntu Clang/LLVM 17 和 AArch64 GNU 工具链。作者为 Dynamic，构建主机为 mars，配置为 `vendor/mars_hyperos4_a17_defconfig`。uname 为 `5.4.302-Dynamic-g<提交前7位>`。

```sh
python3 scripts/dynamic/test_tdm_sample_rates.py
JOBS=6 OUT=/path/to/out bash scripts/build-dynamic-mars-a17.sh
AK3_TEMPLATE=/path/to/HoshinoNeko_Star_Stable2_Any3Kernel.zip python3 scripts/dynamic/test_kernel_only.py
python3 scripts/dynamic/test_ak3_offline.py --source "$PWD" --qemu /path/to/qemu-arm --boot /path/to/original-boot.img --image /path/to/out/arch/arm64/boot/Image --report /path/to/validation.json
OUT=/path/to/out AK3_TEMPLATE=/path/to/HoshinoNeko_Star_Stable2_Any3Kernel.zip AK3_VALIDATION_REPORT=/path/to/validation.json bash scripts/package-dynamic-release.sh
```

附件包括 Image、AK3、配置、构建清单、离线验证报告、发布说明和 SHA-256 清单。文件名时间取对应源码提交时间，Asia/Shanghai，精确到分钟；实际构建完成时间单独记录。适配基线是上述 mars / HyperOS 4 / Android 17，不能将只有机型检查解读为所有 ROM 都已通过适配。
