# Dynamic Kernel v1.0.2 — 澎湃 OS 4 / Android 17 兼容版

日期：2026-09-20。本文以用户认可的 `v1.0.1-a17-test7` 为发布基线，记录正式版的变更、功能、适配范围与验证证据。正式产物的提交号、校验和及刷写后验证结果见该版本的 GitHub Release 与随包构建清单。

## 版本与适用范围

| 项目 | 说明 |
| --- | --- |
| 正式版本 | v1.0.2 |
| Linux 版本 | 5.4.302 |
| 正式内核名称 | `5.4.302-Dynamic-g<发布提交前7位>` |
| 维护分支 | `Dynamic/xiaomi_11_pro-kernel-a17` |
| 原稳定版基线 | Dynamic v1.0.1，`2ef50902a057757ec94e98b95a9c70cb2e585e81` |
| 通过临时启动的候选 | `5.4.302-Dynamic-v1.0.1-a17-test7` |
| 本轮实测设备 | 小米 11 Pro，`mars`，M2102K1AC |
| 本轮实测 ROM | 澎湃 OS `OS4.0.0.25.XKACNXM`，Android 17 / SDK 37 |
| 编译环境 | WSL Ubuntu；Clang 17.0.6、LLD 17.0.6；ARM64 |

这是面向上述设备和 ROM 的兼容更新。虽然本地 ROM 和 TWRP 文件名包含“Pro / Ultra”，实机报告的产品是 `mars`；没有本轮小米 11 Ultra（`star`）、小米 11（`venus`）或其他 ROM 的运行证据，不应将它们标为已适配。也未复测旧 Android / HyperOS 版本，不应推导为通用 SM8350 内核。

## 本次解决的问题

原 Dynamic v1.0.1 不能可靠启动当前 Android 17 ROM；历史失败启动原因包含 `reboot,bpfloader-failed`，ROM 的 `netbpfload.35rc` 会在 BPF 加载失败时触发重启。早期兼容候选可以进入系统，但出现约两分钟额外启动等待和用户报告的异常振动。

v1.0.2 保留稳定版设备内核基础，移植 Android 17 ROM 所需的 BPF 兼容接口，补齐 AW8697 振动接口，并沿用 test7 经过用户认可的增益控制路径。没有把 Linux 版本升级到 5.10；对普通程序显示的真实内核版本仍为 5.4.302。

## 详细源码变动

### 1. Android 17 BPF 兼容

- 以 MiYume SM8350 固定提交 `1dbf6a0fe1dcd62ad91a5d363125e93ac54ee19e` 为主要参考，移植 5.10 系列 BPF core、verifier、map、BTF 及配套 UAPI。
- 配套调整 cgroup BPF、socket / sock map / sock storage、网络命名空间、flow dissector、BPF trace 和 perf 接口，使移植的 BPF 实现能够接入现有 5.4 厂商内核。
- 补齐 capability / SELinux capability 映射、namespace identity、socket 引用、irq work 状态查询、tnum 运算等辅助接口；这些是 BPF 移植依赖，不能等同于把所有 5.10 子系统升级到当前内核。
- Tasks Trace RCU 以 Linux v5.10 对应源码为基础接入，补齐任务初始化、上下文切换静默状态报告和任务状态检查。保留当前树的厂商调度体系，没有整体替换为参考仓库的调度或 RCU 实现。
- 构建配置包含 `CONFIG_BPF_SYSCALL=y`、`CONFIG_BPF_JIT=y`、`CONFIG_BPF_JIT_ALWAYS_ON=y`、`CONFIG_BPF_STREAM_PARSER=y`、`CONFIG_NET_SOCK_MSG=y` 和 `CONFIG_TASKS_TRACE_RCU=y`。

### 2. netbpfload 版本兼容处理

Android 17 ROM 的 `netbpfload` 存在基于 `uname(2)` 的内核最低版本检查。尽管内核已移植对应 BPF 能力，真实 `5.4` 版本字符串仍会触发其拒绝路径。

`kernel/sys.c` 的 `newuname()` 因此为任务名（`current->comm`）**恰好等于** `netbpfload` 的调用者返回 `5.10.199-dsu-bpf-compat`。其他任务继续得到真实 Dynamic 内核版本。该分支位于已有 SUSFS uname 处理之后，是明确、局部的 Android BPF loader 兼容措施。

这不改变实际 Linux 版本，也不代表内核具备全部 5.10 接口。进程名匹配用于兼容，不是身份认证或安全边界。用户查看普通 `uname -r` 时应看到正式的 `5.4.302-Dynamic-g…` 名称。发布版本由 Git 提交、标签和 Release 标题区分，不再把稳定版后缀写入内核名称。

