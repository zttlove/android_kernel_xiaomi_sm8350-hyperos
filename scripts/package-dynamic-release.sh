#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail
src=$(cd -- "$(dirname -- "$0")/.." && pwd)
exec python3 "$src/scripts/dynamic/package_kernel_only.py"
