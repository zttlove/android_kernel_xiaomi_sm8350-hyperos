#!/usr/bin/env python3
"""Execute Lahaina's actual C conversions against its advertised ALSA contract."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path,
                    default=Path(__file__).resolve().parents[2] / 'techpack/audio/asoc/lahaina.c')
args = parser.parse_args()
source = args.source.read_text()
enum = re.search(r'tdm_sample_rate_text\[\]\s*=\s*\{(.*?)\};', source, re.S)
assert enum is not None
labels = re.findall(r'"([^"]+)"', enum[1])
expected_labels = ['KHZ_8', 'KHZ_16', 'KHZ_32', 'KHZ_48', 'KHZ_96', 'KHZ_176P4', 'KHZ_352P8']
assert labels == expected_labels, 'Review the public mixer ABI before changing this contract'
start = source.index('static int tdm_get_sample_rate(int value)')
end = source.index('static int tdm_rx_sample_rate_get(', start)
functions = source[start:end]
rates = {'8': 8000, '11P025': 11025, '16': 16000, '22P05': 22050,
         '32': 32000, '44P1': 44100, '48': 48000, '88P2': 88200,
         '96': 96000, '176P4': 176400, '192': 192000,
         '352P8': 352800, '384': 384000}
header = '#include <stdio.h>\n' + ''.join(
    f'#define SAMPLING_RATE_{name}KHZ {rate}\n' for name, rate in rates.items())
main = r'''
int main(void)
{
    const int expected[] = {8000, 16000, 32000, 48000, 96000, 176400, 352800};
    int failed = 0;
    for (int i = 0; i < 7; ++i) {
        int actual = tdm_get_sample_rate(i);
        int reverse = tdm_get_sample_rate_val(expected[i]);
        int ok = actual == expected[i] && reverse == i;
        printf("%s: index=%d expected=%d actual=%d reverse=%d\n",
               ok ? "PASS" : "FAIL", i, expected[i], actual, reverse);
        failed += !ok;
    }
    if (tdm_get_sample_rate(-1) != 48000 ||
        tdm_get_sample_rate(7) != 48000 ||
        tdm_get_sample_rate_val(12345) != 3) {
        puts("FAIL: unsupported-value fallback must select the advertised 48 kHz item");
        failed++;
    }
    return failed ? 1 : 0;
}
'''
with tempfile.TemporaryDirectory(prefix='dynamic-tdm-contract-') as tmp:
    folder = Path(tmp)
    cfile, exe = folder / 'contract.c', folder / 'contract'
    cfile.write_text(header + functions + main)
    subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror', str(cfile), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
