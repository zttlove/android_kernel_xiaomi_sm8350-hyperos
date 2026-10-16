#!/system/bin/sh
# 只接受固定功能与 0/1 开关，不执行 WebUI 传入的任意代码。
MODDIR=$(cd "${0%/*}" && pwd) || exit 1
CONFIG="$MODDIR/config"
STATE="$MODDIR/state"
LOCK="$STATE/.lock"
POLICY="$MODDIR/system/vendor/etc/seccomp_policy/atfwd@2.0.policy"
RELAY=traced.relay_producer_port
RESETPROP=/data/adb/ksu/bin/resetprop
FIXED_HASH=76402d01474d0f67fe41f7220811b08b5fc60e09a875c46854e2788bdce1d643
STOCK_HASH=245f83d543bf32fa14d80cdec0527ab7d51384e3d9f3721ca185b52884837f70
GNSS_SKIP=ro.gps.loc_sys_service.skip
GNSS_RC_HASH=bdb98db727c2da512e5179e6aab20ad73cf53ca1fe6227f176fcf2540016adff
GNSS_BIN_HASH=aa67db15dcaa35c498f22e19234c8052c64c61b0562bb9c1208392ef62929ce1
GNSS_MANIFEST_HASH=a2febcc396f453bdabfe60f8adc9b0bc89b110845b3bd4b0c582ce35054a5f4e
TCM_RULE="$MODDIR/sepolicy.rule"
TCM_RULE_TEXT='allow platform_app_36 vendor_dpmtcm_socket sock_file write;
allow bluetooth vendor_dpmtcm_socket sock_file write;
allow joyose_app vendor_dpmtcm_socket sock_file write;'
SUSPEND_RULE_TEXT='allow system_suspend sysfs_rtc file getattr;
allow system_suspend sysfs_rtc file open;
allow system_suspend sysfs_rtc file read;'

