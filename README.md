> 本项目是面向 Xiaomi SM8350（Lahaina）设备的 Android/HyperOS 内核源码。当前维护重点为 Xiaomi 11 Pro（`mars` / `M2102K1AC`）和 Xiaomi 11 Ultra（`star` / `M2102K1G`）。
>
> Android 17 双击唤醒、Edge 兼容修复、音频采样率修复和严格的只替换内核安装限制见 [发布说明](Documentation/dynamic-a17-fixes-zh.md)。历史版本中的完整 `boot` 刷写说明不适用于当前发布流程。

# Dynamic Kernel for SM8350

## 最新版本下载

[下载最新 Release（AK3 内核包与统一修复模块）](https://github.com/Leecaarmy/android_kernel_xiaomi_sm8350-hyperos/releases/latest)

当前发布标签：`20261008-2155`；内核：`5.4.302-Dynamic-gf1e6db0`。

- [下载 AK3 内核包](https://github.com/Leecaarmy/android_kernel_xiaomi_sm8350-hyperos/releases/download/20261008-2155/Dynamic-AK3-5.4.302-Dynamic-gf1e6db0-20261008-2155.zip)
- [下载 KernelSU 系统服务修复模块（2.6.2-test）](https://github.com/Leecaarmy/android_kernel_xiaomi_sm8350-hyperos/releases/download/20261008-2155/KernelSU-atfwd_seccomp_fix-2.6.2-test-20261008-2155.zip)

本版将 ReSukiSU/KernelSU 内核侧更新到 BakaSU 35218 / UAPI 5，包含管理器扫描与 SELinux 的上游修复及重复 service 保护，保留 SM8350 大小核修复和既有平台兼容。须配套 35218 / UAPI 5 的管理器及 `ksud`；仅安装 APK 不等于运行服务已更新。统一修复模块 2.6.2-test 沿用上版功能，在管理器中单独安装，用于处理无法在本仓库内核源码中修复的系统服务问题；新安装全部关闭，升级保留合法选择。适配范围、安装与回滚、实机结果、校验值及已知问题见 [本版 Release 说明](https://github.com/Leecaarmy/android_kernel_xiaomi_sm8350-hyperos/releases/tag/20261008-2155)。

## 项目用途

本仓库用于维护 Xiaomi SM8350 平台的 Linux 5.4.302 arm64 内核，针对 Xiaomi 11 Pro/11 Ultra 的 Android/HyperOS 运行环境提供源码、配置、构建校验和 AK3 内核包模板。

项目遵循 `WORK_RULES.md` 中的最小改动、证据优先和可追溯发布规则。源码修改、内核构建、AK3 打包、临时启动和 Release 发布是相互独立的阶段，必须分别完成对应的检查和授权。

当前仓库的主要维护分支为 `dynamic`。设备专用默认配置为 `arch/arm64/configs/vendor/mars_hyperos4_a17_defconfig`，该配置已启用 Clang ThinLTO：`CONFIG_LTO_CLANG=y` 和 `CONFIG_THINLTO=y`。

## 项目结构

| 路径 | 作用 |
| --- | --- |
| `Makefile` | Linux 内核顶层 Kbuild 入口，负责配置、编译、链接和版本生成。 |
| `arch/arm64/` | arm64 架构启动代码、内存管理、平台支持和设备配置。 |
| `arch/arm64/configs/vendor/mars_hyperos4_a17_defconfig` | `mars` HyperOS/Android 17 目标默认配置，也是当前构建基线。 |
| `drivers/` | 输入、触控、显示、USB、存储、电源、振动、网络等设备驱动。 |
| `techpack/` | Qualcomm 平台专用驱动集合，包含 Lahaina 音频、显示和其他 SoC 相关实现。 |
| `kernel/`、`mm/`、`fs/`、`block/`、`ipc/`、`lib/` | 内核调度、内存、文件系统、块设备、进程间通信和通用库等核心子系统。 |
| `net/`、`crypto/`、`security/` | 网络协议、加密算法和安全机制。 |
| `include/` | 内核内部头文件及 `include/uapi/` 用户空间可见的 UAPI 定义。 |
| `KernelSU/` | KernelSU 相关内核驱动代码；管理器 APK 不随内核包安装。 |
| `scripts/dynamic/` | Dynamic 项目的 AK3 生成、内核包审计、离线验证、采样率检查和 boot 重封装校验脚本。 |
| `scripts/ak3/` | AK3 固定模板源码。模板目录不保留 `Image`，打包时只把新编译并校验过的内核 `Image` 放入包根目录。 |
| `Documentation/` | 内核文档和本项目的功能修复、测试边界及发布说明。 |
| `WORK_RULES.md` | Bug 检测、代码修改、新功能、构建、提交、AK3 和 Release 的工作规则。 |

## 主要入口和产物

- **内核构建入口**：根目录 `Makefile`。
- **设备配置入口**：`arch/arm64/configs/vendor/mars_hyperos4_a17_defconfig`。
- **arm64 内核产物**：`arch/arm64/boot/Image`（使用 `O=` 时位于输出目录对应的 `arch/arm64/boot/Image`）。
- **AK3 生成入口**：`scripts/dynamic/package_kernel_only.py`。
- **AK3 安装入口**：`scripts/ak3/anykernel.sh` 及其 `tools/` 下的 AK3 核心脚本。
- **离线校验入口**：`scripts/dynamic/test_kernel_only.py`、`scripts/dynamic/test_ak3_offline.py` 和 `scripts/dynamic/verify_boot_repack.py`。
- **音频采样率校验入口**：`scripts/dynamic/test_tdm_sample_rates.py`。

构建命令中的 `ARCH`、`LLVM`、`CROSS_COMPILE`、`O=` 等参数必须按实际工具链环境填写。下面的命令只表示 Kbuild 目标，不代表本仓库会自动安装编译环境：

```sh
make O=<output-directory> ARCH=arm64 vendor/mars_hyperos4_a17_defconfig
make O=<output-directory> ARCH=arm64 Image
```

在正式打包前必须提交源码快照，并确认工作树没有未记录的源码变化。Windows 工作树可能因大小写不敏感路径和 `aux.*` 保留名称产生 Git 差异；这类差异必须按 `WORK_RULES.md` 记录和处理，不能直接当作源码改动提交。

## 核心功能模块

- Qualcomm Lahaina/SM8350 平台支持，以及 Xiaomi 设备的启动和电源管理适配。
- `techpack/audio/asoc/lahaina.c` 中的 TDM 采样率转换和音频路径逻辑。
- `drivers/input/touchscreen/fts_spi/` 等触控驱动，包含息屏手势和双击唤醒相关处理。
- Android 17 capability、BPF、Tasks Trace RCU、`netbpfload` 和 `hrtimer` 兼容路径。
- Xiaomi Binder hook、引用保护、IPv4/IPv6 网络事件和 UID 过滤。
- ReKernel-X、BakaSU（原 ReSukiSU）、SUSFS、KernelSU 等内核侧扩展；具体版本和来源以源码与发布说明为准。
- AW8697 振动驱动、RAM 固件延迟加载、波形序列和既有增益控制。
- `schedutil`/WALT 调度、ZRAM `lz4p`、F2FS/EROFS、`seccomp`、BPF syscall/JIT 等配置能力。

上述模块是源码中与当前设备功能和发布基线直接相关的部分，不代表本仓库只包含这些子系统。修改任何模块前，必须先按 `WORK_RULES.md` 完成只读分析和根因确认。

### Root 组件源码版本

`KernelSU/` 当前同步 [BakaSU 官方仓库](https://github.com/Baka-SU/BakaSU) 的 `main` 提交 `373303c525d05c8b47801305f506ef9124dbd6e6`，版本号为 `35218`，标签基线为 `v4.2.0-rc3`，UAPI 为 `5`。这是开发版源码；来源和版本元数据记录在 `KernelSU/resukisu-version`。

本仓库保留源码直接集成、SELinux 5.4 状态锁、原有多管理器签名及 `KSU_SUKISU` 模块标识兼容。设备 defconfig、SUSFS 2.3.0、ReKernel-X、统一修复模块和 AK3 模板沿用既有配置。更新记录与验证边界见 [BakaSU 35218 同步记录](work-records/2026-10-08-bakasu-35218-update.md)。

本次源码已完成 mars 的基础临时实机验证，包含启动、Root、UAPI 5 配套、原有修复模块加载和重复 service 保护；测试后恢复原运行环境。过程、已知问题和未测试范围见 [实机测试与回滚记录](work-records/2026-10-08-bakasu-35218-device-test.md)。

管理器 APK 由用户自行安装，应与内核及 `ksud` 的 UAPI 配套。`rc3 / 35171` Release APK 仍使用 UAPI 4，不能作为本次 UAPI 5 更新的配套版本。本次已完成基础临时实机验证并发布 `20261008-2155`；长期待机、完整定位、小米 11 Ultra 及永久安装等未测试范围仍按 Release 说明保留，不把临时测试当作完整验收。

## AK3 内核包规则

1. AK3 包从仓库的 `scripts/ak3/` 目录生成。该目录只保存已经确认的模板文件，不保存编译得到的 `Image`。
2. 用户未明确许可时，只允许在模板基础上替换最终的 `Image` 内核镜像；不得修改 ramdisk、`patch/`、modules、DTB/DTBO、`vbmeta` 或其他分区内容。
3. 实际打包时，`scripts/dynamic/package_kernel_only.py` 会把新编译的 `arch/arm64/boot/Image` 加入包根目录，并验证 Image 哈希和内核版本。
4. 当前准入设备为 `mars`、`star`、`M2102K1AC`、`M2102K1G`。未确认的设备、Recovery、Bootloader、Android 版本或 ROM 不得自行加入准入条件。
5. 安装脚本使用 `split_boot` 和 `flash_boot` 只替换现有 `boot` 中的 kernel payload，保留原有 ramdisk；`patch_vbmeta_flag=0`，`slot_select=active`。
6. AK3 生成后必须执行模板完整性、机型准入、ZIP 完整性、Image 一致性和离线 boot 重封装检查。没有通过检查的包不能用于临时启动、刷写或 Release。

## 测试和发布边界

- 仅分析或检测时，只读取源码、日志、配置和已有产物，不修改、不编译、不打包、不刷写设备。
- 修复代码后，测试范围至少包括原问题、受影响模块和必要的启动/回归检查；测试结果、未测试项目和剩余风险必须记录。
- 临时实机测试应优先使用 `fastboot boot` 或其他可回滚方式；永久刷写、重启、切槽和分区修改需要单独授权。
- Release 标签复用 AK3 的时间格式 `<YYYYMMDD-HHmm>`，例如 `20261001-0213`。Release 必须包含源码提交、内核 Image、AK3 包、哈希、构建清单、离线验证结果和实机测试边界。
- 文档、脚本和规则文件的修改可以单独提交，不因文档提交而重新生成内核 Image；正式内核 Release 仍需完整执行构建和发布检查。

## 如何向 Android Common Kernel 提交补丁

1. **首选方式**：先在上游 Linux 中完成修改；适合时再回移植到 stable 版本。对应的补丁会自动合并到相应的 Android Common Kernel。如果补丁已经存在于上游 Linux，应提交符合下述要求的 backport。
2. **次选方式**：在树外开发补丁。从上游 Linux 的角度看，除非补丁修复 Android 专属问题，否则通常不会被接受；继续提交前应先与 `kernel-team@android.com` 协调，并遵守下面的补丁要求。

## Common Kernel 补丁要求

- 所有补丁必须符合 Linux kernel coding standards，并通过 `script/checkpatch.pl`。
- 补丁不得破坏 arm、arm64、x86、x86_64 架构的 `gki_defconfig` 或 `allmodconfig` 构建（参见 <https://source.android.com/setup/build/building-kernels>）。
- 如果补丁不是从上游分支合并而来，主题必须标注补丁类型：`UPSTREAM:`、`BACKPORT:`、`FROMGIT:`、`FROMLIST:` 或 `ANDROID:`。
- 所有补丁必须包含 `Change-Id:` 标签（参见 <https://gerrit-review.googlesource.com/Documentation/user-changeid.html>）。
- 如果已经分配 Android Bug，必须包含 `Bug:` 标签。
- 补丁必须包含作者和提交者的 `Signed-off-by:` 标签。

下面的要求按补丁类型分别适用。

### 主线 Linux 回移植：`UPSTREAM:`、`BACKPORT:`

- 如果补丁是主线 Linux 的 cherry-pick，且没有任何改动：
  - 主题使用 `UPSTREAM:`；
  - 添加 `(cherry-picked from ...)` 上游提交信息。
- 如果补丁相对上游版本需要改动：使用 `BACKPORT:`，保留与 `UPSTREAM:` 相同的标签，并在 `(cherry-picked from ...)` 行后说明改动。

示例：

```text
UPSTREAM: important patch from upstream

This is the detailed description of the important patch

Signed-off-by: Fred Jones <fred.jones@foo.org>

Bug: 135791357
Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
(cherry-picked from c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
Signed-off-by: Joe Smith <joe.smith@foo.org>
```

如果存在回移植冲突，应在来源提交行后记录，例如：

```text
BACKPORT: important patch from upstream

[ Resolved minor conflict in drivers/foo/bar.c ]
```

### 其他来源的回移植：`FROMGIT:`、`FROMLIST:`

- 补丁已经合并到上游维护者分支、但尚未进入 Linux 主线时，主题使用 `FROMGIT:`，并记录 `(cherry picked from commit <sha1> <repo> <branch>)`。来源必须是稳定且未 rebase 的维护分支，不要使用 `linux-next`。
- 如果该补丁还需要修改，使用 `BACKPORT: FROMGIT:`。
- 补丁已经提交到 LKML、但还没有进入任何维护者分支时，主题使用 `FROMLIST:`，并添加指向 `lore.kernel.org` 提交页面的 `Link:` 标签。
- 如果该补丁还需要修改，使用 `BACKPORT: FROMLIST:`。

示例：

```text
FROMGIT: important patch from upstream

Bug: 135791357
(cherry picked from commit 878a2fd9de10b03d11d2f622250285c7e63deace
 https://git.kernel.org/pub/scm/linux/kernel/git/foo/bar.git test-branch)
Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
Signed-off-by: Joe Smith <joe.smith@foo.org>
```

```text
FROMLIST: important patch from upstream

Bug: 135791357
Link: https://lore.kernel.org/lkml/20190619171517.GA17557@someone.com/
Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
Signed-off-by: Joe Smith <joe.smith@foo.org>
```

### Android 专属补丁：`ANDROID:`

- 修复 Android 专属代码中的 Bug 时，主题使用 `ANDROID:`，并添加引用问题提交的 `Fixes:` 标签。
- 新增 Android 专属功能时，主题使用 `ANDROID:`，并添加 Android Bug 的 `Bug:` 标签。

示例：

```text
ANDROID: fix android-specific bug in foobar.c

This is the detailed description of the important fix

Fixes: 1234abcd2468 ("foobar: add cool feature")
Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## HHG 设备振动驱动

以下内容是原仓库保留的 HHG 设备 `AKSys` 手柄 USB 适配器驱动合并说明。它不是当前 Xiaomi 设备 AK3 打包流程的一部分，使用前应先确认目标内核确实需要该驱动。

### 将驱动合并到内核源码树

1. 将 `${this_project}/drivers/hid/hid-aksys.c` 复制到 `${your_kernel_root}/drivers/hid/`。
2. 对比并合并 `${this_project}/drivers/hid/hid-ids.h` 和 `${your_kernel_root}/drivers/hid/hid-ids.h`，在文件末尾前加入：

   ```c
   #define USB_VENDER_ID_QUALCOMM  0x0a12
   #define USB_VENDER_ID_TEMP_HHG_AKSY 0x1234
   #define USB_PRODUCT_ID_AKSYS_HHG  0x1000
   ```

3. 对比并合并 `${this_project}/drivers/hid/Kconfig` 和 `${your_kernel_root}/drivers/hid/Kconfig`，在文件末尾前加入：

   ```text
   config HID_AKSYS_QRD
       tristate "AKSys gamepad USB adapter support"
       depends on HID
       ---help---
       Support for AKSys gamepad USB adapter

   config AKSYS_QRD_FF
       bool "AKSys gamepad USB adapter force feedback support"
       depends on HID_AKSYS_QRD
       select INPUT_FF_MEMLESS
       ---help---
       Say Y here if you have a AKSys gamepad USB adapter and want to
       enable force feedback support for it.
   ```

4. 对比并合并 `${this_project}/drivers/hid/Makefile` 和 `${your_kernel_root}/drivers/hid/Makefile`，在文件末尾加入：

   ```make
   obj-$(CONFIG_HID_AKSYS_QRD) += hid-aksys.o
   ```

5. 修改目标内核的默认配置文件，加入：

   ```text
   CONFIG_HID_AKSYS_QRD=m
   CONFIG_AKSYS_QRD_FF=y
   ```

任何源码合并、配置变更和构建行为都必须遵守 `WORK_RULES.md` 的阶段边界；未完成问题分析和用户确认前，不得直接执行上述合并操作。
