# GNSS 缺失 AIDL 请求：统一模块处理记录

日期：2026-10-02（北京时间）。本次属于非内核修复，沿用 `atfwd_seccomp_fix`，不创建独立模块。

关联内核仓库 HEAD：`62a63f83791c72edce14b4ef70b3c228b70511c5`。既有 Windows 路径冲突差异未处理。

## 授权与范围

用户要求将 GNSS 处理并入已有模块，设置独立开关，并同意配合室外定位测试。已有 ATFWD、traced 开关、底部 Dock 和只读内核日志页面继续使用。

本次仅更新模块脚本、WebUI、配置默认值、版本和说明，在已连接手机的原模块目录中验证即时切换。未编译内核、刷写分区、重启手机、清空日志或清理用户应用数据；没有安装依赖。没有提交或推送仓库。

## 环境与证据

| 项目 | 值 |
| --- | --- |
| 手机 | 小米 11 Pro，mars / M2102K1AC |
| Android / ROM | Android 17 / OS4.0.0.26.XKACNXM |
| vendor 指纹 | Xiaomi/mars/mars:13/RKQ1.211001.001/OS4.0.0.26.XKACNXM:user/release-keys |
| 内核 | 5.4.302-Dynamic-g1015467 |
| 原模块 / 新版本 | atfwd_seccomp_fix / 2.3-test，versionCode=5 |
| 设备模块目录 | /data/adb/modules/atfwd_seccomp_fix |
| 本地模块目录 | work-records/modules/atfwd_seccomp_fix |

根因证据：`/system_ext/bin/loc_sys_service` 原 PID 1411，等待 `vendor.qti.gnss.ILocAidlGnss/default`；服务未注册，init 没有对应 AIDL 服务可启动。logcat 每秒出现 `Waited one second` 和 `ctl.interface_start` 失败。

实际定位提供者为 `/vendor/bin/hw/android.hardware.gnss@2.1-service-qti`，init 名称 `gnss_service`，PID 1465；`lshal` 注册 `android.hardware.gnss@2.1::IGnss/default` 和 `vendor.qti.gnss@4.0::ILocHidlGnss/gnss_vendor`。因此问题来自 system_ext 客户端与 vendor 接口代际不匹配，当前证据不能确定具体打包者或修改者，也不能证明它是主要耗电来源。

ROM 已提供启动条件：

```rc
on early-boot && property:ro.gps.loc_sys_service.skip=
    start loc_sys_service
```

服务本身声明 `oneshot`、`disabled`。非空跳过属性可阻止此启动条件；运行中改变属性不会自动停止进程，需要单独控制该辅助服务。

### 适配校验值

| 文件 | SHA-256 |
| --- | --- |
| /system_ext/etc/init/loc_sys_service.rc | bdb98db727c2da512e5179e6aab20ad73cf53ca1fe6227f176fcf2540016adff |
| /system_ext/bin/loc_sys_service | aa67db15dcaa35c498f22e19234c8052c64c61b0562bb9c1208392ef62929ce1 |
| /vendor/etc/vintf/manifest/vendor.qti.gnss@4.0-service.xml | a2febcc396f453bdabfe60f8adc9b0bc89b110845b3bd4b0c582ce35054a5f4e |
| 当前 ATFWD 修复策略（仅核对） | 76402d01474d0f67fe41f7220811b08b5fc60e09a875c46854e2788bdce1d643 |

## 实现与文件

- `control.sh`：增加固定参数 `set gnss 0/1`、GNSS 状态、适配检查、当前开机原状态保存、应用和恢复逻辑。开启前校验 ROM/vendor 及三个文件；即时开启还检查 HIDL 服务运行、AIDL 未注册。Binder 查询失败时拒绝开启。
- `config/gnss_enabled`：新安装默认 `0`；手机本次测试明确设置为 `1`。旧 ATFWD/traced 配置没有覆盖。
- `customize.sh`：升级时保留三个开关，增加中文安装说明。
- `webroot/index.html`、`app.js`：在原页面追加第三张卡片，独立关闭确认、异常请求处理状态、辅助服务状态、原定位服务 PID 和跳过属性。应用失败后重新读取后端状态，避免显示旧选择。
- `module.prop`、`kernel-log.html`、`README.md`：更新版本与处理边界；原日志读取逻辑及 Dock 布局不变。

开启使用 KernelSU 已有 `/data/adb/ksu/bin/resetprop -n` 设置 `ro.gps.loc_sys_service.skip=1`。`post-fs-data` 只设置属性，不发可能等待 init 的 `ctl` 命令；启动后和即时切换仅停止 `loc_sys_service`。不修改 rc、VINTF 清单、定位 HAL 或 SELinux。