fail() { printf '%s\n' "$*" >&2; exit 1; }
flag() {
    value=$(cat "$CONFIG/${1}_enabled" 2>/dev/null)
    case "$value" in 0|1) printf '%s' "$value" ;; *) printf 0 ;; esac
}
save() {
    printf '%s\n' "$2" > "$1.tmp" && chmod 0600 "$1.tmp" && mv -f "$1.tmp" "$1"
}
note() {
    printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$STATE/events.log"
    tail -n 40 "$STATE/events.log" > "$STATE/events.tmp" && mv -f "$STATE/events.tmp" "$STATE/events.log"
}
# 避开 Android mksh 内置的 hash 别名，确保实际调用 SHA-256 校验。
file_hash() { sha256sum "$1" 2>/dev/null | cut -d ' ' -f 1; }
# access 是 SELinux 的权限查询接口；提交上下文只计算结果，不加载或修改策略。
# 使用子 shell 独占描述符，失败返回 2，不能把无法检测当作权限未加载。
policy_access() (
    source=$1; target=$2; class=$3
    shift 3
    [ "$(getenforce 2>/dev/null)" = Enforcing ] || exit 2
    class_id=$(cat "/sys/fs/selinux/class/$class/index" 2>/dev/null) || exit 2
    case "$class_id" in ''|*[!0-9]*) exit 2 ;; esac
    [ "$class_id" -ge 1 ] && [ "$#" -gt 0 ] || exit 2
    mask=0
    for permission in "$@"; do
        index=$(cat "/sys/fs/selinux/class/$class/perms/$permission" 2>/dev/null) || exit 2
        case "$index" in ''|*[!0-9]*) exit 2 ;; esac
        [ "$index" -ge 1 ] && [ "$index" -le 32 ] || exit 2
        mask=$((mask | (1 << (index - 1))))
    done
    [ -e /sys/fs/selinux/access ] || exit 2
    exec 3<> /sys/fs/selinux/access 2>/dev/null || exit 2
    printf '%s' "$source $target $class_id" >&3 || exit 2
    response=$(cat <&3) || exit 2
    set -- $response
    [ "$#" -eq 6 ] || exit 2
    case "$1" in ''|*[!0-9a-fA-F]*) exit 2 ;; esac
    [ "${#1}" -le 8 ] || exit 2
    [ $((0x$1 & mask)) -eq "$mask" ]
)
policy_active() (
    result=0
    case "$1" in
        tcm)
            for domain in platform_app_36 bluetooth joyose_app; do
                policy_access "u:r:$domain:s0" u:object_r:vendor_dpmtcm_socket:s0 sock_file write
                case "$?" in 0) ;; 1) [ "$result" = 0 ] && result=1 ;; *) result=2 ;; esac
            done
            exit "$result"
            ;;
        suspend) policy_access u:r:system_suspend:s0 u:object_r:sysfs_rtc:s0 file getattr open read ;;
        *) exit 2 ;;
    esac
)
guard() {
    [ "$(getprop ro.product.device)" = mars ] || fail '设备不在适配范围，未应用修复。'
    [ "$(getprop ro.build.version.release)" = 17 ] || fail 'Android 版本不在适配范围，未应用修复。'
    [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ] || fail '模块已禁用或待卸载。'
}
lock() {
    umask 077
    mkdir -p "$CONFIG" "$STATE" || fail '无法创建模块配置目录。'
    # 锁只在当前开机内有效，避免异常中断留下的旧锁阻止下次开机。
    boot_id=$(cat /proc/sys/kernel/random/boot_id)
    if [ -d "$LOCK" ] && [ "$(cat "$STATE/lock_boot" 2>/dev/null)" != "$boot_id" ]; then
        rmdir "$LOCK" 2>/dev/null
    fi
    mkdir "$LOCK" 2>/dev/null || fail '另一项操作正在执行，请稍后刷新。'
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    trap 'exit 1' HUP INT TERM
    printf '%s\n' "$boot_id" > "$STATE/lock_boot"
}
status() {
    printf 'atfwd_enabled=%s\ntraced_enabled=%s\ntcm_enabled=%s\nsuspend_enabled=%s\n' "$(flag atfwd)" "$(flag traced)" "$(flag tcm)" "$(flag suspend)"
    active=0
    grep -q '^gettid: 1$' /vendor/etc/seccomp_policy/atfwd@2.0.policy && active=1
    printf 'atfwd_active=%s\natfwd_service=%s\natfwd_pid=%s\n' "$active" "$(getprop init.svc.vendor.atfwd)" "$(getprop init.svc_debug_pid.vendor.atfwd)"
    printf 'traced_service=%s\ntraced_pid=%s\nrelay=%s\n' "$(getprop init.svc.traced)" "$(getprop init.svc_debug_pid.traced)" "$(getprop "$RELAY")"
    printf 'traced_probes=%s\ntraced_master=%s\n' "$(getprop init.svc.traced_probes)" "$(getprop persist.traced.enable)"
    gnss_active=0
    if gnss_owned && [ "$(getprop "$GNSS_SKIP")" = 1 ] && [ "$(getprop init.svc.loc_sys_service)" = stopped ]; then gnss_active=1; fi
    printf 'gnss_enabled=%s\ngnss_active=%s\ngnss_skip=%s\n' "$(flag gnss)" "$gnss_active" "$(getprop "$GNSS_SKIP")"
    printf 'gnss_aux_service=%s\ngnss_aux_pid=%s\ngnss_service=%s\ngnss_pid=%s\n' "$(getprop init.svc.loc_sys_service)" "$(getprop init.svc_debug_pid.loc_sys_service)" "$(getprop init.svc.gnss_service)" "$(getprop init.svc_debug_pid.gnss_service)"
    tcm_rule=0
    [ -f "$TCM_RULE" ] && [ "$(grep -Fc 'allow platform_app_36 vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow bluetooth vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow joyose_app vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && tcm_rule=1
    # 启动脚本可能在服务未就绪时退出；旧开机标记不能证明当前权限状态。
    tcm_active=0; tcm_verified=1
    policy_active tcm
    case "$?" in 0) tcm_active=1 ;; 1) ;; *) tcm_verified=0 ;; esac
    printf 'tcm_rule=%s\ntcm_active=%s\ntcm_verified=%s\n' "$tcm_rule" "$tcm_active" "$tcm_verified"
    suspend_rule=0
    [ -f "$TCM_RULE" ] && [ "$(grep -Fc 'allow system_suspend sysfs_rtc file ' "$TCM_RULE" 2>/dev/null)" = 3 ] && suspend_rule=1
    suspend_active=0; suspend_verified=1
    policy_active suspend
    case "$?" in 0) suspend_active=1 ;; 1) ;; *) suspend_verified=0 ;; esac
    printf 'suspend_rule=%s\nsuspend_active=%s\nsuspend_verified=%s\n' "$suspend_rule" "$suspend_active" "$suspend_verified"
    printf 'device=%s\nandroid=%s\nrom=%s\nkernel=%s\n' "$(getprop ro.product.device)" "$(getprop ro.build.version.release)" "$(getprop ro.build.version.incremental)" "$(uname -r)"
    printf 'checked=%s\n' "$(date '+%H:%M:%S')"
}
kernel_logs() {
    # 只读取快照，不清空、不持续跟踪，也不写入模块状态文件。
    # -S 使用 syslog 快照接口；默认 /dev/kmsg 路径不遵守此设备的 -s 限制。
    # 截掉可能不完整的首行，并保留上游失败状态，避免权限错误被 tail 掩盖。
    set -o pipefail
    dmesg -S -r -s 65536 | tail -c 65536 | sed -n '/^<[0-9][0-9]*>/,$p' | tail -n 400 || fail '读取内核日志失败，请确认 KernelSU root 权限。'
}
apply_traced() {
    # 从未启用过修复时保持原状，不覆盖其他组件设置的通道。
    if [ "$(flag traced)" = 0 ] && [ ! -f "$STATE/relay_original" ]; then return 0; fi
    [ -x "$RESETPROP" ] || fail '现有 resetprop 不可用，未安装任何新工具。'
    current=$(getprop "$RELAY")
    # 只处理已确认的通道。ROM 更新后出现其他配置时不擅自删除。
    case "$current" in ''|'vsock://-1:2010') ;; *) fail '发现不同的 traced 通道配置，请重新分析后再使用。' ;; esac
    rom_relay=$(sed -n 's/^traced\.relay_producer_port=//p' /product/etc/build.prop | head -n 1)
    case "$rom_relay" in ''|'vsock://-1:2010') ;; *) fail 'ROM 的通道配置已变化，请重新分析。' ;; esac
    changed=0
    if [ "$(flag traced)" = 1 ]; then
        if [ -n "$current" ]; then
            save "$STATE/relay_original" "$current" || fail '保存原属性失败，未应用修复。'
            "$RESETPROP" -n --delete "$RELAY" || fail '删除错误通道属性失败。'
            [ -z "$(getprop "$RELAY")" ] || fail '属性仍然存在，修复未生效。'
            changed=1
            note 'traced：已移除错误的 vsock 端点，保留本地性能追踪。'
        fi
    else
        # 恢复当前 ROM 的配置，不把旧 ROM 的值带到新版 ROM。
        if [ "$current" != "$rom_relay" ]; then
            if [ -n "$rom_relay" ]; then
                "$RESETPROP" -n "$RELAY" "$rom_relay" || fail '恢复原通道配置失败。'
            else
                "$RESETPROP" -n --delete "$RELAY" || fail '恢复空通道配置失败。'
            fi
            changed=1
            note 'traced：修复已关闭，恢复 ROM 原通道配置。'
        fi
    fi
    # 启动早期只处理属性；即时切换仅重启 traced，不重启手机或其他服务。
    if [ "$1" = live ] && [ "$changed" = 1 ] && [ "$(getprop persist.traced.enable)" = 1 ]; then
        setprop ctl.restart traced || fail '属性已更新，但重启 traced 失败，请刷新状态。'
        if [ "$(flag traced)" = 1 ]; then
            # init 可能按默认重启间隔延迟拉起，最多等待八秒。
            remaining=8
            while [ "$remaining" -gt 0 ] && [ "$(getprop init.svc.traced)" != running ]; do
                sleep 1
                remaining=$((remaining - 1))
            done
        fi
    fi
}
gnss_owned() {
    [ "$(cat "$STATE/gnss_boot" 2>/dev/null)" = "$(cat /proc/sys/kernel/random/boot_id)" ]
}
check_gnss() {
    [ -x "$RESETPROP" ] || fail '现有 resetprop 不可用，未应用 GNSS 处理。'
    # .19 与已验证的 .26 共用相同 GNSS 三文件哈希，仍要求精确版本和 vendor 指纹匹配。
    case "$(getprop ro.build.version.incremental):$(getprop ro.vendor.build.fingerprint)" in
        'OS4.0.0.19.XKACNXM:Xiaomi/mars/mars:13/RKQ1.211001.001/OS4.0.0.19.XKACNXM:user/release-keys'|\
        'OS4.0.0.26.XKACNXM:Xiaomi/mars/mars:13/RKQ1.211001.001/OS4.0.0.26.XKACNXM:user/release-keys') ;;
        *) fail 'ROM 或 vendor 版本已变化，需要重新适配 GNSS。' ;;
    esac
    [ "$(file_hash /system_ext/etc/init/loc_sys_service.rc)" = "$GNSS_RC_HASH" ] &&
    [ "$(file_hash /system_ext/bin/loc_sys_service)" = "$GNSS_BIN_HASH" ] &&
    [ "$(file_hash /vendor/etc/vintf/manifest/vendor.qti.gnss@4.0-service.xml)" = "$GNSS_MANIFEST_HASH" ] || fail 'GNSS 程序、启动配置或 vendor 清单已变化，需要重新分析。'
    current_skip=$(getprop "$GNSS_SKIP")
    case "$current_skip" in
        '') ;;
        1) gnss_owned || fail '跳过属性由其他组件设置，未接管。' ;;
        *) fail '发现其他 GNSS 跳过属性值，未修改。' ;;
    esac
    if [ "$1" = live ]; then
        [ "$(getprop init.svc.gnss_service)" = running ] || fail '原有 HIDL 定位服务未运行，先检查定位状态。'
        services=$(service list) || fail '无法读取 Binder 服务列表，未应用 GNSS 处理。'
        printf '%s\n' "$services" | grep -Fq 'vendor.qti.gnss.ILocAidlGnss/default' && fail 'AIDL 服务已存在，不应跳过客户端。'
    fi
    return 0
}
wait_gnss() {
    remaining=5
    while [ "$remaining" -gt 0 ] && [ "$(getprop init.svc.loc_sys_service)" != "$1" ]; do
        sleep 1
        remaining=$((remaining - 1))
    done
    [ "$(getprop init.svc.loc_sys_service)" = "$1" ] || fail 'GNSS 辅助服务尚未达到目标状态，请刷新检查。'
}
apply_gnss() {
    if [ "$(flag gnss)" = 1 ]; then
        check_gnss "$1"
        if ! gnss_owned; then
            # 只保存当前开机的原状态，避免 OTA 后恢复旧 ROM 的属性。
            existed=0
            getprop | grep -q '^\[ro.gps.loc_sys_service.skip\]:' && existed=1
            resume=0
            if [ "$1" = boot ] || [ "$(getprop init.svc.loc_sys_service)" = running ]; then resume=1; fi
            save "$STATE/gnss_original_exists" "$existed" &&
            save "$STATE/gnss_resume" "$resume" &&
            save "$STATE/gnss_boot" "$(cat /proc/sys/kernel/random/boot_id)" || fail '保存 GNSS 原状态失败。'
        fi
        if [ "$(getprop "$GNSS_SKIP")" != 1 ]; then
            "$RESETPROP" -n "$GNSS_SKIP" 1 || fail '设置 GNSS 跳过属性失败。'
            [ "$(getprop "$GNSS_SKIP")" = 1 ] || fail 'GNSS 跳过属性未生效。'
            note 'GNSS：已设置 ROM 自带的跳过属性，仅针对 loc_sys_service。'
        fi
        # post-fs-data 只设置属性，避免 ctl 属性等待 init 导致启动阻塞。
        if [ "$1" = live ] && [ "$(getprop init.svc.loc_sys_service)" != stopped ]; then
            setprop ctl.stop loc_sys_service || fail '停止 GNSS 辅助服务失败。'
            wait_gnss stopped
            note 'GNSS：已停止不存在的 AIDL 接口请求，保留 gnss_service。'
        fi
    elif gnss_owned; then
        # 不恢复其他模块或用户写入的新属性，也不启动本来停止的服务。
        case "$(getprop "$GNSS_SKIP")" in ''|1) ;; *) fail 'GNSS 属性被其他组件更改，未覆盖。' ;; esac
        [ -x "$RESETPROP" ] || fail 'resetprop 不可用，未恢复 GNSS 状态。'
        if [ "$(cat "$STATE/gnss_original_exists")" = 1 ]; then
            "$RESETPROP" -n "$GNSS_SKIP" '' || fail '恢复原 GNSS 空属性失败。'
        else
            "$RESETPROP" -n --delete "$GNSS_SKIP" || fail '撤销 GNSS 跳过属性失败。'
        fi
        [ -z "$(getprop "$GNSS_SKIP")" ] || fail 'GNSS 属性未恢复。'
        if [ "$1" = live ] && [ "$(cat "$STATE/gnss_resume")" = 1 ] && [ "$(getprop init.svc.loc_sys_service)" != running ]; then
            setprop ctl.start loc_sys_service || fail '恢复 GNSS 辅助服务失败。'
            wait_gnss running
        fi
        rm -f "$STATE/gnss_boot" "$STATE/gnss_original_exists" "$STATE/gnss_resume"
        note 'GNSS：处理已关闭，恢复本次开机原状态，AIDL 错误可能重新出现。'
    fi
}
check_tcm() {
    # 只增加实机核对过的 .19；版本与 vendor 指纹必须成对匹配。
    case "$(getprop ro.build.version.incremental):$(getprop ro.vendor.build.fingerprint)" in
        'OS4.0.0.19.XKACNXM:Xiaomi/mars/mars:13/RKQ1.211001.001/OS4.0.0.19.XKACNXM:user/release-keys'|\
        'OS4.0.0.26.XKACNXM:Xiaomi/mars/mars:13/RKQ1.211001.001/OS4.0.0.26.XKACNXM:user/release-keys') ;;
        *) fail 'ROM 或 vendor 版本不在 TCM 修复适配范围。' ;;
    esac
    [ "$(getenforce 2>/dev/null)" = Enforcing ] || fail 'SELinux 不是 Enforcing，未应用 TCM 修复。'
    [ -e /dev/socket/tcm ] || fail '未找到 /dev/socket/tcm，未应用 TCM 修复。'
    ls -Z /dev/socket/tcm 2>/dev/null | grep -Fq 'vendor_dpmtcm_socket' || fail 'TCM Socket 标签已变化，需要重新分析。'
    pidof dpmd >/dev/null 2>&1 || fail 'dpmd 未运行，未应用 TCM 修复。'
    dumpsys package com.miui.passwords 2>/dev/null | grep -Fq 'com.miui.passwords' || fail 'MiuiPasswords 未安装，未应用 TCM 修复。'
}

