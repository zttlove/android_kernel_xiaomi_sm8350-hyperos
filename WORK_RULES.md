# Dynamic Kernel 后续规范操作手册

> 版本：2026-09-24
>
> 适用分支：`Dynamic/xiaomi_11_pro-kernel-a17`
>
> 作者署名：`Dynamic`

本手册用于约束内核源码修改、编译、AK3 打包、Release 发布和实机操作。规则分为“必须”“禁止”“允许”三类；没有明确写入“允许”的行为，不能自行推断为允许。

## 1. 规则优先级与范围

### 1.1 优先级

按以下顺序处理冲突：

1. 用户在当前任务中明确给出的操作范围和授权；
2. 本手册中的分区安全规则和 AK3 固定流程；
3. 本手册中的构建、发布和记录要求；
4. 工具默认行为、历史脚本行为和个人推断。

用户授权只覆盖明确写出的目标、分区和动作。授权刷入目标 boot，不等于授权修改 ramdisk、vendor_boot、dtbo、vbmeta、modules 或其他分区。

### 1.2 三类变更的边界

| 变更类型 | 允许范围 | 禁止范围 |
| --- | --- | --- |
| 内核功能变更 | 内核源码、内核配置及实现该功能所需的源码文件 | ramdisk、patch、modules、启动镜像其他组件和无关重构 |
| 构建与发布工具 | 为复现构建、打包和验证而修改仓库中的文档、测试脚本和发布脚本 | 把工具修改成新的运行时刷写逻辑，或向 ZIP 注入未授权载荷 |
| 设备操作 | 仅在用户明确授权后，对指定目标 boot 执行 kernel-only 替换 | 其他分区、清数据、切槽、自动重启、修改 ramdisk 或启动配置 |

修改本手册属于用户明确要求的文档变更，不代表扩大了设备操作授权。

## 2. 源码和分区安全规则

- 内核功能修复必须只修改解决问题所必需的内核源码；不得借机混入无关调优、重构或其他功能。
- 严禁修改或注入 `ramdisk/`、`patch/`、`modules/`，以及 boot 中除 kernel payload 和封装算法必需 header 大小、对齐、校验字段外的内容。header 字段只能因 kernel 长度变化而被重新计算，不得改变启动参数或其他语义配置。
- 未经用户明确授权，不得写入、擦除、格式化、切换或修改任何设备分区，包括 `boot`、`boot_a`、`boot_b`、`vendor_boot`、`dtbo`、`vbmeta`、`vendor_dlkm`、`system_dlkm`、`super` 和 `userdata`。
- 用户明确授权目标 boot 后，只允许执行第 6 节规定的 kernel-only AK3 流程；该授权不扩展到其他分区或其他 boot 组件。
- 打包、构建和离线验证必须使用临时文件或离线副本，不得连接手机写入分区。
- 工具或刷机包如果会修改 ramdisk、启动配置、模块、AVB/vbmeta 或未授权的其他分区，必须停止并说明。
- kernel-only 重封装允许因 kernel 长度变化而重新生成必要的 header 大小、对齐和校验字段；这些字段的变化必须是封装算法的必然结果，不能改变启动参数、ramdisk、DTB/DTBO 或其他语义配置。

## 3. `uname -r` 命名

`uname -r` 必须严格使用以下格式：

```text
<内核版本>-<作者署名>-g<源码提交前 7 位>
```

示例：

```text
5.4.302-Dynamic-g573058b
```

要求：

- 内核版本必须来自源码实际版本信息；
- 作者署名固定为 `Dynamic`，除非用户明确指定新署名；
- 短哈希必须来自最终构建源码提交的前 7 位，并保留 `g` 前缀；
- 构建输出、Image、设备运行结果、Release 说明和构建清单必须一致；
- 任一处不一致都必须停止发布或刷写。

## 4. Bug 修复和兼容修复流程

每项修复必须按以下顺序执行：

1. 记录基线：系统版本、机型、当前内核、复现步骤和现象；
2. 定位根因：使用源码、日志、运行时数据或对照测试确认原因；
3. 最小修改：只改解决该根因所必需的源码；
4. 编译检查：确认构建成功、`uname -r` 正确、配置符合预期；
5. 实机验证：只在用户授权范围内测试，记录实际运行版本和结果；
6. 回归验证：检查已确认的启动、触控、双击唤醒、振动、Edge、网络和其他相关功能；
7. 发布判断：区分“通过”“失败”“未测试”，不能用编译成功代替功能验证。

