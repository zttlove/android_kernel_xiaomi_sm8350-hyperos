# 系统服务稳定性修复

沿用原模块 ID `atfwd_seccomp_fix`，适配小米 11 Pro（mars）、Android 17 和当前 KernelSU/Hybrid Mount 环境；GNSS、TCM 开关接受 `OS4.0.0.19.XKACNXM`、`OS4.0.0.26.XKACNXM` 各自对应的精确 vendor 指纹。2.6.4-test 在 `.19` / `5.4.302-Dynamic-g3c304f2` 验证开关和 RTC 即时权限。

## 五个独立开关

| 功能 | 开启时 | 关闭时 | 生效时间 |
| --- | --- | --- | --- |
| ATFWD 服务修复 | vendor seccomp 策略只增加 `gettid: 1` | 挂载前移除本模块的策略覆盖，使用 ROM 原文件 | 下次开机；不自动重启 |
| 性能追踪服务修复 | 删除 `traced.relay_producer_port`，保留本地 Unix Socket | 恢复 `/product/etc/build.prop` 中的原值 | 即时；必要时仅重启 traced |
| GNSS 异常请求抑制 | 设置 `ro.gps.loc_sys_service.skip=1`，仅停止重复请求缺失 AIDL 接口的 `loc_sys_service` | 恢复当前开机原属性；仅恢复原来运行或被启动规则跳过的辅助服务 | 即时；开机早期只设置属性，后期补查服务 |
| MiuiPasswords TCM Socket 修复 | 仅增加 3 个已确认调用域向现有 `vendor_dpmtcm_socket` 写入的 SELinux 规则 | 删除本模块生成的规则；不关闭 SELinux | 下次开机加载 |
| `system_suspend` RTC 读取权限 | 允许 `system_suspend` 读取 `sysfs_rtc` 的 RTC 唤醒统计 | 删除本模块生成的读取规则；当前开机策略需重启后撤销 | 即时应用；下次开机持久化 |

新安装 ATFWD、traced、GNSS、TCM、RTC 五个开关全部默认关闭；升级保留合法的已有选择，新增、缺失或无效的配置均按关闭处理。安装阶段移除关闭的 ATFWD 覆盖文件；traced 在从未启用过修复时不操作通道属性。开关保存于模块 `config` 目录，WebUI 区分选择与当前生效状态。

用户应先查看各开关下方的只读日志检查和建议：发现对应错误时可自行选择开启，未发现时暂时无需开启；检查失败显示“无法判断”，不能据此自动启用。模块不会根据日志、安装、升级或页面刷新擅自把关闭的开关改为开启；用户之前已开启的项目仍按已保存的选择生效。关闭已生效的处理可能让原错误重新出现，页面关闭操作需要确认。

### TCM Socket 处理边界（2.5.0-test）

当前 ROM 中多个 `TcmReceiver` 调用域反复向 `/dev/socket/tcm` 写入，因 `vendor_dpmtcm_socket` 的 `sock_file write` 被 SELinux 拒绝，触发审计日志洪泛。实测确认的调用域为 `platform_app_36`、`bluetooth` 和 `joyose_app`。TCM 开关只在设备、ROM、Socket 标签和 `dpmd` 均匹配时生成以下三条最小规则：

```te
allow platform_app_36 vendor_dpmtcm_socket sock_file write;
allow bluetooth vendor_dpmtcm_socket sock_file write;
allow joyose_app vendor_dpmtcm_socket sock_file write;
```

规则写入模块目录后仅在下次开机由 KernelSU 加载；关闭时只删除内容完全匹配的本模块规则。当前开机的 SELinux 策略不会被动态修改，不关闭 SELinux，不放宽其他权限。WebUI 在 TCM 关闭时读取最近五分钟内的内核快照，发现对应拒绝才建议开启。

### `system_suspend` RTC 处理边界（2.6.0-test）

当前 ROM 的 `system_suspend` 服务运行在 `u:r:system_suspend:s0`，RTC 唤醒统计节点标记为 `sysfs_rtc`。日志确认它读取 `name`、`active_count`、`last_change_ms`、`max_time_ms`、`total_time_ms`、`active_time_ms`、`event_count` 等文件时被 SELinux 拒绝，造成 `audit_lost` 和 `audit: rate limit exceeded`。

此开关只增加以下最小文件读取权限：

```te
allow system_suspend sysfs_rtc file getattr;
allow system_suspend sysfs_rtc file open;
allow system_suspend sysfs_rtc file read;
```

规则不包含写入、创建、删除、重标记或其他 RTC/系统权限。开启时模块先校验 `mars`、Android 17、SELinux Enforcing、`system_suspend` 服务和 `sysfs_rtc` RTC 节点，再通过当前 KernelSU 的 `ksud sepolicy patch` 实时应用，并把同一规则写入模块策略供下次开机加载。关闭只能撤销下次开机的模块规则，当前开机已经加载的 SELinux 允许项需要重启后恢复。

### TCM / RTC 状态核对（2.6.1-test）