check_suspend() {
    [ "$(getprop ro.product.device)" = mars ] || fail '设备不在 RTC 权限修复适配范围。'
    [ "$(getprop ro.build.version.release)" = 17 ] || fail 'Android 版本不在 RTC 权限修复适配范围。'
    [ "$(getenforce 2>/dev/null)" = Enforcing ] || fail 'SELinux 不是 Enforcing，未应用 RTC 权限修复。'
    ps -AZ 2>/dev/null | grep -Fq 'u:r:system_suspend:s0' || fail 'system_suspend 服务未运行，未应用 RTC 权限修复。'
    found=0
    for wakeup in /sys/class/rtc/rtc*/wakeup*; do
        [ -d "$wakeup" ] || continue
        ls -Zd "$wakeup" 2>/dev/null | grep -Fq 'sysfs_rtc' || continue
        [ -r "$wakeup/name" ] && found=1
    done
    [ "$found" = 1 ] || fail '未找到 sysfs_rtc 的 RTC 唤醒统计节点。'
}

policy_expected() {
    [ "$(flag tcm)" = 1 ] && printf '%s\n' "$TCM_RULE_TEXT"
    [ "$(flag suspend)" = 1 ] && printf '%s\n' "$SUSPEND_RULE_TEXT"
}

policy_is_owned() {
    current=$1
    [ -z "$current" ] && return 0
    [ "$current" = "$TCM_RULE_TEXT" ] && return 0
    [ "$current" = "$SUSPEND_RULE_TEXT" ] && return 0
    [ "$current" = "$(printf '%s\n%s' "$TCM_RULE_TEXT" "$SUSPEND_RULE_TEXT")" ] && return 0
    [ "$current" = "$(printf '%s\n%s' "$SUSPEND_RULE_TEXT" "$TCM_RULE_TEXT")" ] && return 0
    return 1
}