### 3. AW8697 振动驱动适配

保留参考驱动中与当前 ROM 接口相符的部分：

- 启用 `AWINIC_RAM_UPDATE_DELAY`，使用已有延迟工作路径在驱动初始化后加载 RAM 波形固件。
- 每次播放 RAM effect 前重写全部 waveform sequencer 槽位并清零 loop 配置，避免沿用前一次播放残留的序列项。
- 新增 LED class 振动接口，提供 `/sys/class/leds/vibrator` 兼容路径及 `vmax`、`rtp`、`waveform_index` 属性，以配合 ROM 中可观察到的振动服务接口。
- 保留原有 input force-feedback 接口。
- 保留稳定版 `set_gain()` 的增益分段算法，不启用 test6 中新增的 FF_GAIN → gain / boost voltage 联动映射。
- 新增 LED 接口的 `vmax` 写入使用与旧 I2C sysfs 路径一致的直接升压值处理方式。**v1.0.1 基线没有该 LED 接口**，因此这里是“新增接口复用旧处理逻辑”，不是“恢复旧版 LED 接口”。

test7 相对 test6 的主要运行时差异就是撤回新增 FF_GAIN 映射路径。用户随后明确认可 test7 可作为新版本发布；没有逐项提供通知、来电和声音强弱的测试报告，因此不把这次认可扩写为每种振动场景都已验证。

### 4. 固件加载等待配置

- 关闭 `CONFIG_FW_LOADER_USER_HELPER_FALLBACK`。
- 保留 `CONFIG_FW_LOADER_USER_HELPER=y`。

这与当前 ROM 原始内核提取出的配置一致，可避免固件直接加载失败后自动进入强制用户空间 fallback 等待路径。test6 已观察到启动速度恢复到接近原始内核的水平；由于没有完整固件超时内核日志，不将该配置单独定性为过去慢启动的唯一根因。

### 5. 保留稳定版 hrtimer 与既有功能

`kernel/time/hrtimer.c`、`include/linux/hrtimer.h` 保持 Dynamic v1.0.1 基线。这保留了已修复的 CPU 热插拔定时器初始化，不再采用试验期间不完整的 `hrtimers_prepare_cpu()` / `hrtimers_cpu_starting()` 拆分。

test3 / test5 的拆分把状态初始化移动到了未被当前 CPU hotplug 路径完整调用的位置，曾导致回归；它们不是正式 v1.0.2 的组成部分。

## 功能与组件

| 组件 / 功能 | v1.0.2 预期保留或新增的状态 | 本轮验证说明 |
| --- | --- | --- |
| ReSukiSU | 内核驱动 `v4.2.0-rc2-0b5cffd9@ReSukiSU`，version code 35149 | test7 构建日志确认；管理器 APK 版本不等于内核驱动版本 |
| SUSFS | v2.3.0，ReSukiSU inline hook | 构建日志和配置确认；本轮未逐项复测所有隐藏功能 |
| ReKernel-X | v1.5，保留 Generic Netlink 接口 | 源码基线和配置保留；本轮未重复 NoActive UI 全流程 |
| ZRAM | 默认 `lz4p`；保留 `lz4`、`lz4p`、`zstd` 支持 | 构建配置确认；容量继续由 Android 按设备内存设置 |
| CPU 调度 | `schedutil + WALT` | 构建配置保留 |
| 调试配置 | `DEBUG_FS=n`、`PAGE_OWNER=n`、`USER_NS=y` | test7 配置确认；保留 v1.0.1 设置 |
| BPF | 5.10 系列实现与配套 5.4 接口适配 | test7 系统成功完成启动，`sys.miui_bpf_ready=1` |
| AW8697 | RAM 延迟加载、完整序列清理、LED 接口、旧增益路径 | test7 振动服务运行并记录触摸反馈完成 |
| SELinux | 保持 Enforcing | test7 实机确认；没有通过切换为 Permissive 完成适配 |

Linux 5.4.302、hrtimer 深度休眠修复、ZRAM 标志位 / reset 修复和 DWC3 稳定性修复均继承自 v1.0.1。历史版本的测试结果用于说明这些功能的既有基础，不替代它们在 Android 17 上的完整回归验证。

## 已有验证证据

### test7 实机与构建

