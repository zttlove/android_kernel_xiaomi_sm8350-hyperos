#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Build the tested Xiaomi 11 Pro HyperOS 4 / Android 17 configuration.
set -euo pipefail
src=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$src"
out=${OUT:-"$src/../out-dynamic-mars-a17"}
mkdir -p "$out"
out=$(cd "$out" && pwd)
if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
    echo 'Commit the release sources before building a named release.' >&2
    exit 1
fi
commit=$(git rev-parse HEAD)
export SOURCE_COMMIT=$commit
export KBUILD_BUILD_USER=Dynamic
export KBUILD_BUILD_HOST=mars
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP=$(git show -s --format=%cD HEAD)
export SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)
args=(O="$out" ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang-17 LD=ld.lld-17
      AR=llvm-ar-17 NM=llvm-nm-17 OBJCOPY=llvm-objcopy-17
      OBJDUMP=llvm-objdump-17 STRIP=llvm-strip-17
      CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=)
make "${args[@]}" vendor/mars_hyperos4_a17_defconfig
bash scripts/set-dynamic-version.sh "$out/.config"
make "${args[@]}" olddefconfig
grep -qx 'CONFIG_BPF_STREAM_PARSER=y' "$out/.config"
grep -qx 'CONFIG_FW_LOADER_USER_HELPER=y' "$out/.config"
grep -qx '# CONFIG_FW_LOADER_USER_HELPER_FALLBACK is not set' "$out/.config"
make "${args[@]}" -j"${JOBS:-10}" Image
expected="5.4.302-Dynamic-g${commit:0:7}"
test "$(cat "$out/include/config/kernel.release")" = "$expected"
{
    printf 'source_commit=%s\nkernel_release=%s\n' "$commit" "$expected"
    printf 'build_timestamp=%s\n' "$KBUILD_BUILD_TIMESTAMP"
    clang-17 --version | head -1
    ld.lld-17 --version
    sha256sum "$out/.config" "$out/arch/arm64/boot/Image"
} | tee "$out/dynamic-build-manifest.txt"