prepare_policy() {
    [ "$(flag tcm)" = 1 ] && check_tcm
    [ "$(flag suspend)" = 1 ] && check_suspend
    current=$(cat "$TCM_RULE" 2>/dev/null)
    policy_is_owned "$current" || fail '发现非本模块生成的 sepolicy.rule 内容，未覆盖。'
    expected=$(policy_expected)
    if [ "$current" != "$expected" ]; then
        if [ -z "$expected" ]; then
            rm -f "$TCM_RULE" || fail '撤销模块策略失败。'
        else
            printf '%s\n' "$expected" > "$TCM_RULE.tmp" && chmod 0644 "$TCM_RULE.tmp" && mv -f "$TCM_RULE.tmp" "$TCM_RULE" || fail '准备模块策略失败。'
        fi
        note "策略：已根据 TCM 和 system_suspend 开关更新规则。"
    fi
}

mark_policy_boot() {
    tcm_loaded=0
    suspend_loaded=0
    [ -f "$TCM_RULE" ] && [ "$(grep -Fc 'allow platform_app_36 vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow bluetooth vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow joyose_app vendor_dpmtcm_socket sock_file write;' "$TCM_RULE" 2>/dev/null)" = 1 ] && tcm_loaded=1
    [ -f "$TCM_RULE" ] && [ "$(grep -Fc 'allow system_suspend sysfs_rtc file getattr;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow system_suspend sysfs_rtc file open;' "$TCM_RULE" 2>/dev/null)" = 1 ] && [ "$(grep -Fc 'allow system_suspend sysfs_rtc file read;' "$TCM_RULE" 2>/dev/null)" = 1 ] && suspend_loaded=1
    save "$STATE/tcm_boot" "$(cat /proc/sys/kernel/random/boot_id)" || fail '保存 TCM 开机状态失败。'
    save "$STATE/tcm_loaded" "$tcm_loaded" || fail '保存 TCM 策略状态失败。'
    save "$STATE/suspend_boot" "$(cat /proc/sys/kernel/random/boot_id)" || fail '保存 RTC 权限开机状态失败。'
    save "$STATE/suspend_loaded" "$suspend_loaded" || fail '保存 RTC 权限状态失败。'
}

