# 非内核修复工作记录：vendor.atfwd seccomp 重启循环

## 记录信息

- 记录编号：`NK-2026-10-01-ATFWD-001`
- 记录日期：`2026-10-01`
- 问题类型：非内核用户空间服务、vendor seccomp 策略、KernelSU 临时覆盖
- 当前状态：临时修复已启用并通过设备验证；尚未固化到 vendor 源码或 vendor 镜像
- 适配设备：`M2102K1AC`（mars）
- 系统版本：`Android 17`，`OS4.0.0.26.XKACNXM`
- 测试内核：`5.4.302-Dynamic-g1015467`
- 活动槽位：`_a`
- Verified Boot：`green`
- Bootloader：锁定
- 仓库分支：`dynamic`
- 修复前仓库提交：`62a63f83791c72edce14b4ef70b3c228b70511c5`

## 2026-10-01 追加：扩展为系统服务稳定性修复模块

用户授权在现有 `atfwd_seccomp_fix` 模块上继续增加已确认的 `traced` 修复，并加入中文 KernelSU WebUI。扩展仍然是设备侧用户空间修复，不修改本仓库内核源码、defconfig、AK3 或任何只读系统分区。

### 新增内容

模块源码与可审查文件保存在：

```text
work-records/modules/atfwd_seccomp_fix/
```

- 保留模块 ID `atfwd_seccomp_fix`，名称改为“系统服务稳定性修复”；
- 保留原策略覆盖，并保留原策略和修复策略的 SHA-256 基线；
- 新增 `traced` 独立控制：只处理已经确认的 `traced.relay_producer_port=vsock://-1:2010`，启用时删除该属性，保留本地 Unix Socket；
- 新增 ATFWD 和 traced 两个独立配置开关；ATFWD 选择下次开机生效，traced 选择即时生效；
- 新增中文 WebUI，显示设备、策略、属性、服务 PID、操作记录，并对关闭修复进行确认；
- WebUI 只通过 KernelSU 原生 root `exec` 桥接，未引入网络脚本、第三方依赖或常驻监控进程；
- 仅在 `mars` / Android 17 上执行，发现 ROM 属性、策略哈希或设备条件变化时主动停止，避免套用旧修复。

### 设备更新和验证

设备上的原模块目录已原位更新，未刷写 boot、vendor、product、vbmeta，未清除数据。更新前已将原模块备份为：

```text
build-artifacts/service-fixes/atfwd_seccomp_fix-1.0-original.zip
```

验证结果：

1. `atfwd_enabled=1`、`traced_enabled=1` 时，ATFWD PID 保持 `2393`，策略仍为修复哈希；traced 属性为空，服务状态为 `running`，`traced_probes` 为 `running`；
2. ATFWD WebUI 关闭/开启只保存开关，不重启当前 ATFWD 服务，PID 未改变；
3. traced 关闭恢复 ROM 的 `vsock://-1:2010`，重新开启删除该属性，traced 等待 init 的重启间隔后恢复 `running`；
4. WebUI 已在 `com.resukisu.resukisu/.ui.webui.WebUIActivity` 中打开，中文页面显示两个开关和真实服务状态；关闭确认、刷新和操作记录可用；
5. 非关闭修复的观察时段未出现新的 `Failed to create vsock://-1:2010`、`Failed to start the traced service`、`vendor.atfwd SIGSYS` 或 `blocked syscall: gettid`；测试关闭 traced 时原错误允许短暂复现，不计入修复开启后的验证窗口；
6. 两个开关、无效参数、脚本语法、策略哈希、ZIP 内容逐项检查通过。

测试模块包：

```text
build-artifacts/service-fixes/系统服务稳定性修复-2.0-test.zip
SHA-256: 4FB6697F0AEFCC4EC8A026AB581E3DF9DB618E91D54A80FCCF4E0EAA65EE985F
```

原模块备份包：

```text
build-artifacts/service-fixes/atfwd_seccomp_fix-1.0-original.zip
SHA-256: 0EED2EFDBD71BF47A86BF9CCC6398444A70549F2561DA7CA7FF8B985F45EBA50
```

