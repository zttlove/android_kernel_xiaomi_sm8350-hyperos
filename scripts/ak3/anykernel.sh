### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## LAHAINA (SM8350 5.4, Non-GKI) — venus/star/odin/haydn/mona

### AnyKernel setup
# global properties
properties() { '
kernel.string=Dynamic Kernel For SM8350
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=mars
device.name2=star
device.name3=M2102K1AC
device.name4=M2102K1G
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=0
slot_select=active
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh
AKHOME="${AKHOME:-$(pwd)}"

# LAHAINA devices are boot image v3 (separate vendor_boot), no init_boot
# partition. All supported devices (venus/star/odin/haydn/mona) are SM8350
# MIUI/HyperOS. Single-variant Image in the zip root.
if [ ! -f "$AKHOME/Image" ]; then
    abort "  -> No kernel Image found in this zip! Aborting."
fi

# boot install
# Replace the kernel without extracting/rebuilding the existing ramdisk cpio.
split_boot
flash_boot
## end boot install


## install bundled Phantom userspace/module payload
## platform-phantom-addon-install: begin
AKHOME="${AKHOME:-$(pwd)}"
PHANTOM_ADDON_SOURCE_ZIP="$AKHOME/patch/magisk.zip"
PHANTOM_ADDON_ZIP="$PHANTOM_ADDON_SOURCE_ZIP"
PHANTOM_ADDON_STAGE_DIR="${PHANTOM_ADDON_STAGE_DIR:-}"
PHANTOM_STAGED_ADDON_ZIP=""
PHANTOM_INSTALL_LOG="$AKHOME/patch/.phantom-module-install.log"

phantom_first_number() {
    sed -n 's/[^0-9]*\([0-9][0-9][0-9][0-9]*\).*/\1/p' | head -n 1
}

phantom_print_install_log() {
    [ -s "$PHANTOM_INSTALL_LOG" ] || return 0
    grep -v "^$" "$PHANTOM_INSTALL_LOG" || true
}

phantom_install_succeeded() {
    rc="$1"

    [ "$rc" -eq 0 ] || return 1
    if grep -qiE "Failed to install module|unsupported kernel|No module system found|not a Magisk module|invalid zip|cannot install|error:" "$PHANTOM_INSTALL_LOG" 2>/dev/null; then
        return 1
    fi
    return 0
}

phantom_require_min_vercode() {
    actual="$1"
    minimum="$2"
    label="$3"

    case "$actual" in
        ""|*[!0-9]*)
            ui_print "$label version code unavailable; continuing"
            return 0
            ;;
    esac
    if [ "$actual" -lt "$minimum" ]; then
        ui_print "WARNING: $label version too low for bundled Phantom module"
        return 1
    fi
    return 0
}

phantom_note_install_failure() {
    ui_print "WARNING: bundled Phantom module install failed via $1"
    ui_print "WARNING: kernel flash will continue; install patch/magisk.zip manually if needed"
}

phantom_stage_candidates() {
    [ -n "${PHANTOM_ADDON_STAGE_DIR:-}" ] && printf '%s\n' "$PHANTOM_ADDON_STAGE_DIR"
    if [ -n "${POSTINSTALL:-}" ]; then
        case "$POSTINSTALL" in
            */files)
                printf '%s\n' "${POSTINSTALL%/files}/cache"
                ;;
        esac
        printf '%s\n' "$POSTINSTALL/tmp"
    fi
    case "$AKHOME" in
        */files/tmp/anykernel)
            printf '%s\n' "${AKHOME%/files/tmp/anykernel}/cache"
            ;;
    esac
    printf '%s\n' "/data/local/tmp/phantom-install"
    printf '%s\n' "/data/adb/phantom-install"
}

phantom_try_stage_addon_zip() {
    src="$1"
    stage_dir="$2"
    dst="$stage_dir/phantom-addon-$$.zip"
    owner=""

    [ -n "$stage_dir" ] || return 1
    mkdir -p "$stage_dir" 2>/dev/null || return 1
    chmod 0700 "$stage_dir" 2>/dev/null || true
    rm -f "$dst" 2>/dev/null || true
    cp -f "$src" "$dst" 2>/dev/null || cat "$src" >"$dst" 2>/dev/null || return 1
    owner="$(ls -ld "$stage_dir" 2>/dev/null | awk '{print $3 ":" $4}' | head -n 1)"
    [ -n "$owner" ] && chown "$owner" "$dst" 2>/dev/null || true
    chmod 0644 "$dst" 2>/dev/null || true
    if command -v chcon >/dev/null 2>&1; then
        chcon u:object_r:adb_data_file:s0 "$dst" 2>/dev/null || true
    fi
    [ -s "$dst" ] || return 1
    PHANTOM_STAGED_ADDON_ZIP="$dst"
    PHANTOM_ADDON_ZIP="$dst"
    return 0
}

phantom_stage_addon_zip() {
    src="$1"
    stage_dir=""

    [ -f "$src" ] || return 1
    for stage_dir in $(phantom_stage_candidates); do
        if phantom_try_stage_addon_zip "$src" "$stage_dir"; then
            ui_print "Staged Phantom module: $PHANTOM_ADDON_ZIP"
            return 0
        fi
    done
    return 1
}

phantom_cleanup_staged_addon() {
    [ -n "$PHANTOM_STAGED_ADDON_ZIP" ] || return 0
    rm -f "$PHANTOM_STAGED_ADDON_ZIP" 2>/dev/null || true
}

phantom_candidate_is_exec() {
    [ -n "$1" ] && [ -f "$1" ] && [ -x "$1" ]
}

