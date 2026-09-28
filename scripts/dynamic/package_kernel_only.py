#!/usr/bin/env python3
"""Build the Dynamic AK3 package from the approved HoshinoNeko template."""
import datetime
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from zoneinfo import ZoneInfo

src = Path(__file__).resolve().parents[2]
template = Path(os.environ.get("AK3_TEMPLATE", "/mnt/c/Users/Leeze/Downloads/HoshinoNeko_Star_Stable2_Any3Kernel.zip"))
expected_template_sha256 = "590627e556f15e49f243ab692bc07246242901aed21eacfb3cf8938b151263db"

def git(*args):
    return subprocess.check_output(["git", "-C", str(src), *args], text=True).strip()

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

if git("status", "--porcelain", "--untracked-files=normal"):
    raise SystemExit("Commit release sources before packaging")
if not template.is_file():
    raise SystemExit(f"AK3 template not found: {template}")
if sha(template) != expected_template_sha256:
    raise SystemExit("AK3 template SHA-256 does not match the approved template")
subprocess.run(['python3', str(src/'scripts/dynamic/test_kernel_only.py')], check=True,
               env=dict(os.environ, AK3_TEMPLATE=str(template)))

commit = git("rev-parse", "HEAD")
epoch = int(git("show", "-s", "--format=%ct", "HEAD"))
when = datetime.datetime.fromtimestamp(epoch, ZoneInfo("Asia/Shanghai"))
stamp = when.strftime("%Y%m%d-%H%M")
release = "5.4.302-Dynamic-g" + commit[:7]
out = Path(os.environ.get("OUT", str(src.parent / "out-dynamic-mars-a17")))
dest = Path(os.environ.get("RELEASE_DIR", str(src.parent / ("release-" + commit[:7]))))
dest.mkdir(parents=True, exist_ok=True)
if (out / "include/config/kernel.release").read_text().strip() != release:
    raise SystemExit("kernel.release does not match source commit")
build_manifest = (out / "dynamic-build-manifest.txt").read_text()
if "source_commit=" + commit not in build_manifest:
    raise SystemExit("build output was not produced from HEAD")
image_data = (out / "arch/arm64/boot/Image").read_bytes()
if sha(out / "arch/arm64/boot/Image") not in build_manifest:
    raise SystemExit("Image hash is missing from build manifest")
if (b"Linux version " + release.encode() + b" ") not in image_data:
    raise SystemExit("Image does not contain the required uname release")

base = release + "-" + stamp
image = dest / ("Image-" + base)
config = dest / ("config-" + base)
ak3 = dest / ("Dynamic-AK3-" + base + ".zip")
report_path = Path(os.environ['AK3_VALIDATION_REPORT'])
report = json.loads(report_path.read_text())
if report['source_commit'] != commit or report['results'][0]['kernel_sha256'] != sha(out/'arch/arm64/boot/Image'):
    raise SystemExit('Offline verification does not match the build')
for key, name in [('ak3_core_sha256', 'tools/ak3-core.sh'), ('anykernel_sha256', 'anykernel.sh')]:
    if report[key] != sha(src/'scripts/ak3'/name):
        raise SystemExit(f'Offline verification does not match {name}')
validation = dest / ('AK3Validation-' + base + '.json')
shutil.copyfile(report_path, validation)
shutil.copyfile(out / "arch/arm64/boot/Image", image)
shutil.copyfile(out / ".config", config)

with zipfile.ZipFile(template) as template_zip:
    template_names = template_zip.namelist()
    template_comment = template_zip.comment
    template_infos = {info.filename: info for info in template_zip.infolist()}
    template_data = {name: template_zip.read(name) for name in template_names if name != 'Image'}
    if template_names.count("Image") != 1:
        raise SystemExit("approved template must contain exactly one root Image")
    expected_names = set(template_names) - {"Image"}

source_files = {p.relative_to(src / "scripts/ak3").as_posix(): p for p in (src / "scripts/ak3").rglob("*") if p.is_file()}
if set(source_files) != expected_names:
    missing = sorted(expected_names - set(source_files))
    extra = sorted(set(source_files) - expected_names)
    raise SystemExit(f"AK3 template entries differ; missing={missing}, extra={extra}")

ak_text = (src / "scripts/ak3/anykernel.sh").read_text()
required = ("kernel.string=Dynamic Kernel For SM8350", "do.devicecheck=1", "device.name1=mars", "device.name2=star", "device.name3=M2102K1AC", "device.name4=M2102K1G", "split_boot", "flash_boot", "patch_vbmeta_flag=0", "slot_select=active")
if any(item not in ak_text for item in required):
    raise SystemExit("anykernel.sh is missing the model-only/template install flow")
if any(x in ak_text for x in ("bootloader", "getprop ro.boot.verifiedbootstate", "seek=1")):
    raise SystemExit("anykernel.sh contains an unsupported admission or fixed-offset gate")
for name, path in source_files.items():
    if name != 'anykernel.sh' and path.read_bytes() != template_data[name]:
        raise SystemExit(f'Unapproved template entry change: {name}')