apply_suspend_live() {
    [ "$(flag suspend)" = 1 ] || return 0
    check_suspend
    /data/adb/ksud sepolicy check "$SUSPEND_RULE_TEXT" >/dev/null 2>&1 || fail 'RTC 权限规则格式不受当前 KernelSU 支持。'
    /data/adb/ksud sepolicy patch "$SUSPEND_RULE_TEXT" >/dev/null 2>&1 || fail '实时应用 RTC 权限规则失败。'
    save "$STATE/suspend_boot" "$(cat /proc/sys/kernel/random/boot_id)" || fail '保存 RTC 权限开机状态失败。'
    save "$STATE/suspend_loaded" 1 || fail '保存 RTC 权限状态失败。'
    note 'system_suspend：已实时允许读取 sysfs_rtc 的 RTC 唤醒统计。'
}
prepare_atfwd() {
    if [ "$(flag atfwd)" = 0 ]; then
        # 挂载前移除本模块的单个覆盖文件，恢复真正的 vendor 策略。
        rm -f "$POLICY" || fail '撤销 ATFWD 覆盖失败。'
        note 'ATFWD：本次开机不覆盖 vendor 策略。'
        return
    fi
    [ "$(file_hash "$MODDIR/assets/atfwd-fixed.policy")" = "$FIXED_HASH" ] || fail 'ATFWD 修复策略校验失败。'
    current_hash=$(file_hash /vendor/etc/seccomp_policy/atfwd@2.0.policy)
    case "$current_hash" in
        "$STOCK_HASH"|"$FIXED_HASH") ;;
        *) rm -f "$POLICY"; fail 'vendor 策略已变化，已跳过旧策略覆盖，需重新适配。' ;;
    esac
    mkdir -p "${POLICY%/*}" || fail '创建策略目录失败。'
    if [ "$(file_hash "$POLICY")" != "$FIXED_HASH" ]; then
        cp "$MODDIR/assets/atfwd-fixed.policy" "$POLICY.tmp" && chmod 0644 "$POLICY.tmp" && mv -f "$POLICY.tmp" "$POLICY" || fail '准备 ATFWD 策略失败。'
    fi
    chmod 0755 "$MODDIR/system" "$MODDIR/system/vendor" "$MODDIR/system/vendor/etc" "${POLICY%/*}" || fail '设置策略目录权限失败。'
    chcon -R u:object_r:vendor_configs_file:s0 "$MODDIR/system/vendor" || fail '设置 vendor 策略标签失败。'
    note 'ATFWD：已准备仅增加 gettid 的修复策略。'
}

