#!/usr/bin/env python3
"""Exercise unchanged AK3 core on disposable files, never device partitions."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zipfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--qemu', required=True, type=Path)
parser.add_argument('--boot', required=True, type=Path)
parser.add_argument('--image', required=True, type=Path)
parser.add_argument('--report', required=True, type=Path)
args = parser.parse_args()
SRC, QEMU, ROM, IMAGE, EVIDENCE = (p.resolve() for p in (args.source, args.qemu, args.boot, args.image, args.report))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def entries(data):
    """Compare cpio file data, permissions, ownership, timestamps and links."""
    result = {}
    off = 0
    while off < len(data):
        assert data[off:off+6] in (b'070701', b'070702'), off
        f = [int(data[off+6+i*8:off+14+i*8], 16) for i in range(13)]
        name = data[off+110:off+110+f[11]-1].decode()
        start = (off+110+f[11]+3) & ~3
        payload = data[start:start+f[6]]
        off = (start+f[6]+3) & ~3
        if name == 'TRAILER!!!':
            break
        if name in ('.', './'):
            continue
        name = name.removeprefix('./')
        result[name] = {'mode': f[1], 'uid': f[2], 'gid': f[3],
                        'nlink': f[4], 'mtime': f[5], 'rdevmajor': f[9],
                        'rdevminor': f[10], 'data': digest(payload)}
    return result

with tempfile.TemporaryDirectory(prefix='dynamic-ak3-offline-') as temp:
    root = Path(temp)
    binpath = root / 'bin'
    binpath.mkdir()
    magisk = SRC / 'scripts/ak3/tools/magiskboot'
    wrapper = binpath / 'magiskboot'
    wrapper.write_text(f'#!/bin/sh\nif [ "${{AK3_TEST_FAIL_REPACK:-0}}" = 1 ] && [ "$1" = repack ]; then exit 86; fi\nexec {QEMU} {magisk} "$@"\n')
    wrapper.chmod(0o755)
    env = dict(os.environ, PATH=str(binpath) + ':' + os.environ['PATH'])
    core = (SRC / 'scripts/ak3/tools/ak3-core.sh').read_text()
    assert core.rstrip().endswith('setup_ak;')
    core_file = root / 'core.sh'
    core_file.write_text(core.rsplit('setup_ak;', 1)[0])
    original = ROM.read_bytes()
    assert original[:8] == b'ANDROID!'
    assert struct.unpack_from('<I', original, 40)[0] == 3
    original_hash = digest(original)
    original_dir = root / 'original'
    original_dir.mkdir()
    subprocess.run(['magiskboot', 'unpack', '-h', str(ROM)], cwd=original_dir, env=env, check=True, capture_output=True)
    before_cpio = entries((original_dir / 'ramdisk.cpio').read_bytes())
    base_image = IMAGE.read_bytes()
    results = []
    # Current payload plus a larger payload crosses a page boundary; the latter
    # is an offline layout fixture, not a bootable artifact for distribution.
    for label, image in [('compiled-image', base_image), ('larger-layout-fixture', base_image + b'\0'*8192), ('smaller-layout-fixture', base_image[:-8192])]:
        ak = root / label
        ak.mkdir()
        (ak / 'Image').write_bytes(image)
        (ak / 'tools').mkdir()
        block = ak / 'mock-boot-partition'
        block.write_bytes(original)
        run = ak / 'run.sh'
        run.write_text('''#!/bin/bash
set -o pipefail
AKHOME="$1"
BLOCK="$AKHOME/mock-boot-partition"
BOOTIMG="$AKHOME/boot.img"
BIN="$AKHOME/tools"
SPLITIMG="$AKHOME/split_img"
RAMDISK="$AKHOME/ramdisk"
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=0
NO_MAGISK_CHECK=1
OUTFD=1
. "$2"
# The unchanged template writes to a block device. This test confines writes
# to its disposable regular-file substitute and bounds its zero-fill operation.
dd() {
  local arg input= output=
  for arg in "$@"; do
    case "$arg" in if=*) input="${arg#if=}";; of=*) output="${arg#of=}";; esac
  done
  case "$input" in "$BLOCK"|boot-new.img|/dev/zero) ;; *) echo "unexpected input $input" >&2; return 90;; esac
  case "$output" in "$BLOCK"|"$BOOTIMG") ;; *) echo "unexpected output $output" >&2; return 91;; esac
  if [ "$input" = /dev/zero ]; then
    command dd if=/dev/zero of="$BLOCK" bs=1048576 count="$(stat -c %s "$BLOCK")" iflag=count_bytes conv=notrunc status=none
  else
    command dd "$@" conv=notrunc status=none
  fi
}
blockdev() { [ "$1" = --setrw ] && [ "$2" = "$BLOCK" ]; }
cd "$AKHOME"
split_boot
flash_boot
''')
        proc = subprocess.run(['bash', str(run), str(ak), str(core_file)], env=env, capture_output=True, text=True)
        if proc.returncode:
            raise RuntimeError(proc.stdout + proc.stderr)
        verify = ak / 'verify'
        verify.mkdir()
        unpack = subprocess.run(['magiskboot', 'unpack', '-h', str(block)], cwd=verify, env=env, capture_output=True, text=True)
        assert unpack.returncode == 0, unpack.stderr
        assert (verify / 'kernel').read_bytes() == image, label
        after_cpio = entries((verify / 'ramdisk.cpio').read_bytes())
        assert before_cpio == after_cpio, [k for k in before_cpio if before_cpio[k] != after_cpio.get(k)][:10]
        assert (original_dir / 'ramdisk.cpio').read_bytes() == (verify / 'ramdisk.cpio').read_bytes(), 'cpio byte stream changed'
        new = block.read_bytes()
        # Only kernel_size and ramdisk_size in the header may change on repack.
        assert original[:8] == new[:8] and original[16:1580] == new[16:1580], label
        assert (original_dir / 'header').read_bytes() == (verify / 'header').read_bytes(), label
        results.append({'case': label, 'kernel_bytes': len(image), 'kernel_sha256': digest(image),
                        'ramdisk_entries': len(before_cpio), 'ramdisk_files_metadata_equal': True,
                        'ramdisk_cpio_bytes_equal': True,
                        'header_parameters_equal': True, 'output_boot_sha256': digest(new)})
        print('PASS', label, len(image), 'ramdisk entries', len(before_cpio))
    failure_results = []
    for label, invalid_boot, fail_repack in [('invalid-boot', True, False), ('repack-failure', False, True)]:
        failed_dir = root / label
        failed_dir.mkdir()
        (failed_dir / 'tools').mkdir()
        (failed_dir / 'Image').write_bytes(base_image)
        failed_block = failed_dir / 'mock-boot-partition'
        failed_input = b'INVALID!' + b'\0' * 4088 if invalid_boot else original
        failed_block.write_bytes(failed_input)
        failed_run = failed_dir / 'run.sh'
        failed_run.write_text(run.read_text())
        fault_env = dict(env, AK3_TEST_FAIL_REPACK='1' if fail_repack else '0')
        proc = subprocess.run(['bash', str(failed_run), str(failed_dir), str(core_file)],
                              env=fault_env, capture_output=True, text=True, timeout=90)
        assert proc.returncode != 0, label
        assert failed_block.read_bytes() == failed_input, label + ': target was modified'
        assert not (failed_dir / 'boot-new.img').exists(), label + ': partial output remained'
        failure_results.append({'case': label, 'rejected': True, 'mock_target_unchanged': True,
                                'no_partial_repacked_image': True})
        print('PASS', label, 'aborted before writing; no partial repacked image')
    assert digest(ROM.read_bytes()) == original_hash
    EVIDENCE.write_text(json.dumps({'rom': str(ROM), 'rom_sha256': original_hash,
                                   'source_commit': subprocess.check_output(['git', '-C', str(SRC), 'rev-parse', 'HEAD'], text=True).strip(),
                                   'original_kernel_bytes_unpacked': (original_dir/'kernel').stat().st_size,
                                   'ak3_core_sha256': digest((SRC/'scripts/ak3/tools/ak3-core.sh').read_bytes()),
                                   'anykernel_sha256': digest((SRC/'scripts/ak3/anykernel.sh').read_bytes()),
                                   'method': 'unchanged AK3 core split_boot/flash_boot; bundled ARM magiskboot through QEMU; block writes mocked to disposable files',
                                   'physical_device_access': False, 'input_boot_unchanged': True,
                                   'failure_results': failure_results, 'results': results}, indent=2)+'\n')
    print('Evidence:', EVIDENCE)