本次扩展仍不代表 `millet_monitor`、GNSS、性能节点、PowerHelper 或 5G 待机耗电问题已经修复。重启持久化验证尚未执行；在完成重启前，模块状态应标记为“当前运行时验证通过，重启验证待执行”。

## 1. 修改范围和授权

本次只处理日志中确认的 `vendor.atfwd` 崩溃重启问题。

用户已明确授权使用现有 KernelSU 环境创建测试模块并重启设备验证。未授权修改内核源码、刷写 vendor 分区、清除数据或安装新的外部依赖。

本次没有修改当前内核仓库中的内核源码、defconfig、`scripts/ak3` 或构建环境。仓库原有 15 项未提交差异保持不变。

## 2. 修改前基线

### 2.1 设备上的相关文件

```text
/vendor/bin/ATFWD-daemon
/vendor/etc/seccomp_policy/atfwd@2.0.policy
/vendor/etc/init/hw/init.qcom.rc
```

`init.qcom.rc` 中的服务定义为：

```text
service vendor.atfwd /vendor/bin/ATFWD-daemon
    class late_start
    user system
    group system radio
```

启动属性：

```text
persist.vendor.radio.atfwd.start=true
```

### 2.2 修复前日志证据

服务约每 5 秒启动一次并退出，典型日志如下：

```text
ATFWD-daemon: libminijail: blocked syscall: gettid
init: Service 'vendor.atfwd' received SIGSYS
init: Sending SIGKILL to service 'vendor.atfwd' process group
init: process with updatable components 'vendor.atfwd' exited 4 times in 4 minutes
```

启动阶段还出现：

```text
init: failed write pid ... to memcg
```

该条日志不是进程退出的直接原因，真正的退出原因是 seccomp 拦截 `gettid`。

### 2.3 修复前策略内容

原始策略文件不包含 `gettid: 1`，只包含相关的 `getpid: 1`、`set_tid_address: 1` 等规则。

原始文件 SHA-256：

```text
245f83d543bf32fa14d80cdec0527ab7d51384e3d9f3721ca185b52884837f70
```

## 3. 根因判断

`ATFWD-daemon` 使用 `libminijail` 加载 `/vendor/etc/seccomp_policy/atfwd@2.0.policy`。当前策略没有放行 `gettid`，而二进制在启动过程中调用了该系统调用，因此被 seccomp 发送 `SIGSYS`，随后由 init 重启服务。

这不是内核缺少 `gettid`，也不是 modem 重启。问题位于 vendor 用户空间策略和二进制的兼容关系。

## 4. 方案选择

采用 KernelSU 独立覆盖模块，原因如下：

1. 不写入只读的 EROFS `/vendor` 分区；
2. 不修改 `vbmeta`，不触碰 AVB；
3. 不解锁 Bootloader；
4. 不替换 `ATFWD-daemon` 和 init 配置；
5. 只放行一个已经确认需要的系统调用；
6. 可以通过禁用模块快速回滚；
7. 不改变用户文件、应用数据和 modem 固件。

没有采用关闭 `vendor.atfwd`、禁用整个 seccomp、修改内核配置或直接刷写 `vendor.img` 的方案。

## 5. 模块实施记录

### 5.1 模块信息

模块目录：

```text
/data/adb/modules/atfwd_seccomp_fix
```

模块元数据：

```text
id=atfwd_seccomp_fix
name=ATFWD Seccomp Fix
version=1.0-test
versionCode=1
```

模块只包含：

```text
module.prop
system/vendor/etc/seccomp_policy/atfwd@2.0.policy
```

策略唯一行为改动：

```diff
 getpid: 1
+gettid: 1
 sigaltstack: 1
```

没有添加 `service.sh`、`sepolicy.rule`，没有替换二进制，也没有修改现有 KernelSU 模块。

### 5.2 第一次测试及失败原因

第一次重启后，KernelSU overlay 已经成功挂载到：

```text
/vendor/etc
```

但是模块文件继承了 `/data/adb` 的：

```text
u:object_r:adb_data_file:s0
```

`vendor_atfwd` 无法搜索该 overlay 目录，产生：

```text
Could not read base policy file '/vendor/etc/seccomp_policy/atfwd@2.0.policy'
Fatal signal 6 (SIGABRT)
```

发现问题后立即创建 `disable` 标记并重启回滚。原始 vendor 文件和用户数据未被修改。