- 成功编译 Image、重打包 boot；原始 ramdisk 保持不变。
- `git diff --check` 通过；hrtimer 两个文件相对稳定基线无差异。
- 通过 `fastboot boot` 临时启动，进入系统；当时没有把 test7 写入持久 boot 分区。
- `uname -r=5.4.302-Dynamic-v1.0.1-a17-test7`。
- `sys.boot_completed=1`，`sys.miui_bpf_ready=1`，槽位 `_a`，产品 `mars`，SELinux `Enforcing`。
- `vibrator-bridge` 与 `vibratorfeature-hal-service` 均处于 `running`。
- `vibrator_manager` 识别默认振动器，具备 `ON_CALLBACK`、`PERFORM_CALLBACK`、`AMPLITUDE_CONTROL`；test7 保存的本次 TOUCH / TICK 完成记录为 74、77、82 ms，另有 60 ms 的 `cancelled_superseded` 记录，表示被后续请求替代。
- 现有 test7 采样日志中没有发现 `no firmware was found`、`write FF_GAIN failed` 或 AW8697 probe 失败；这不是全时段内核日志无错的保证。

test7 保存的 logcat 还出现 `NotificationVibratorHelper` 对通知波形 `[0]` 报 `IllegalArgumentException`（至少一个 timing 必须非零）。错误发生在 Android 框架创建波形的校验阶段，不能据此认定是 AW8697 失败；也不能据此声称通知振动已经全面正常。需要结合对应通知渠道设置或后续实测单独判断。

### 启动时间历史对照

| 镜像 | `boot_progress_start` | `boot_progress_enable_screen` |
| --- | ---: | ---: |
| 原始 HyperOS 4 内核 | 30,028 ms | 41,540 ms |
| 旧 test2 | 152,971 ms | 164,022 ms |
| test6 | 31,337 ms | 42,691 ms |

这些是系统事件时间，不包含全部 bootloader 阶段。该表说明 test6 已不再复现 test2 的约 123 秒额外等待；它不是 test7 或正式 v1.0.2 的新计时结果。正式版应在刷写后补充自己的启动验证记录。

## 适配边界与尚未覆盖的测试

- 本轮只确认上述 `mars + OS4.0.0.25.XKACNXM + Android 17` 组合；其他设备、其他 vendor、其他 Android 版本均未据此宣布支持。
- 用户认可 test7 作为发布基线；自动日志不能测量马达实际声音、频率或触感，也不能替代所有振动场景的主观测试。
- 调查工作区的 `scripts/test-a17-bpf.c` 已准备功能测试，用于 map batch、ringbuf mmap、有效 BPF 程序加载 / JIT 和无效操作码拒绝；当前记录未证明这些独立设备端测试全部运行通过，不能标为“完整 BPF selftests 通过”。
- 本轮 test7 证据未包含数小时或数天待机、连续通话、全部相机模式、所有传感器、双开用户、完整网络与 Root / 隐藏功能的重测；继承源码不等于本轮逐项验证。
- 本轮普通 ADB shell 读取部分 sysfs / 内核日志受 SELinux 限制；现有软件侧记录不包含完整运行时马达校准 / 升压值对照。

## 正式构建、刷写与回退说明

正式构建必须来自最终提交后的源码，并执行仓库的 `scripts/set-dynamic-version.sh` 生成版本名。发布标签、内核名称的七位提交号、源代码归档和产物清单应指向同一提交。不得把带 `test7` 名称的文件直接重命名为正式版本代替重编译。

从本次发布分支开始，`uname -r` 统一采用 `5.4.302-Dynamic-g<提交前7位>`。构建元数据中的作者为 `Dynamic`，内核名称不包含日期。Release 附件名称在内核名称后追加源码提交时间（`YYYYMMDD-HHMM`，Asia/Shanghai），日期取对应提交而不是上传时间。`scripts/package-dynamic-release.sh` 会生成 Image、匹配 ROM 的 boot、AnyKernel3 包、配置、构建清单和 SHA-256 清单。

产物应包含：最终 Image、有效构建配置、构建日志、SHA-256 清单，以及适用于上述 ROM 的 boot 镜像；若同时提供 AnyKernel3 包，应使用同一 Image，并明确其设备检查及保留当前 ramdisk 的行为。ROM 专用 boot 镜像仅适用于匹配的 ROM / boot 格式，不能作为跨 ROM 通用镜像。

永久刷写前应核对设备 `mars`、当前槽、正式版本名与镜像 SHA-256，并保留已验证原始 boot。当前设备已知原始 HyperOS 4 boot 的 SHA-256 为：

```text
c9ec95939d7cb6c5966343f3ec6d655dff4114b76eddf5183972c4c16125acbf
```

正式镜像应保留当前 ROM 的 ramdisk、header 和对应启动参数；本轮原始 ramdisk 的 SHA-256 为：

```text
2267e836a67a111fae84b9aa82b764e8b66deba34cc2ae79a2baabce4ef3767c
```

