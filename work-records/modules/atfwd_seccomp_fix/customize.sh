#!/system/bin/sh
[ "$(getprop ro.product.device)" = mars ] || abort '本模块仅在小米 11 Pro（mars）验证。'
[ "$(getprop ro.build.version.release)" = 17 ] || abort '本版本仅适配 Android 17。'
ui_print '安装系统服务稳定性修复：ATFWD、traced、GNSS、TCM、RTC 分别控制。'
# 更新同一模块时保留用户选择；不执行或导入配置文件中的任何命令。
for feature in atfwd traced gnss tcm suspend; do
    # 新安装及新增开关默认关闭；只有合法的旧选择才覆盖默认值。
    printf '0\n' > "$MODPATH/config/${feature}_enabled" || abort '初始化开关失败。'
    old="/data/adb/modules/atfwd_seccomp_fix/config/${feature}_enabled"
    if [ -f "$old" ]; then
        value=$(cat "$old")
        case "$value" in 0|1) printf '%s\n' "$value" > "$MODPATH/config/${feature}_enabled" || abort '保留原开关失败。' ;; esac
    fi
done
# KernelSU 先加载策略再执行开机脚本；安装阶段需按已保存的选择准备规则。
# 只生成本模块既有权限，不复制旧策略，避免带入其他规则或默认启用修复。
policy_tmp="$MODPATH/sepolicy.rule.tmp"
: > "$policy_tmp" || abort '初始化模块策略失败。'
if [ "$(cat "$MODPATH/config/tcm_enabled")" = 1 ]; then
    [ "$(getprop ro.build.version.incremental)" = OS4.0.0.26.XKACNXM ] || abort 'ROM 版本不在 TCM 修复适配范围。'
    printf '%s\n' \
        'allow platform_app_36 vendor_dpmtcm_socket sock_file write;' \
        'allow bluetooth vendor_dpmtcm_socket sock_file write;' \
        'allow joyose_app vendor_dpmtcm_socket sock_file write;' >> "$policy_tmp" || abort '准备 TCM 策略失败。'
fi
if [ "$(cat "$MODPATH/config/suspend_enabled")" = 1 ]; then
    printf '%s\n' \
        'allow system_suspend sysfs_rtc file getattr;' \
        'allow system_suspend sysfs_rtc file open;' \
        'allow system_suspend sysfs_rtc file read;' >> "$policy_tmp" || abort '准备 RTC 策略失败。'
fi
if [ -s "$policy_tmp" ]; then
    mv -f "$policy_tmp" "$MODPATH/sepolicy.rule" || abort '保存模块策略失败。'
else
    rm -f "$policy_tmp" "$MODPATH/sepolicy.rule" || abort '移除关闭的模块策略失败。'
fi
# 在模块挂载之前移除关闭的覆盖文件，防止新安装自动放行 gettid。
if [ "$(cat "$MODPATH/config/atfwd_enabled")" = 0 ]; then
    rm -f "$MODPATH/system/vendor/etc/seccomp_policy/atfwd@2.0.policy" || abort '移除关闭的 ATFWD 覆盖失败。'
fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
for script in control.sh post-fs-data.sh service.sh customize.sh; do
    set_perm "$MODPATH/$script" 0 0 0755
done
# 策略标签必须与 vendor 原文件一致，避免再次触发已确认的读取失败。
chcon -R u:object_r:vendor_configs_file:s0 "$MODPATH/system/vendor" || abort '设置 vendor 策略标签失败。'
ui_print '新安装所有修复默认关闭；请查看错误日志和建议后自行开启。升级保留原选择。'
ui_print 'GNSS 开启仅抑制缺失 AIDL 的请求，仍需实机定位验收。'