phantom_find_app_ksud() {
    for pkg in com.resukisu.resukisu me.weishu.kernelsu; do
        apk_path="$(pm path "$pkg" 2>/dev/null | sed -n 's/^package://p' | head -n 1)"
        [ -n "$apk_path" ] || continue
        app_dir="$(dirname "$apk_path" 2>/dev/null || true)"
        for candidate in "$app_dir"/lib/*/libksud.so "$app_dir"/lib/libksud.so; do
            phantom_candidate_is_exec "$candidate" || continue
            printf '%s\n' "$candidate"
            return 0
        done
    done
    for candidate in \
        /data/app/*/com.resukisu.resukisu*/lib/*/libksud.so \
        /data/app/*/*com.resukisu.resukisu*/lib/*/libksud.so \
        /data/app/*/me.weishu.kernelsu*/lib/*/libksud.so \
        /data/app/*/*me.weishu.kernelsu*/lib/*/libksud.so; do
        phantom_candidate_is_exec "$candidate" || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

phantom_find_ksud() {
    if phantom_candidate_is_exec "${PHANTOM_KSUD:-}"; then
        printf '%s\n' "$PHANTOM_KSUD"
        return 0
    fi
    for name in ksud libksud.so; do
        candidate="$(command -v "$name" 2>/dev/null || which "$name" 2>/dev/null || true)"
        phantom_candidate_is_exec "$candidate" || continue
        printf '%s\n' "$candidate"
        return 0
    done
    phantom_find_app_ksud && return 0
    for candidate in /data/adb/ksud /data/adb/ksu/bin/ksud; do
        phantom_candidate_is_exec "$candidate" || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

phantom_install_with_ksu() {
    info="$("$PHANTOM_KSUD_BIN" debug version 2>/dev/null || "$PHANTOM_KSUD_BIN" -V 2>/dev/null || true)"
    ver="$(printf '%s\n' "$info" | phantom_first_number)"
    phantom_require_min_vercode "$ver" 12081 "KernelSU" || return 1
    ui_print "KernelSU: $("$PHANTOM_KSUD_BIN" -V 2>/dev/null || echo unknown)${ver:+($ver)}"
    "$PHANTOM_KSUD_BIN" module install "$PHANTOM_ADDON_ZIP" >"$PHANTOM_INSTALL_LOG" 2>&1
    rc=$?
    phantom_print_install_log
    phantom_install_succeeded "$rc" && return 0
    phantom_note_install_failure "KernelSU"
    return 1
}

phantom_install_with_apatch() {
    info="$(/data/adb/apd -V 2>/dev/null || true)"
    ver="$(printf '%s\n' "$info" | phantom_first_number)"
    phantom_require_min_vercode "$ver" 11039 "APatch" || return 1
    ui_print "APatch: ${info:-unknown}${ver:+($ver)}"
    /data/adb/apd module install "$PHANTOM_ADDON_ZIP" >"$PHANTOM_INSTALL_LOG" 2>&1
    rc=$?
    phantom_print_install_log
    phantom_install_succeeded "$rc" || {
        phantom_note_install_failure "APatch"
        return 1
    }
    ui_print "After flash, you should reinstall APatch manually" && sleep 3
    return 0
}

phantom_install_with_magisk() {
    magisk_bin="$(command -v magisk 2>/dev/null || which magisk 2>/dev/null || true)"
    [ -n "$magisk_bin" ] || return 1
    magisk_ver="$(magisk -v 2>/dev/null || echo unknown)"
    magisk_vercode="$(magisk -V 2>/dev/null || true)"
    phantom_require_min_vercode "$magisk_vercode" 24000 "Magisk" || return 1
    ui_print "Magisk: $magisk_ver${magisk_vercode:+($magisk_vercode)}"
    magisk --install-module "$PHANTOM_ADDON_ZIP" >"$PHANTOM_INSTALL_LOG" 2>&1
    rc=$?
    phantom_print_install_log
    phantom_install_succeeded "$rc" && return 0
    phantom_note_install_failure "Magisk"
    return 1
}

if [ -f "$PHANTOM_ADDON_SOURCE_ZIP" ]; then
    ui_print "Installing Phantom userspace and kernel modules"
    rm -f "$PHANTOM_INSTALL_LOG" 2>/dev/null || true
    if ! phantom_stage_addon_zip "$PHANTOM_ADDON_SOURCE_ZIP"; then
        PHANTOM_ADDON_ZIP="$PHANTOM_ADDON_SOURCE_ZIP"
        ui_print "WARNING: unable to stage Phantom module under $PHANTOM_ADDON_STAGE_DIR"
    fi
    PHANTOM_KSUD_BIN="$(phantom_find_ksud 2>/dev/null || true)"
    if [ -n "$PHANTOM_KSUD_BIN" ]; then
        ui_print "KernelSU daemon: $PHANTOM_KSUD_BIN"
        phantom_install_with_ksu || true
    elif [ -x "/data/adb/apd" ] || [ -f "/data/adb/apd" ]; then
        phantom_install_with_apatch || true
    elif command -v magisk >/dev/null 2>&1 || which magisk >/dev/null 2>&1; then
        phantom_install_with_magisk || true
    else
        ui_print "WARNING: no supported module manager found for bundled Phantom module"
        ui_print "WARNING: kernel flash will continue; install patch/magisk.zip manually if needed"
    fi
    phantom_cleanup_staged_addon
else
    ui_print "No bundled Phantom module payload"
fi
## platform-phantom-addon-install: end
