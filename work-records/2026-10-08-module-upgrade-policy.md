# 统一模块完整 ZIP 升级策略准备修复记录

## 授权与基线

- 用户先授权临时 QEMU 离线验证和完整模块 ZIP 升级、备份、重启临时测试及异常恢复；发现安装阶段问题后，按 `WORK_RULES.md 2.7` 单独确认最小修复范围，用户回复“同意”。
- 基线：`dynamic` / `5ae52e705c75b3dcd00f111b6ca4853353bbe726`，本地和远程一致。
- 手机：mars / M2102K1AC，Android 17 / HyperOS `OS4.0.0.26.XKACNXM`；原临时运行内核 `5.4.302-Dynamic-g5ae52e7`，活动槽位 `_a`。
- 修复范围：模块安装器、版本显示、必要说明；随后按新源码提交编译、临时启动、完整模块升级验收、推送与发布。保留原五个 Windows 路径删除状态，不修改其他内核源码、分区或用户开关。

## 根因与已确认事实

- 原模块版本 `2.6.1-test` / versionCode `11`，五项开关均为 `1`。完整备份放在活动模块目录外，同时保存主机副本。
- 使用现有 `ksud module install` 安装待发布 ZIP，命令成功，待升级目录五项开关均保留为 `1`，但缺少 `sepolicy.rule`。
- 仓库 KernelSU 的 `handle_updated_modules` 用升级目录替换活动目录；`on_post_fs_data` 在处理升级后先调用 `load_sepolicy_rule`，最后才执行模块开机脚本。
- 模块在开机脚本内生成策略晚于加载时机；因此安装命令成功和开关保留不能证明首次重启权限已生效。此轮未重启，不能声称实测首次启动失败。
- 已取消旧 ZIP 的待生效升级并移除本次新增的空 `update` 标记；原活动模块文件、权限和开关复核保持原值，boot ID、槽位与 boot_a 哈希不变。

## 最小实现

- 模块版本 `2.6.2-test` / versionCode `12`，同步页面标题。
- `customize.sh` 在读取合法旧选择后，提前生成本模块既有 TCM / RTC 规则。TCM 仍限定已适配 ROM，权限内容与 `control.sh` 的固定文本相同。
- 原子保存规则；新安装、缺失或无效配置按关闭，两项全关时删除暂存及策略文件。写入失败停止安装，不默默丢失原选择。
- 不复制任意旧策略，不新增 SELinux 权限，不关闭 SELinux，不即时改变当前开机权限，不安装依赖，不修改用户选择或服务控制逻辑。
- 本问题属于 ROM 服务修复模块的安装流程；不是内核 CPU 修复，也不代表 GNSS AIDL 或耗电问题已解决。

## 验证与发布边界

- 必须检查新安装、非法选择、TCM / RTC 四种组合、与既有规则逐字节一致、脚本和 ZIP 权限；新安装五项默认关闭。
- 必须用完整 ZIP 升级实机，核对保留开关及首次启动前的规则，然后临时启动新提交对应内核，核对实际权限、日志与服务状态。
- 本记录在源码快照固定时仅描述实现和验收要求，以下在验收完成后补充实际结果；文档补充提交不改变产物来源和 Release 标签。
- 原 `20261008-0146` 标签保持指向 `5ae52e7`；原草稿在验收后绑定新标签，不发布旧待修复附件。最终 Image、AK3、模块和正式 Release 使用 `a4f8add91bd86fcf72a801eb6e3bd695117a67e5` / `20261008-2011`。

## 已完成验收与发布

