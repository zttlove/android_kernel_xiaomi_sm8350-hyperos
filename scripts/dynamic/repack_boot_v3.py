#!/usr/bin/env python3
"""Replace the kernel payload in an Android boot image header v3."""

import argparse
import pathlib
import struct

PAGE = 4096
HEADER = struct.Struct("<8sIIII4II1536s")


def align(value):
    return (value + PAGE - 1) // PAGE * PAGE


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stock")
    parser.add_argument("kernel")
    parser.add_argument("output")
    args = parser.parse_args()

    stock = pathlib.Path(args.stock).read_bytes()
    new_kernel = pathlib.Path(args.kernel).read_bytes()
    fields = list(HEADER.unpack_from(stock))
    if fields[0] != b"ANDROID!":
        raise SystemExit("invalid Android boot magic")
    if fields[9] != 3:
        raise SystemExit(f"expected header version 3, got {fields[9]}")

    old_kernel_size = fields[1]
    ramdisk_size = fields[2]
    ramdisk_offset = PAGE + align(old_kernel_size)
    ramdisk = stock[ramdisk_offset:ramdisk_offset + ramdisk_size]
    if len(ramdisk) != ramdisk_size:
        raise SystemExit("stock ramdisk is truncated")

    fields[1] = len(new_kernel)
    header = HEADER.pack(*fields)
    image = bytearray(PAGE)
    image[:len(header)] = header
    image.extend(new_kernel)
    image.extend(b"\0" * (align(len(new_kernel)) - len(new_kernel)))
    image.extend(ramdisk)
    image.extend(b"\0" * (align(ramdisk_size) - ramdisk_size))
    pathlib.Path(args.output).write_bytes(image)
    print(f"kernel={len(new_kernel)} ramdisk={ramdisk_size} image={len(image)}")


if __name__ == "__main__":
    main()