### 5.3 标签修正

读取原始 vendor 文件后确认正确标签为：

```text
u:object_r:vendor_configs_file:s0
```

随后将模块中的 `system/vendor` 覆盖树统一设置为 `vendor_configs_file`，保持目录、文件权限为原始值，并重新启用模块测试。

## 6. 最终验证结果

### 6.1 启动和服务状态

验证时间：`2026-10-01 16:04:42 CST`

设备本次启动 uptime：约 `869` 秒。

```text
sys.boot_completed=1
init.svc.vendor.atfwd=running
init.svc_debug_pid.vendor.atfwd=2393
vendor.peripheral.modem.state=ONLINE
gsm.network.type=NR_SA,Unknown
radio.modem.modemresetting=false
```

服务 PID 在延时复核前后保持：

```text
2393 -> 2393
```

### 6.2 策略覆盖状态

当前生效文件：

```text
/vendor/etc/seccomp_policy/atfwd@2.0.policy
```

当前标签：

```text
u:object_r:vendor_configs_file:s0
```

当前 SHA-256：

```text
76402d01474d0f67fe41f7220811b08b5fc60e09a875c46854e2788bdce1d643
```

KernelSU 挂载记录：

```text
KSU /vendor/etc overlay ... atfwd_seccomp_fix/system/vendor/etc:/vendor/etc
```

### 6.3 错误日志复核

以本次启动的 `dmesg` 和当前 `logcat` 检查：

| 检查项 | 结果 |
|---|---:|
| `blocked syscall: gettid` | 0 |
| `Could not read base policy` | 0 |
| ATFWD `SIGSYS` | 0 |
| ATFWD `SIGABRT` | 0 |
| `vendor.atfwd` 启动/退出循环 | 0 |
| ATFWD 相关 SELinux 拒绝 | 0 |
| ATFWD crash buffer 记录 | 0 |
| 当前启动的 ATFWD dmesg 错误 | 0 |

`logcat` 中少量包含 `ATFWD` 的记录只是本次通过 ADB 查询属性产生的 `adbd` 命令审计，不是 ATFWD 服务错误。

### 6.4 无关的剩余日志

当前仍有 `failed write pid ... to memcg`，但上下文显示对应服务是：

```text
traced
millet_monitor
```

没有对应 `vendor.atfwd`，不属于本次修复范围。

GNSS AIDL 服务缺失和 `millet_monitor` socket 失败也仍然存在，后续应单独建立问题记录，不能与本记录混合处理。

## 7. 回滚方式

先禁用模块并重启：

```powershell
adb shell su -c "touch /data/adb/modules/atfwd_seccomp_fix/disable"
adb reboot
```

确认系统恢复后，如需删除测试模块，再删除：

```text
/data/adb/modules/atfwd_seccomp_fix
```

删除前必须确认不再需要本次复现证据和回滚能力。

## 8. 未测试项目和剩余风险

- 尚未使用专用 AT 命令接口验证 ATFWD 的全部业务功能；当前以服务稳定、modem 在线、NR SA 正常作为兼容性检查。
- 尚未完成断开 USB、锁屏、关闭 Wi-Fi 条件下的 30 至 60 分钟待机功耗对比。
- 该修复是 KernelSU 临时覆盖，不是 vendor 源码的永久修复；系统 OTA 或模块重装可能覆盖该状态。
- 重新打包模块时必须保留 `vendor_configs_file` 标签，否则会再次触发策略读取失败。
- 当前记录不代表 GNSS、`millet_monitor`、`traced` 等其他日志问题已经修复。

## 9. 后续永久修复方向

如果需要固化到系统，应在匹配当前 ROM 的完整 Android/vendor 源码中修改：

```text
vendor/.../seccomp_policy/atfwd@2.0.policy
```

只增加：

```text
gettid: 1
```

然后重新生成并校验 vendor 镜像。当前内核仓库不包含该文件，因此不应修改本仓库的内核源码或 AK3 模板来实现永久修复。

## 2026-10-01 追加：2.1-test WebUI 实机验收

