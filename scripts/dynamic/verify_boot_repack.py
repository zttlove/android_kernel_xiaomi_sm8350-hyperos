#!/usr/bin/env python3
import hashlib
import struct
import sys
from pathlib import Path

original, candidate = map(Path, sys.argv[1:3])
old = original.read_bytes()
new = candidate.read_bytes()
page = 4096
kernel_size = struct.unpack_from('<I', new, 8)[0]
ramdisk_size = struct.unpack_from('<I', new, 12)[0]
old_kernel_size = struct.unpack_from('<I', old, 8)[0]
old_ramdisk_size = struct.unpack_from('<I', old, 12)[0]
assert old[:8] == new[:8] == b'ANDROID!'
assert struct.unpack_from('<I', new, 40)[0] == 3
assert old[12:page] == new[12:page], 'header metadata changed beyond kernel size'
assert old_ramdisk_size == ramdisk_size
old_ramdisk_off = page + ((old_kernel_size + page - 1) // page) * page
new_ramdisk_off = page + ((kernel_size + page - 1) // page) * page
old_ramdisk = old[old_ramdisk_off:old_ramdisk_off + ramdisk_size]
new_ramdisk = new[new_ramdisk_off:new_ramdisk_off + ramdisk_size]
assert hashlib.sha256(old_ramdisk).digest() == hashlib.sha256(new_ramdisk).digest()
print(f'old_size={len(old)} new_size={len(new)}')
print(f'kernel_size={kernel_size} old_kernel_size={old_kernel_size} ramdisk_size={ramdisk_size}')
print(f'ramdisk_sha256={hashlib.sha256(new_ramdisk).hexdigest()}')