发现新异常、启动失败、功能回退或测试证据不足时，必须停止发布和永久刷入，先定位问题或恢复已验证状态。不得承诺“绝无其他 bug”。

## 5. 构建要求

- 构建必须在区分大小写的 Linux 文件系统中进行，避免 Windows 文件系统大小写冲突。
- 构建前必须确认源码工作树状态、分支、最终提交和构建脚本版本。
- 必须记录工具链、配置、构建时间、源码提交、Image 大小和 SHA-256。
- 构建产物必须通过 `uname -r`、Image 完整性和提交一致性检查。
- 构建成功不代表 AK3 安装器安全；必须继续执行第 7 节的打包和离线验证。

## 6. AK3 固定模板和 kernel-only 流程

### 6.1 固定模板

- 所有后续 AK3 包必须使用用户确认的 `HoshinoNeko_Star_Stable2_Any3Kernel.zip`。
- 模板 SHA-256 固定为：

  ```text
  590627e556f15e49f243ab692bc07246242901aed21eacfb3cf8938b151263db
  ```

- 未经用户明确指定并重新确认，不得更换模板、模板版本或安装器实现。
- 模板的目录结构、ZIP 条目、条目顺序、权限、时间戳、压缩属性、许可证、工具和 `update-binary` 必须保留。

### 6.2 唯一准入条件

AK3 运行时只验证机型，白名单固定为：

| 机型 | `ro.product.device` / 设备树标识 |
| --- | --- |
| 小米 11 Pro | `mars` / `M2102K1AC` |
| 小米 11 Ultra | `star` / `M2102K1G` |

不得增加以下检查或拦截：

- Recovery、Horizon 或其他执行环境；
- zygote 是否存在；
- Bootloader 锁定状态或 Verified Boot 状态；
- Android 版本、安全补丁日期或 ROM 名称；
- 当前内核版本、旧内核大小、Image 大小或 Image 格式；
- Image 哈希、Root、KernelSU、Magisk、APatch 或其他管理器状态；
- 任何未由用户明确要求的系统属性。

读取失败、boot 无法解析、重封装失败、目标分区容量不足和实际写入失败是执行错误，必须正常报错；它们不能被伪装成额外的兼容性准入条件。

### 6.3 只替换 kernel payload

- 必须使用模板已有的 `split_boot` + `flash_boot` 流程。
- `split_boot` 可以读取和解析 boot；不得调用会解包、重建或注入 ramdisk 的 `dump_boot` + `write_boot`。
- 必须保留原 boot 的 ramdisk cpio 字节流、文件内容、权限、属主、时间、启动参数、DTB/DTBO 以及其他组件。
- 只允许因 kernel 长度变化更新 kernel size、位置对齐和封装算法所需的 header 字段。
- 必须设置：

  ```text
  patch_vbmeta_flag=0
  slot_select=active
  ```

  不得通过 AK3 修改 AVB/vbmeta 标志，不得在 OTA 或 postinstall 环境自动选择 inactive 槽位。
- 不自动重启、不清数据、不切换活动槽位。

### 6.4 AK3 派生包允许和禁止的差异

只允许修改以下项目：

1. ZIP 根目录的 `Image`；
2. `anykernel.sh` 的显示名称为 `Dynamic Kernel For SM8350`；
3. 四个机型白名单；
4. kernel-only 所需的 `split_boot`、`flash_boot`、`patch_vbmeta_flag=0` 和 `slot_select=active` 设置。

禁止：

- `dd if=Image ... seek=1`、`cat Image > block` 或任何固定偏移 writer；
- 不解析 boot header 就直接覆盖 block 前段；
- 恢复或新增 `tools/kernel-only.sh` 等绕过模板 core 的精简安装器；
- 修改 `tools/`、`update-binary`、`phantom-package.json`、许可证、权限或其他模板条目；
- 新增 `ramdisk/`、`patch/`、`modules/`、DTB、DTBO、vendor_boot、vendor_dlkm、system_dlkm、vbmeta、完整 boot 或其他分区载荷；
- 添加 Phantom、Magisk、KernelSU 或 APatch 模块，除非用户另行明确授权。

### 6.5 AK3 文件名

文件名固定为：

```text
Dynamic-AK3-<内核版本>-Dynamic-g<源码提交前 7 位>-<YYYYMMDD-HHmm>.zip
```

不得加入 `HoshinoNeko`、`template` 或其他未规定字段。时间取最终源码提交时间，时区为 Asia/Shanghai，精确到分钟。

## 7. 发布前强制阻断检查