第 4、5 项状态直接通过现有 SELinux `access` 查询接口核对当前权限：TCM 检查三个调用域的 `sock_file write`，RTC 检查 `getattr/open/read`。查询只计算权限结果，不加载或修改策略，不修改配置和开关；不再依赖可能因启动检查中断而未更新的旧开机记录。

检测成功且权限完整允许时显示“当前权限已生效”；权限缺失时区分规则已准备与未准备，已重启仍未生效则提示检查加载日志；接口、上下文或 root 权限检测失败时明确显示“无法核实”，不冒充待重启。关闭后仍允许的权限可能来自当前尚未撤销的策略、ROM 或其他模块，不能据此要求用户反复重启，也不能仅凭查询结果判断具体策略来源。

模块备份应放在 KernelSU 活动模块目录之外；仅修改目录名为 `backup` 不会阻止其脚本执行。已有活动备份必须禁用并保留回滚记录，避免多份模块同时控制属性和服务。本版本没有改变策略加载顺序或权限范围。

### 完整 ZIP 升级的策略准备（2.6.2-test）

KernelSU 在替换升级目录后先加载 `sepolicy.rule`，再执行模块的 `post-fs-data.sh`。旧安装器只保留开关，没有把已开启的 TCM / RTC 规则准备到新目录；仅替换手机文件并保留旧策略的测试不能验证这条安装路径。

本版在安装阶段保留合法开关后，按 TCM / RTC 选择生成上文既有的三条写入或三条读取规则，供首次重启加载；TCM 仍限定已适配 ROM。不复制任意旧策略，不新增权限，不即时修改当前 SELinux 策略。新安装、缺失或无效选择均为关闭，两项全关时不保留策略文件。其他服务控制与开关生效时间不变。

完整 ZIP 安装后的开关、规则内容、首次重启实际权限与回滚需要单独验收；结果见工作记录和对应 Release 说明，不能用安装命令成功替代验证。

### GNSS 处理边界（2.6.3-test）

当前 `loc_sys_service` 等待 `vendor.qti.gnss.ILocAidlGnss/default`，vendor 实际提供旧 HIDL 接口。此开关抑制无效请求，不补齐 AIDL，也不保证该辅助服务的所有厂商扩展功能可用。保留 `/vendor/bin/hw/android.hardware.gnss@2.1-service-qti`（`gnss_service`），仍须用户进行室外搜星、连续导航和重启后验收。

- 开启前校验已确认的 `OS4.0.0.19.XKACNXM` 或 `OS4.0.0.26.XKACNXM` 版本、对应 vendor 指纹，以及辅助程序、init 配置和 HIDL 清单的 SHA-256；即时开启还检查原定位服务运行、AIDL 服务未注册。ROM 更新或配置不匹配时拒绝开启。
- `post-fs-data` 阶段只使用现有 `resetprop -n` 设置属性，不发 `ctl` 命令；`service.sh` 和即时切换只控制 `loc_sys_service`。
- 保存原空属性是否存在及辅助服务状态，限定本次开机。默认关闭且没有本模块状态时不操作属性或服务；遇到其他属性值拒绝覆盖。
- 独立设置命令：`sh /data/adb/modules/atfwd_seccomp_fix/control.sh set gnss 1`；关闭改为 `0`。不需要创建第二个模块。

## 修改范围

### TCM 开关的 .19 适配（2.6.4-test）

修复 `.19` 系统点击 TCM 时被旧 `.26` 版本判断拒绝的问题。实机确认 `/dev/socket/tcm` 仍标记为 `vendor_dpmtcm_socket`、`dpmd` 正在运行，且存在同类 `TcmReceiver` 写入拒绝。运行脚本与安装脚本同步接受 `.19`、`.26` 的精确版本和 vendor 指纹组合，保留设备、Android、SELinux、Socket、服务及应用检查；原有三条权限和下次开机加载方式不变。

RTC 在本次实机后端开启成功，已通过 SELinux 权限查询核实；未确认独立的 RTC 脚本缺陷，因此不改变其权限或接口。TCM 保存开启后仍需下次开机核实实际权限，不能把开关保存成功等同于已加载。本次不自动重启，以保留正在运行的临时测试内核。

### 关闭开关时的日志建议（2.5.0-test）

进入修复开关页、手动刷新或切换后，若有开关关闭，读取最近五分钟内最多 2000 条相关 logcat 记录，并读取内核日志快照，分别匹配 ATFWD 的 gettid/SIGSYS、traced 的指定 vsock 端点创建失败、GNSS 的缺失 AIDL 请求、TCM 的 `TcmReceiver`/`vendor_dpmtcm_socket` 拒绝。仅检查既定服务日志来源，排除 ADB 命令审计。

发现对应错误建议开启；未发现提示暂时无需开启；读取失败明确显示无法判断。traced 错误同时匹配 `traced` 和实际输出错误的 `perfetto` 标签，包括 vsock 创建失败和服务启动失败。日志受缓冲区覆盖和数量上限限制，不表示完整五分钟或历史上从未出错。ATFWD 关闭但策略仍生效时，提示下次开机实际关闭后再判断。所有开关开启时不进行这项额外扫描，不自动开启、不定时轮询、不保存原始日志。