with zipfile.ZipFile(ak3, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.comment = template_comment
    for name in template_names:
        info = copy.copy(template_infos[name])
        data = image_data if name == 'Image' else source_files[name].read_bytes()
        z.writestr(info, data)

with zipfile.ZipFile(ak3) as z:
    if z.testzip() is not None:
        raise SystemExit("AK3 ZIP integrity check failed")
    if z.namelist() != template_names or z.comment != template_comment:
        raise SystemExit("AK3 output entry order/comment differs from approved template")
    for info in z.infolist():
        original = template_infos[info.filename]
        for field in ('date_time', 'compress_type', 'create_system', 'create_version',
                      'extract_version', 'internal_attr', 'external_attr', 'comment', 'extra'):
            if getattr(info, field) != getattr(original, field):
                raise SystemExit(f'AK3 template metadata differs: {info.filename}: {field}')
    if z.read("Image") != image_data:
        raise SystemExit("AK3 Image does not match compiled Image")
    if z.read("anykernel.sh").count(b"MiYume HoshinoNeko Kernel For SM8350"):
        raise SystemExit("old kernel title remains in AK3")
    if z.read("anykernel.sh").count(b"Dynamic Kernel For SM8350") != 1:
        raise SystemExit("new kernel title count is not exactly one")

manifest = {
    "author": "Dynamic", "source_commit": commit, "branch": git("branch", "--show-current"), "kernel_release": release,
    "source_commit_time": when.isoformat(), "artifact_timestamp": stamp, "artifact_timezone": "Asia/Shanghai",
    "build_timestamp": git("show", "-s", "--format=%cD", "HEAD"), "build_user": "Dynamic", "build_host": "mars",
    "build_completed_at": datetime.datetime.fromtimestamp((out/'arch/arm64/boot/Image').stat().st_mtime, ZoneInfo('Asia/Shanghai')).isoformat(),
    "compiler": subprocess.check_output(["clang-17", "--version"], text=True).splitlines()[0],
    "linker": subprocess.check_output(["ld.lld-17", "--version"], text=True).strip(),
    "config": "vendor/mars_hyperos4_a17_defconfig + scripts/set-dynamic-version.sh", "kernel_payload_bytes": len(image_data),
    "installer": "HoshinoNeko AnyKernel3 template; model admission only; split_boot/flash_boot preserves existing ramdisk cpio without rebuilding its filesystem; active slot; vbmeta flag patching disabled; no recovery/bootloader/Android-version/equal-kernel-size policy gate",
    "allowed_devices": ["mars", "star", "M2102K1AC", "M2102K1G"], "template": str(template), "template_sha256": expected_template_sha256,
    "files": {p.name: sha(p) for p in (image, config, ak3, validation)},
}
manifest_file = dest / ("dynamic-build-manifest-" + stamp + ".json")
manifest_file.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
notes = (src / "Documentation/dynamic-a17-fixes-zh.md").read_text()
notes += "\n## 本次构建与 AK3 安装器校验\n\n"
notes += f"- 源码提交：`{commit}`\n- 分支：`{manifest['branch']}`\n- uname：`{release}`\n- 源码提交/构建时间戳：`{when.isoformat()}`\n"
notes += f"- 工具链：{manifest['compiler']}；{manifest['linker']}\n- 配置：`{manifest['config']}`\n- 内核载荷长度：{len(image_data)} 字节\n"
notes += "- AK3 来源：已批准的 HoshinoNeko_Star_Stable2_Any3Kernel.zip；运行时使用其 `split_boot`/`flash_boot`，保留原 ramdisk cpio 的文件与元数据，跳过 ramdisk 文件解包/重建，只替换 kernel payload 并重新封装 boot。\n"
notes += "- 唯一准入检查：`mars`/`star`/`M2102K1AC`/`M2102K1G`；不增加 Recovery、Bootloader、系统版本或其他环境拦截。\n\n"
notes += f"- 实际 Image 构建完成时间：`{manifest['build_completed_at']}`；内核内嵌时间及附件名称取提交时间。\n"
notes += '- 离线验证：32 组机型准入；.26 原 boot 配合当前 Image 与 ±8 KiB 大小布局样本，ramdisk cpio 字节、893 个文件条目及启动参数保持一致。测试写入只发生于本机临时文件，没有刷写手机；详见 AK3Validation 附件。\n\n'
notes += "| 文件 | SHA-256 |\n| --- | --- |\n"
for p in (image, ak3, config, validation, manifest_file):
    notes += f"| `{p.name}` | `{sha(p)}` |\n"
notes_file = dest / ("ReleaseNotes-" + base + ".md")
notes_file.write_text(notes)
sums = dest / ("SHA256SUMS-" + stamp + ".txt")
sums.write_text("".join(sha(p) + "  " + p.name + "\n" for p in (image, ak3, config, validation, manifest_file, notes_file)))
print(json.dumps({"release_dir": str(dest), "tag": "dynamic-kernel-g" + commit[:7], "source_commit": commit, "kernel_release": release, "stamp": stamp, "files": [p.name for p in (image, ak3, config, validation, manifest_file, notes_file, sums)]}, indent=2))
