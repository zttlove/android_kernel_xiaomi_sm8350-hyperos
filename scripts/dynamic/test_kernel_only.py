#!/usr/bin/env python3
"""Audit template fidelity and execute the actual model admission function."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

src = Path(__file__).resolve().parents[2]
folder = src / 'scripts/ak3'
template = Path(os.environ.get('AK3_TEMPLATE', '/mnt/c/Users/Leeze/Downloads/HoshinoNeko_Star_Stable2_Any3Kernel.zip'))
assert hashlib.sha256(template.read_bytes()).hexdigest() == '590627e556f15e49f243ab692bc07246242901aed21eacfb3cf8938b151263db'
with zipfile.ZipFile(template) as z:
    assert z.testzip() is None
    expected = z.read('anykernel.sh')
    replacements = {
        b'kernel.string=MiYume HoshinoNeko Kernel For SM8350': b'kernel.string=Dynamic Kernel For SM8350',
        b'do.devicecheck=0': b'do.devicecheck=1',
        b'device.name1=star': b'device.name1=mars',
        b'device.name2=\n': b'device.name2=star\n',
        b'device.name3=\n': b'device.name3=M2102K1AC\n',
        b'device.name4=\n': b'device.name4=M2102K1G\n',
        b'patch_vbmeta_flag=auto': b'patch_vbmeta_flag=0\nslot_select=active',
        b'dump_boot\nwrite_boot': b'# Replace the kernel without extracting/rebuilding the existing ramdisk cpio.\nsplit_boot\nflash_boot',
    }
    for before, after in replacements.items():
        assert expected.count(before) == 1, before
        expected = expected.replace(before, after)
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    assert actual == set(z.namelist()) - {'Image'}
    for name in actual:
        assert (folder/name).read_bytes() == (expected if name == 'anykernel.sh' else z.read(name)), name
print('PASS: exact approved template contents; only documented anykernel.sh edits')
for name in ['anykernel.sh', 'tools/ak3-core.sh', 'META-INF/com/google/android/update-binary']:
    subprocess.run(['bash', '-n', str(folder/name)], check=True)

entry = (folder/'META-INF/com/google/android/update-binary').read_text()
function = entry[entry.index('do_devicecheck() {'):entry.index('int2ver() {')]
with tempfile.TemporaryDirectory(prefix='ak3-admission-') as temp:
    test = Path(temp)/'check.sh'
    test.write_text('''#!/bin/bash
cd "$1"
file_getprop() { grep "^$2=" "$1" | tail -n1 | cut -d= -f2-; }
ui_print() { printf '%s\\n' "$*"; }
abort() { ui_print "$@"; exit 1; }
getprop() {
  case "$1" in
    ro.product.device|ro.build.product|ro.product.vendor.device|ro.vendor.product.device)
      [ "$1" = "$TEST_PROPERTY" ] && printf '%s\\n' "$TEST_DEVICE";;
    *) echo "Unexpected admission property: $1" >&2; exit 99;;
  esac
}
''' + function + '\ndo_devicecheck\n')
    devices = ['mars','star','M2102K1AC','M2102K1G','venus','alioth','mars-extra','']
    for prop in ['ro.product.device','ro.build.product','ro.product.vendor.device','ro.vendor.product.device']:
        for device in devices:
            env = dict(os.environ, TEST_PROPERTY=prop, TEST_DEVICE=device)
            result = subprocess.run(['bash', str(test), str(folder)], env=env, capture_output=True, text=True)
            assert (result.returncode == 0) == (device in devices[:4]), (prop,device,result.stdout,result.stderr)
            assert not result.stderr, result.stderr
print('PASS: 32 model admission cases; only four device properties queried')
print('PASS: shell syntax; no device partitions accessed')