- 仅使用现有 KernelSU 的 `resetprop` 和系统命令，不下载依赖。
- 不刷写 boot、vendor、product、vbmeta，不修改内核或用户数据。
- 不关闭 `persist.traced.enable`，不关闭 SELinux；TCM 只在用户启用独立开关后生成一条严格匹配的策略规则。
- 不常驻监听，也不定时采集日志。模块操作记录仅保留最后 40 行。
- ATFWD 策略保留原版权和英文接口，页面、说明、提示、新增注释使用中文。
- ATFWD 原策略和修复策略按已验证的 SHA-256 检查；配置变化时跳过旧覆盖，需重新适配。
- traced 只处理已经确认的 `vsock://-1:2010`；发现其他通道时停止操作。
- GNSS 只处理当前已确认的辅助客户端，不修改 init rc、VINTF 清单、定位 HAL 或任何系统镜像；TCM 不修改 vendor 原文件，仅使用 KernelSU 模块策略入口。

## 页面入口

KernelSU 管理器 → 模块 → 系统服务稳定性修复 → WebUI。

WebUI 随模块离线提供，使用 KernelSU 原生 root 桥接。普通浏览器只能显示页面，不能控制手机。

### 内核日志页面（2.3.1-test）

进入 WebUI 后点底部 Dock 栏的“内核日志”，可在独立页面查看 `dmesg` 快照，支持手动刷新、关键词和级别筛选，再点“修复开关”返回。2.2-test 起导航固定在底部，当前页面高亮，滚动时可直接切换；内容底部为导航和系统手势区域预留空间。

- 只读取最近 64 KiB 内的最多 400 行，进入页面读取一次，不自动轮询、不清空缓冲区、不保存日志文件。
- 时间戳是启动后的秒数；缓冲区会覆盖旧记录，此页面不是完整开机日志或历史归档。
- 级别取原始优先级最低三位；无法识别的行保留为“未知”。关键词筛选不区分大小写，仅匹配当前快照，不传入 shell。
- 原始日志按纯文本显示。读取失败会显示错误，已有快照明确标为旧数据；需要当前管理器授予的 root 权限。
- 内核缓冲区也包含用户空间服务写入的消息，不能只根据错误级别判定内核存在故障。
- 2.3.1-test 起 Dock 切换替换当前浏览历史，点击当前页不跳转，避免返回手势在两页之间逐次回退。更新后重新打开 WebUI，旧会话已经积累的历史不会由网页强行清除。

## 回滚

- 仅撤销 traced：在 WebUI 关闭“性能追踪服务修复”。它会恢复 ROM 原配置，可能重新触发每 5 秒重启。
- 仅撤销 ATFWD：关闭对应开关，用户自行重启后生效，可能重新触发 SIGSYS。
- 仅撤销 GNSS：关闭“GNSS 异常请求抑制”；恢复当前开机原属性与辅助服务状态，缺失 AIDL 请求可能重新出现。
- 仅撤销 TCM：关闭“MiuiPasswords TCM Socket 修复”并重启；下次开机不再加载本模块 TCM 规则，原拒绝日志可能重新出现。
- 仅撤销 RTC：关闭“system_suspend RTC 读取权限”并重启；当前开机已加载的允许项不会由模块伪造撤销，重启后恢复 ROM 原策略。
- 撤销整个模块：在 KernelSU 禁用模块，用户自行重启后，原系统属性和 vendor 文件恢复。
- 返回扩展前的版本：原备份包是文件快照，不是带完整安装校验的安装包；还原时需要同时恢复 `vendor_configs_file` 标签，并处理新增脚本和配置，不直接安装该快照包。

## 验收

1. ATFWD、traced 修复开启时，ATFWD PID 不变且 Seccomp 保持开启，traced PID 稳定且属性为空。
2. ATFWD 切换仅保存选择，不改变当前 policy、服务 PID 或 traced 属性。
3. traced 关闭恢复原属性，重新开启后恢复正常；不影响 ATFWD。
4. 无效命令/参数不修改配置；并发操作使用短期锁。
5. WebUI 从管理器打开并读取真实状态，开关、关闭确认、刷新和错误提示可用。
6. 重启持久化需要单独实机验证；未经重启验证不声称已完成这一项。
7. GNSS 开启后辅助服务停止、跳过属性为 `1`，新日志中不再出现该 AIDL 请求；关闭后可恢复，原定位服务 PID 不变。室外实际定位另行验证。
8. TCM 开启后必须重启；确认规则已加载、`TcmReceiver` 拒绝停止、`audit_lost` 不再快速增长，且 SELinux 仍为 `Enforcing`。
9. RTC 修复开启后，`system_suspend` 的 `sysfs_rtc` AVC 拒绝停止，`dumpsys suspend_control_internal` 能读取 RTC 唤醒统计，SELinux 仍为 `Enforcing`；关闭后重启，原权限状态恢复。

本模块处理 ATFWD、traced、GNSS 无效请求、已确认的 TCM Socket 拒绝和 `system_suspend` RTC 读取权限，不代表缺失的 GNSS AIDL 已实现、millet 等其他问题已修复，也不保证耗电问题已解决。