- 41 项真实安装器隔离场景通过：新安装、32 种五开关组合、五项非法配置及机型/系统/ROM 拒绝；生成规则与 `control.sh` 的固定文本逐字节一致，任意旧策略未导入。四个源码脚本语法检查通过，ZIP 20 个条目和默认五项 `0`、权限均核对通过。
- 待发布模块 ZIP：`KernelSU-atfwd_seccomp_fix-2.6.2-test-20261008-2011.zip`，32,656 字节，SHA-256 `e070672ae52c381b7d0094e98dca6cae2e43f27a0759921f999eb4c4127c8dd3`，从 `a4f8add` 源码快照打包。
- 手机真实 `ksud module install` 完整升级成功；安装后五项合法选择保留为 `1`，首次启动前已生成六条既有规则，SHA-256 仍为 `099ab8d64c7207b632a673bf7afee244f8c51f5bdda0da9be9f546355a69074a`。
- 新提交完整 Clang/LLD 17.0.6 ThinLTO 构建通过；与前一已验证内核配置相比仅 LOCALVERSION 后缀不同。Image SHA-256 `b8b214416e57587eef767a2c94fd223113690eba55fc06e9b4e3264ff9520250`。
- 经一次重启到 bootloader 后使用 `fastboot boot` 临时启动 `5.4.302-Dynamic-ga4f8add`；boot ID `27a0a68d-a62e-4e04-bc8d-f864d3d75698`，Android 启动完成，八核 ARM32/ARM64 共 16/16 检查通过，CPU_OUT_OF_SPEC 位保持清除。
- 首次升级启动后，TCM 三个已确认域和 RTC 三条读取权限通过实际 SELinux access 查询，`tcm_active/verified`、`suspend_active/verified` 均为 `1`；RTC 唤醒统计可读取，SELinux 保持 Enforcing。ATFWD/traced/主 GNSS PID 在观察窗口稳定。
- 已授权 TCM 三域和 RTC 拒绝在采集窗口均为 `0`；审计限流存在丢失，不能仅用日志计数判断权限。另有 `theme` 域 TCM write 拒绝，不属于既有三域规则；显示初始化的 `msm_drm_bind → kthread_queue_work → kthread_insert_work` WARN 与前一测试内核相同，tainted 仍为 `512`。本轮未修改这些独立问题。
- 原活动槽位 `_a`、boot_a 哈希保持原值，未永久刷写分区或清理用户数据，五项用户选择未改变；旧活动目录中的备份仍保持禁用。
- AK3 当前、跨页增大、缩小三种长度及两种失败场景通过；893 个 ramdisk 条目、cpio 字节流和元数据、启动参数保持一致，原输入未修改；固定模板其余 14 项内容和 ZIP 元数据保持一致。
- 正式源码与标签已推送；`20261008-2011` Release 已发布为 Latest，仅上传八份必备附件，逐份下载 SHA-256 核对通过。Edge 实际 Latest 页面和附件链接已核对；网页另显示两份 GitHub 自动源码归档。当前执行环境匿名网页请求返回 404，原因未确认，不把它等同于 Release 未发布。
- 已清理本次构建输出/ThinLTO 缓存 8,221,848,002 字节及临时 QEMU 包、工具绑定；保留源码、产物、配置、符号、原 boot、临时 boot、模块完整备份、失败证据和校验记录。未压缩或卸载 WSL 虚拟磁盘，释放的 Linux 内部空间供后续复用。

本次新模块升级前完整备份位于 `release-work/20261008-module-upgrade/module-before.tar.gz`，SHA-256 `a7565e81817d5756dcdf5eda49ca8b7816a2452b39969566cf25fe32c57ea51d`。本地 `device-verification.json`、`installer-validation.json`、`module-staged-validation.json`、`source-push-receipt.json` 和 `release-publication-receipt.json` 等保留完整检查结果。

尚未复测 star、完整室外定位/导航、受控续航、全部应用、AK3 永久安装、已激活模块禁用后重启的回滚；已实测旧待生效升级取消回滚，不能将其描述成全部回滚路径均已验证。

## 回滚和证据

- 原活动模块完整备份在工作区 `release-work/20261008-cpu-feature-test/module-before.tar.gz`，SHA-256 为 `9899683fd92d11308812d55d5e4c16f4dcc06d1c92c69a4761bf850ee05824a1`；失败安装快照及安装、撤销记录同目录保留。
- 异常时只恢复本次模块及其用户配置和必要标签，不恢复分区、不清用户数据、不启用活动目录中的旧备份。
- 原 boot_a SHA-256：`3f04599d738975e81590caf2a87451317b17ffedc487ec53fc918040aeeedafe`；永久 boot 未改变，临时内核可通过普通重启退出。