- 已将本次模块文件临时复制到设备 `/data/adb/modules/atfwd_seccomp_fix`，未重启、未刷写、未切换开关。
- KernelSU WebUI 页面已进入“内核日志”独立页，实机显示 `400/400` 行及原始 `<3>`、`<6>`、`<7>`、`<11>` 等优先级记录；“修复开关”与“内核日志”页签可以互相切换。
- 已用关键词输入框验证筛选，输入不存在的关键词显示 `0/400` 和“没有符合筛选条件的日志”；页面内容以纯文本显示。
- 已完成 JavaScript 逻辑测试：优先级解析、组合筛选、空结果、日志文本安全显示和无 KernelSU 桥接时的禁用状态均通过。
- 设备端最终状态仍为两个修复开启、ATFWD 运行中、traced 运行中、traced 通道属性为空；读取日志期间没有产生模块事件记录或改变修复状态。
- 本次实机证据截图：`build-artifacts/service-fixes/webui-kernel-log.png`、`build-artifacts/service-fixes/webui-kernel-log-filter.png`。

### 2.1-test 实现与产物追溯

新增 `kernel-log.html`、`kernel-log.js`，两页共享原有 root 桥接（`bridge.js`）；`control.sh` 只追加只读 `kernel-logs` 命令。手机默认 dmesg 读取路径未遵守 `-s` 容量限制，已改为 `dmesg -S -r -s 65536` 快照接口，再限制 64 KiB / 400 行并跳过被截断的首条记录。管道保留上游错误退出码。日志不写入磁盘、不清空、不自动轮询；筛选在页面内执行。原始优先级按最低三位解析，日志使用纯文本插入页面。

包内全部 17 个文件已逐一与本地源码按字节对比通过；四个 shell 脚本权限为 0755。没有修改内核代码或启动脚本逻辑，没有编译内核。旧 2.0 包保留作为上一版本记录。手机临时传输目录与临时截图已清理。

测试包：`build-artifacts/service-fixes/系统服务稳定性修复-2.1-test.zip`

SHA-256：`8750E293251DA841FFE03AF6EE3C5C1AE0F2DC5B8E8A64D99BF7AF67D5E0AB2B`

本次验证只覆盖日志页读取和筛选、返回原页面及运行状态检查；重启持久化仍未验证。截图 `webui-kernel-log.png` 记录日志页面；`webui-kernel-log-filter.png` 最后保存的是返回修复开关页的状态。没有改变系统设置或修复开关。

## 2026-10-01 追加：2.2-test 底部 Dock 导航

用户授权将页面切换按钮改为底部 Dock 栏。修改仅涉及 `webroot/index.html`、`webroot/kernel-log.html`、`webroot/style.css`、版本信息和说明文档。顶部导航已移除，两页共用固定底部布局：中文文字与本地 SVG 图标、当前页面高亮、键盘焦点提示；页面底部留出 110px 加安全区域的空间，Dock 自身避开系统手势区域。不引入依赖，不改动 JavaScript、控制脚本、策略或开关配置。

已同步到手机现有模块，在 KernelSU WebUI 中验证两页显示、日志读取（400/400 行）、底部导航切换及页面滚动后的固定位置。日志页滚至底部时，说明文字和日志容器可完整显示在 Dock 上方。实机输入通过 `input -d 0` 指定主屏幕完成；没有修改手机显示设置或修复开关。未重启手机。

截图保存在 `build-artifacts/service-fixes/webui-dock-index.png`、`webui-dock-log.png`、`webui-dock-scroll.png`。模块版本为 `2.2-test` / `versionCode=4`。测试包全部文件已逐一比对本地源码；shell 文件权限为 0755。

测试包：`build-artifacts/service-fixes/系统服务稳定性修复-2.2-test.zip`

SHA-256：3AD8FF909C2DC23F360A326245098E769A182805E6EBAA3390275CF1432701BF

## 2026-10-02 追加：2.3-test 并入 GNSS 独立开关

按用户要求，GNSS 缺失 AIDL 的异常请求处理已并入同一模块，增加第三个独立开关，没有创建独立模块。详细根因、适配校验、改动、即时切换/回滚、日志证据、产物和待验收项目记录于 [GNSS 统一模块处理记录](2026-10-02-gnss-unified-module.md)。本记录此前关于 GNSS 未处理的描述属于旧版本历史状态。