关闭仅恢复本模块接管的当前开机状态：保留原空属性是否存在，恢复原来运行的服务；原来停止的服务不主动启动。状态绑定 boot ID，避免把旧开机或 OTA 前的值带到新 ROM。发现其他组件写入不同属性值时拒绝覆盖。没有本模块接管状态且开关关闭时不操作服务或属性。

隔离测试发现 Android mksh 的内置 `hash` 别名会把原校验函数调用展开成 `alias -t`，导致文件校验失败。内部帮助函数改为 `file_hash`，保留原 SHA-256 算法与校验值；这是确保原策略校验和本次 GNSS 校验实际执行所必需的修正，不改变公开脚本命令。

## 验证结果

1. JavaScript 语法检查、设备 shell 语法检查通过。隔离测试替换属性和服务控制命令，没有修改真实设备属性；验证默认关闭、未接管关闭无副作用、早期启动无 ctl 命令、即时停止范围、关闭恢复、不启动原停止服务及拒绝第三方属性覆盖。
2. WebUI 逻辑测试验证无 root 桥接时禁用、状态渲染、关闭确认、重新开启、其余开关保持及固定命令范围。
3. 11:42:06 手机配置默认关闭，辅助服务 PID 1411 正在请求 AIDL。11:42:25 首次开启成功：跳过属性 `1`，辅助服务 `stopped`，原定位 PID 1465 运行。至 11:43:27 的新 logcat 中目标错误为 0。
4. 11:43:45 通过 WebUI 确认关闭：跳过属性恢复为空，辅助服务恢复运行（新 PID 9681），相同 AIDL 启动失败再次出现，证明可以回滚。
5. 11:44:05 通过 WebUI 重新开启：辅助服务停止，原定位服务 PID 1465 保持不变。11:47:13 已同步最终适配校验代码，重复保存开启选择没有重启其他服务。
6. 11:49:44 最终检查：从 11:44:06 起约 5 分 38 秒，新 logcat 中目标 AIDL 请求错误为 **0**；64 KiB 内核快照中未见该目标文本。没有清空日志，历史缓冲区是否保留旧错误不作为新错误的判断依据。

最终状态：

| 项目 | 状态 |
| --- | --- |
| ATFWD | 开启，运行中，PID 2393，策略哈希保持不变 |
| traced | 开启，运行中，PID 13738，relay 属性为空 |
| GNSS 处理 | 开启且已应用，skip=1，辅助服务停止 |
| 原 HIDL GNSS | 运行中，PID 1465，两个原接口仍注册 |

按时间和服务 tag 筛选 logcat，排除 ADB 命令审计中的检索文本，没有把历史记录或命令文本计作新错误。

截图：`build-artifacts/service-fixes/webui-gnss.png`、`webui-gnss-confirm.png`（相对于工作区根目录）。

## 产物与回滚

测试包：`build-artifacts/service-fixes/系统服务稳定性修复-2.3-test.zip`，24719 字节；共 18 个文件，全部与本地源文件逐字节对比通过，四个 shell 脚本 ZIP 权限为 0755。包内 GNSS 默认关闭，升级安装保留手机当前选择。

SHA-256：`4A98285FE8777D0CAC348C3E9CBA41923F07337C28D66F89C4FF79040917C74A`。

已清理手机 `/data/local/tmp/dynamic-gnss-check`、本地临时隔离测试脚本和重复截图；保留源文件、测试包、两张验收截图及必要历史回滚包。

即时回滚使用 WebUI 关闭第三个开关，或执行：

```sh
sh /data/adb/modules/atfwd_seccomp_fix/control.sh set gnss 0
```

返回 2.2 版本前，先关闭 GNSS 处理以恢复当前开机属性和辅助服务，再恢复旧版本；仅覆盖旧控制脚本不会自动撤销已经设置的属性。禁用整个模块后由用户自行重启，系统原属性与启动规则恢复；本次没有执行重启。

## 待验收与限制

- 用户已同意配合室外地图定位测试，当前尚未收到结果。需要确认实际位置、连续更新及正常导航；PID 和接口注册不能代替实际定位验收。
- 重启后的启动时序和持久化尚未实机验证，不声称该项通过。
- 该方案抑制无效 AIDL 请求，没有实现缺失接口或恢复辅助服务的厂商扩展功能；需要这些功能时必须匹配 system_ext/vendor。
- 未进行待机功耗对照，不能据此承诺耗电改善。其他错误不纳入本次修复。

相关历史记录：[ATFWD 与原统一模块记录](2026-10-01-vendor-atfwd-kernelsu.md)。旧记录中的 GNSS 未修复结论对应当时版本，本次以本记录为准。