任何一项失败，都必须停止发布，不得用“编译成功”替代验证。

### 7.1 源码和产物一致性

- 源码分支、最终提交、Image、AK3、构建清单和 Release 说明使用同一提交；
- `uname -r`、文件名短哈希和 Release 标签一致；
- 模板 SHA-256 匹配固定值；
- Image 存在、可读、大小和 SHA-256 已记录。

### 7.2 模板逐项比较

- ZIP 可完整解压且 `testzip()` 通过；
- 逐条比较模板和成品的条目、顺序、权限、时间戳、压缩属性；
- 除第 6.4 节列出的差异外，所有条目必须逐字节一致；
- 旧显示名称残留数为零，新显示名称出现次数为一；
- `anykernel.sh`、`update-binary`、`tools/ak3-core.sh` 通过 shell 语法检查；
- 扫描并拒绝固定偏移写入、直接 block 覆盖、额外环境拦截和 ramdisk 重建路径。

### 7.3 离线 boot 验证

必须使用原始目标 boot 的离线副本，测试至少三种 kernel 长度：

1. 当前编译 Image；
2. 跨页增大的 Image；
3. 缩小的 Image。

每个测试都必须确认：

- kernel payload 被正确替换；
- ramdisk cpio 字节流完全一致；
- ramdisk 文件内容、权限、属主和时间完全一致；
- 启动参数、DTB/DTBO 和其他组件保持一致；
- 原始输入 boot 没有被修改；
- 失败测试不会留下部分输出。

验证报告必须记录 boot、Image、模板、`ak3-core.sh`、`anykernel.sh` 的 SHA-256、ramdisk 条目数量、测试载荷长度和每项结果。没有验证报告，不得发布或推荐刷入。

## 8. Release 内容和发布流程

### 8.1 必备附件

每个内核功能提交的 Release 必须包含：

- Image 内核镜像；
- AK3 内核刷机包；
- `.config` 或等价配置文件；
- 构建清单；
- Release 说明；
- SHA-256 清单；
- AK3 离线验证报告。

Release 说明必须记录源码提交、分支、构建时间、工具链、配置、`uname -r`、产物哈希、打包模板、安装流程、当前版本新增功能、修复的 bug、已有兼容实现、适配系统和机型，以及未测试项目。

### 8.2 发布前后流程

1. 在草稿 Release 中上传附件；
2. 逐一核对远端文件名、大小和 SHA-256；
3. 核对 Release 标签指向最终源码提交；
4. 核对 Release 说明与附件版本、短哈希和哈希值一致；
5. 全部通过后再发布并标记 Latest；
6. 任一项不一致时，保持草稿或撤回，不得推荐刷入。

功能源码提交必须同步对应 Release。仅修改规范、文档或测试脚本且没有新的内核 Image 时，记录为文档提交，不生成虚假的内核 Release。

## 9. 失败、撤回和记录

- 发现固定偏移 writer、缺少 boot 解析、模板条目异常、验证失败或可能修改 ramdisk / 启动配置时，立即停止发布。
- 已发布但后来发现安装器不安全的包，必须标记为撤回或作废，Release 说明中写明原因，并明确告知用户不得刷入。
- 不得把历史候选、临时启动结果、离线测试或编译成功描述成最终版本的实机验证。
- 每次实机测试必须记录：授权范围、设备序列号或机型、活动槽位、刷写动作、是否重启、运行内核、结果和异常。
- 未经用户再次明确授权，不得因为打包、验证或故障排查自动刷写、重启、切槽或恢复分区。

## 10. 发布前简表

```text
[ ] 只修改了必要的内核源码、文档或构建工具
[ ] 没有修改 ramdisk / patch / modules / 其他分区载荷
[ ] uname -r、Image、提交短哈希和文件名一致
[ ] 使用固定 HoshinoNeko 模板且模板哈希正确
[ ] AK3 只检查 mars / M2102K1AC / star / M2102K1G
[ ] 没有 Recovery / Bootloader / 系统版本等额外拦截
[ ] 使用 split_boot + flash_boot
[ ] patch_vbmeta_flag=0，slot_select=active
[ ] 没有固定偏移 writer 或 tools/kernel-only.sh
[ ] 模板逐项比较通过
[ ] 三种 kernel 长度离线 boot 验证通过
[ ] ramdisk cpio、启动参数和其他组件验证保持一致
[ ] Release 附件、哈希、标签和说明全部一致
[ ] 未经授权没有刷写、重启、切槽或修改手机
```
