# TCM / RTC 重启提示误判修复记录

## 授权和基线

- 用户反馈：模块第 4、5 项重启后仍显示“规则已变更，需重启后加载或撤销”；完成只读诊断后，用户授权“最小方案进行修复”。
- 范围：现有模块的 `control.sh`、WebUI 状态检测/提示、版本和必要说明；生成测试 ZIP、更新现有手机模块文件验证，保留开关；禁用旧备份并保留回滚材料。不自动重启、不修改内核和分区、不发布。
- 分支 `dynamic`，基线 `f20758ef80ac78338090faa38a60171ccaeed217`。保留原有未提交的 RTC 和默认关闭改动，保留 5 个历史 Windows 路径删除状态。
- 手机 `40df69bc`，mars / Android 17 / `OS4.0.0.26.XKACNXM`，内核 `5.4.302-Dynamic-gb0773c7`，SELinux Enforcing；安装模块为 `2.6.0-test`。

## 诊断证据

- 当前 boot ID：`5d82438e-e021-452c-a10c-1ba3c65ec792`。
- TCM 旧记录：`d486b0a2-4952-478b-a3a2-bc9b8cc8d14e` / loaded `0`；RTC 旧记录：`30cec9af-7744-46d8-a717-393ea4c2562d` / loaded `1`。
- KernelSU 开机日志明确加载当前模块 `sepolicy.rule`，加载发生在模块 `post-fs-data.sh` 之前。
- 对实时 SELinux 权限计算：三个 TCM 调用域均返回 allowed `4`，对应 `sock_file write`；RTC allowed `40012`，对应 `file getattr/open/read`，不含 write `4`。六条所需权限均允许，诊断对应错误计数均为 `0`。
- 已确认页面把旧开机记录当作当前状态。启动脚本在 `mark_policy_boot` 之前要求 dpmd/Socket/服务就绪，存在提前退出的时序条件；本次未捕获具体退出语句，不将其描述为已确认的唯一原因。
- `/data/adb/modules/atfwd_seccomp_fix.backup-2.4.1-tcm` 没有 disable/remove，KernelSU 本次开机确实执行其 post-fs-data/service；备份内 ATFWD、traced、GNSS 均为 `1`，与当前模块 GNSS `0` 冲突。

## 最小实现

- 版本 `2.6.1-test` / versionCode `11`。
- 保留既有 `*_active=0/1` 字段，增加 `tcm_verified`、`suspend_verified` 标识检测是否完成；界面只在 verified 为 `1` 时解释权限结果。
- 使用系统现有 `/sys/fs/selinux/access` 接口计算访问向量；运行时读取 class/perms 编号，完整检查权限位。子 shell 独占描述符，异常单独返回，不生成策略或配置文件。
- 查询三条 TCM write 权限、RTC 三条读取权限；不以规则文件存在或旧 boot ID 代替实时查询。SELinux 非 Enforcing 或查询失败时明确报告无法核实。
- 页面区分完整允许、权限缺失、规则未准备、查询失败；关闭后仍允许时说明来源无法仅凭权限查询确定，不反复要求重启。
- 原策略加载流程、权限范围、其他功能实现保持原值；禁用旧备份用于阻止后续启动，不在本轮接管其已经写入的 GNSS 属性或服务。

## 验证与回滚

### 已通过