## 2026-10-02 追加：2.3.1-test 修复 Dock 返回历史

用户反馈多次切换 Dock 后侧滑返回会在两页之间回退。原 Dock 使用普通链接，管理器 `WebUIScreen.kt` 在 WebView 可以返回时调用 `goBack()`，因此每次切换累积的历史会逐条回退。

最小修改为共享 `webroot/bridge.js` 拦截 Dock 点击：其他页使用 `location.replace()` 替换当前历史条目，当前页不跳转。版本更新为 `2.3.1-test` / `versionCode=6`，同步两页版本标识、README 和手机现有模块；未修改服务控制脚本及三个开关选择。旧会话历史无法由网页安全清空，测试前重新打开 WebUI。

JavaScript 语法检查通过。用户允许暂停手机操作后，实机连续切换 Dock，并再次点击当前页，确认日志页正常显示 400 行。ADB 模拟侧滑未触发返回；随后发送一次系统 `KEYCODE_BACK`，WebUI 退出，前台回到原蓝牙设置，没有在 Dock 两页间回退。系统返回路径已通过，人工侧滑手势仍待用户复核。三个开关均为 1，ATFWD PID 2393、traced PID 13738、GNSS HAL PID 1465 保持不变，辅助服务停止。

测试包：`build-artifacts/service-fixes/系统服务稳定性修复-2.3.1-test.zip`。18 个文件逐字节对比通过。SHA-256：`08CE7BB2C60D844724EA7BAAB67862A6CA2A99661BF4DAC92EC6B9C08082EE3D`。临时传输目录及截图在验收后清理。

## 2026-10-02 追加：2.4-test 关闭开关后的日志建议

用户要求每个关闭的开关根据对应错误日志建议是否开启。新增只读 `diagnostics` 命令，读取 main/system/crash 中限定服务来源的最近最多 2000 条日志，再按 epoch 时间筛选最近五分钟。匹配 ATFWD gettid/SIGSYS、traced 指定 vsock 创建失败和 GNSS 缺失 AIDL 请求；不清空、不落盘、不轮询，不自动切换开关。

WebUI 在三个开关下方分别显示有错误建议开启、未发现暂时无需开启、读取失败无法判断。检查范围随结果说明；ATFWD 关闭但策略仍生效时不以无错误推断无需修复。进入页面、刷新和切换后检查；全开启时不扫描。新增只读命令不执行用户输入。

shell 与 JavaScript 检查通过；隔离日志样本验证三类各一条、过期与无关日志排除、读取失败。页面逻辑验证有错/无错/尚在生效/读取失败/全开启不扫描五种分支。设备真实只读扫描三项均为 0（当时三项修复均开启，不能用于判断关闭后是否需要）。已同步手机原模块，12:14:07 三个开关仍开启，原 PID 2393/13738/1465 保持不变；没有为了测试而关闭服务修复。关闭状态下的实际 WebUI 显示尚未实机验收。

版本 `2.4-test` / versionCode=7。包内 18 文件，路径 `build-artifacts/service-fixes/系统服务稳定性修复-2.4-test.zip`，SHA-256 `A035FA6BA8BE36B5E52AF0585B2B89E4CD60538D705A008E56A59EEAF3FA7792`。临时测试脚本与手机传输目录已清理。

## 2026-10-02 追加：2.4.1-test 修正 traced 标签漏判

用户授权修复日志建议的 traced 标签问题。真实失败日志使用 `perfetto` 标签；2.4 的标签筛选和正文匹配均只包含 `traced`，因此误报未发现。`control.sh` 的 diagnostics 已增加 `perfetto:V`，正文同时识别 traced/perfetto 下的指定 vsock 创建失败及 traced 服务启动失败。同步版本信息、两页标识和 README，未改动服务控制逻辑或开关选择。

Android shell 语法检查与 JavaScript 语法检查通过。隔离样本包含两条 perfetto 错误和一条无关 traced 日志，检测结果 traced_errors=2，其余为 0。12:39:26 设备检测时三个修复均已开启，traced PID 16246 运行、relay 为空，近五分钟对应错误为 0；没有关闭修复来制造错误。脚本已同步原模块；关闭状态的页面显示未重新触控验收，用户重新打开 WebUI 后使用新版本。

测试包 `build-artifacts/service-fixes/系统服务稳定性修复-2.4.1-test.zip`，18 文件与源码逐字节校验通过。SHA-256：`EAD293D14FDF331AD45380005AB990757DE1F84E08CA925A81B1033441F4D38A`。临时脚本、设备传输目录已清理。没有编译内核、刷写、重启手机或提交源码。