永久刷写完成后再核对真实版本名、`sys.boot_completed`、`sys.miui_bpf_ready`、槽位和 SELinux；正常重启后仍运行正式版本，才构成“永久刷入已验证”。如果新版本不能启动，恢复匹配 ROM 的原始 boot；不需要为回退格式化 userdata，也不应把跨 ROM boot 当作回退镜像。

## v1.0.2 正式产物与永久刷写记录

- 源码提交：573058b36621e404e178f683ce89958d8d0f8fe1。
- 标签：dynamic-kernel-v1.0.2。
- Image SHA-256：4a33d8418632126e8ca34ea4536580dd401f4ff261d1d4a3f1777c05c5daca9d。
- boot 镜像 SHA-256：fdac44e11190ce0e362d8e907a19ef5963f4cb11b9a579a8b22f8142f4e60c2e。
- .config SHA-256：cac8e0b5ddf6631931573095c4ad47b5a86679c64c3e13b997ee2f9a986ae874。
- 2026-09-20 已对 mars 的 boot_a 执行永久刷写，fastboot 返回 Sending、Writing 均为 OKAY。
- 刷写后正常重启验证：uname -r=5.4.302-Dynamic-g573058b-v1.0.2、产品 mars、ROM OS4.0.0.25.XKACNXM、槽位 _a、sys.boot_completed=1、sys.miui_bpf_ready=1、SELinux Enforcing。

## test7 来源清单（不是正式版校验和）

| 文件 | SHA-256 |
| --- | --- |
| `Image-v1.0.1-a17-test7` | `fb344019aa950b05ed1c9e44303be11240f4d810acf6cc76ec93a1bdcba4a2af` |
| `boot-v1.0.1-a17-test7.img` | `beba9d34044e9839b193eb5aefb1d668c023747bd27af50c56a4148923c1e0bd` |
| `config-v1.0.1-a17-test7` | `65024d0f848bec775abb2b13a3a2e7e9c0db369fc2f1573ef382ddddc8c03034` |

原始证据见本目录的 `test7-runtime-20260920/`、`build-test7.log`、`test7-sha256.txt`、`兼容工作记录.md`。正式发布应另外记录最终提交号、标签、正式产物校验和及刷写后测试结果，不应覆盖这些候选证据。

## 参考与致谢

- Dynamic v1.0.1：本仓库稳定设备内核基线与已有 ReSukiSU / SUSFS、ReKernel-X、ZRAM、CPU 调度和稳定性修复。
- [MiYume0721/android_kernel_xiaomi_sm8350_miyume](https://github.com/MiYume0721/android_kernel_xiaomi_sm8350_miyume)，参考提交 `1dbf6a0fe1dcd62ad91a5d363125e93ac54ee19e`：BPF 兼容和 AW8697 驱动接口。
- Linux v5.10：Tasks Trace RCU 和相应任务状态辅助实现。
- ReSukiSU、SUSFS、ReKernel-X、AnyKernel3 及原小米 / Qualcomm 内核维护者。源文件原有版权与许可证保留。

## 从源码重建

请在 Linux 原生、区分大小写的文件系统中检出发布标签；Windows 不区分大小写的目录不能完整表达本内核树中的所有文件名。使用 Clang / LLVM 17、AArch64 GNU binutils，以及内核构建所需的 make、bc、bison、flex、libssl-dev、libelf-dev 等依赖。

```sh
git checkout dynamic-kernel-v1.0.2
OUT=/absolute/path/to/out JOBS=10 bash scripts/build-dynamic-mars-a17.sh
```

`arch/arm64/configs/vendor/mars_hyperos4_a17_defconfig` 保存完整参考配置（与 test7 的运行配置一致，仅版本字符串不同）。构建入口生成配置、从当前提交写入正式版本名并构建 Image；它要求源码工作区干净，防止把未提交修改标为已有提交。最终 `.config`、Image 和 `dynamic-build-manifest.txt` 位于 OUT。传统 `build.sh` 和其他设备 defconfig 不等同于本版发布配置。

保留原始 ROM boot 并只替换内核载荷：

```sh
python3 scripts/dynamic/repack_boot_v3.py matching-stock-boot.img /absolute/path/to/out/arch/arm64/boot/Image boot-v1.0.2.img
python3 scripts/dynamic/verify_boot_repack.py matching-stock-boot.img boot-v1.0.2.img
```

重打包工具仅处理 header v3，校验原始 header 元数据和 ramdisk 保持一致。必须自行提供与目标设备当前 ROM 匹配的原始 boot；源码仓库不包含厂商 ROM ramdisk。