- 现有 WSL Bash 检查四个脚本语法；Node 检查 `app.js` 语法。没有安装工具或编译内核。
- 20 项后端隔离检查通过：完整/缺失权限、一个 TCM 域缺失或查询失败、异常响应、缺失接口/编号、非 Enforcing，以及旧 boot ID 的原问题复现。查询前后配置和状态逐文件哈希一致。
- 16 项 WebUI 状态回归通过，覆盖 TCM/RTC 的已生效、未加载、检测失败、缺规则、关闭且撤销、其他策略仍允许、允许但未准备持久化、规则残留；已生效时不显示重启提示。
- 测试包 `KernelSU-atfwd_seccomp_fix-2.6.1-test-policy-status.zip`，20 个源码条目，31,887 字节，SHA-256 `e42acdb3a4fd8ce842b25d9b2430490f6a2eedf02a314c808408336e4943f0f4`。ZIP 完整性、权限、逐条内容哈希和五个默认开关 `0` 检查通过；文本按 LF 导出，未修改无关文件的 Windows 换行。
- 手机更新前备份五个目标文件到 `/data/local/tmp/dynamic-module-policy-status-2.6.1/rollback`，位于活动模块目录之外。通过哈希校验、Android `sh -n`，事务替换 `control.sh`、`webroot/app.js`、`webroot/index.html`、`module.prop`、模块 `README.md`；任何替换或状态/配置校验失败均恢复这五个文件并撤销本轮新建的备份 disable。
- 更新后手机 `tcm_active=1 / tcm_verified=1`、`suspend_active=1 / suspend_verified=1`，实际核实两项权限完整允许；此前两项 active 均为 `0`。
- 当前开关仍为 ATFWD `1`、traced `1`、GNSS `0`、TCM `1`、RTC `1`；config、state、`sepolicy.rule` 所有现有文件的前后 SHA-256 清单逐字节一致，策略文件 SHA-256 仍为 `099ab8d64c7207b632a673bf7afee244f8c51f5bdda0da9be9f546355a69074a`。
- ATFWD PID `2585`、traced PID `2394`、GNSS PID `1575` 保持不变；内核仍为 `5.4.302-Dynamic-gb0773c7`，boot ID 未变化，未重启/刷写手机。
- 创建旧备份目录的 `disable` 标记，保留备份文件；阻止其后续由 KernelSU 启动，不在当前开机接管其已设置的 GNSS 属性。
- 更新后近五分钟的限定诊断：ATFWD、traced、GNSS、TCM、RTC 对应错误计数均 `0`；这是受缓冲区和采样范围限制的结果，不代表历史没有错误。

手机更新文件 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `control.sh` | `4339c988b60042e6c3f08a803bc7ed3b108ee07042337ea63943abc464a828f2` |
| `webroot/app.js` | `9c8ba807a82c232c7a5565d03273daec2b8aa902c7df9652466cb6e795f659c3` |
| `webroot/index.html` | `6718cf86175fb6b5640aab9ba4bd36ef2774cd3b61bef2cc0ba581a30325efc0` |
| `module.prop` | `8346cc92fef0670db6cd8af6489190c85e39543a3fdc495807e6bfe0c60d6c65` |
| `README.md` | `858c5264746d3b4d9378776e5c1f6da23b826d35d361c2d4528815cedfe33de0` |

本地报告位于工作区 `module-work/20261007-policy-status`：`local-validation.json`、`ui-validation.json`、`package-validation.json`、`device-deployment.txt`、`device-verification.txt`。临时测试脚本、模拟目录和手机暂存的新文件在校验后清理；测试包、报告和小型回滚备份保留到验收完成。

### 尚待验收

- 请用户关闭并重新打开 KernelSU WebUI，确认实际页面显示；重新打开用于避免旧 WebView 缓存，不修改浏览器数据。
- 用户手动重启后重新核对当前 boot ID、实时权限和状态；核对旧备份不再启动、当前 GNSS `0` 选择未被旧备份覆盖。未完成时不声称已通过重启持久化。
- 本次手机采用五个文件的最小事务更新，保留当前 `sepolicy.rule`；未在手机运行完整 ZIP 安装/升级，不把这一结果当作安装器策略保留路径已经验收，也不发布该测试包。

### 回滚方式

如需回滚，经用户确认后从上述非活动 `rollback` 目录逐项恢复五个原文件及其权限；如需恢复旧备份的启动行为，仅移除本轮创建的 `atfwd_seccomp_fix.backup-2.4.1-tcm/disable`，需要再次重启才重新执行启动脚本。不撤销原有 TCM/RTC 权限规则，不修改其他模块或开关。修复阶段当时未提交、推送或发布。用户随后授权提交和推送源码，本次按 RTC 读取权限、默认关闭、状态误判三个逻辑拆分提交；重启、完整安装/升级和 Release 验收仍按上述未完成范围记录。提交前同步源码 WebUI 标题版本为 2.6.1，未改变状态检测逻辑；此时手机已断开，标题同步未传输成功，手机上述部署哈希仍对应修复时的文件，标题显示 2.6.0 不代表后台模块仍是旧版本。