diagnostics() {
    # 仅读取近五分钟内最多 2000 条相关日志，限定来源，排除 ADB 命令审计。
    snapshot=$(logcat -b main -b system -b crash -d -t 2000 -v epoch -s ATFWD-daemon:V init:V traced:V perfetto:V libc:V libbinder.ServiceManagerCppClient:V servicemanager:V '*:S' 2>/dev/null) || fail '读取日志失败，无法判断是否需要开启。'
    cutoff=$(($(date +%s) - 300))
    printf '%s\n' "$snapshot" | awk -v cutoff="$cutoff" '
        $1 + 0 >= cutoff {
            if ($0 ~ /ATFWD-daemon.*blocked syscall: gettid/ || $0 ~ /init.*vendor[.]atfwd.*SIGSYS/) a++
            if ($0 ~ /(traced|perfetto).*Failed to create vsock:\/\/-1:2010/ || $0 ~ /(traced|perfetto).*Failed to start the traced service/) t++
            if ($0 ~ /vendor[.]qti[.]gnss[.]ILocAidlGnss\/default/ && $0 ~ /Waited one second|Unable to set property|Could not find|Trying to start/) g++
        }
        END { printf "atfwd_errors=%d\ntraced_errors=%d\ngnss_errors=%d\n", a, t, g }
    ' || fail '解析日志失败，无法判断是否需要开启。'
    now=$(cut -d. -f1 /proc/uptime 2>/dev/null) || fail '读取运行时间失败，无法检查内核日志。'
    cutoff=$((now - 300))
    kernel_snapshot=$(dmesg -S -r -s 65536 2>/dev/null) || fail '读取内核审计日志失败，无法判断是否需要开启。'
    printf '%s\n' "$kernel_snapshot" | awk -v cutoff="$cutoff" '
        {
            line=$0; sub(/^<[0-9]+>/, "", line); ts=line
            sub(/^\[[ \t]*/, "", ts); sub(/\..*$/, "", ts)
            if ((ts + 0) >= cutoff && line ~ /TcmReceiver/ && line ~ /vendor_dpmtcm_socket/) n++
        }
        END { printf "tcm_errors=%d\n", n + 0 }
    '
    printf '%s\n' "$kernel_snapshot" | awk -v cutoff="$cutoff" '
        {
            line=$0; sub(/^<[0-9]+>/, "", line); ts=line
            sub(/^\[[ \t]*/, "", ts); sub(/\..*$/, "", ts)
            if ((ts + 0) >= cutoff && line ~ /scontext=u:r:system_suspend:s0/ && line ~ /tcontext=u:object_r:sysfs_rtc:s0/ && line ~ /denied/) n++
        }
        END { printf "suspend_errors=%d\n", n + 0 }
    '
    printf 'diagnostics_checked=%s\n' "$(date '+%H:%M:%S')"
}

case "$1" in
    status) status ;;
    logs) [ ! -f "$STATE/events.log" ] || tail -n 40 "$STATE/events.log" ;;
    kernel-logs) kernel_logs ;;
    diagnostics) diagnostics ;;
    boot)
        guard; lock
        prepare_atfwd
        apply_traced boot
        apply_gnss boot
        prepare_policy
        mark_policy_boot
        ;;
    apply)
        guard; lock
        apply_traced live
        apply_gnss live
        ;;
    set)
        case "$2:$3" in atfwd:0|atfwd:1|traced:0|traced:1|gnss:0|gnss:1|tcm:0|tcm:1|suspend:0|suspend:1) ;; *) fail '开关参数无效。' ;; esac
        guard; lock
        if [ "$2" = traced ]; then
            # 在改变用户选择前先验证通道，避免失败时留下错误配置。
            case "$(getprop "$RELAY")" in ''|'vsock://-1:2010') ;; *) fail '通道配置已变化，未保存开关。' ;; esac
        fi
        if [ "$2:$3" = gnss:1 ]; then check_gnss live; fi
        if [ "$2:$3" = tcm:1 ]; then check_tcm; fi
        if [ "$2:$3" = suspend:1 ]; then check_suspend; fi
        save "$CONFIG/${2}_enabled" "$3" || fail '保存开关失败。'
        if [ "$2" = tcm ]; then
            prepare_policy
            printf 'TCM 开关已保存；SELinux 规则将在下次开机加载，请重启后验证。\n'
        elif [ "$2" = suspend ]; then
            prepare_policy
            if [ "$3" = 1 ]; then
                apply_suspend_live
                printf 'RTC 读取权限修复已保存并实时应用；请刷新状态后观察 system_suspend 日志。\n'
            else
                printf 'RTC 读取权限修复已关闭；当前开机策略无法撤销，重启后恢复。\n'
            fi
        elif [ "$2" = gnss ]; then
            apply_gnss live
            printf 'GNSS 开关已保存并应用；请检查状态并进行室外定位测试。\n'
        elif [ "$2" = traced ]; then
            apply_traced live
            if [ "$3" = 1 ] && [ "$(getprop init.svc.traced)" != running ]; then
                printf '开关和通道已更新，服务尚未运行；请刷新状态，不代表服务验证通过。\n'
            else
                printf '已保存并应用 traced 开关，请刷新运行状态。\n'
            fi
        else
            note "ATFWD：下次开机启用=$3；当前服务不重启。"
            printf 'ATFWD 开关已保存，下次开机生效；当前服务未重启。\n'
        fi
        ;;
    *) fail '只支持 status、logs、kernel-logs、diagnostics、boot、apply、set 命令。' ;;
esac
