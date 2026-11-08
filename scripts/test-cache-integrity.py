"""Run the production C cache with injected corruption on an OHOS target."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', default='127.0.0.1:5555')
parser.add_argument('--abi', choices=['x86_64', 'arm64-v8a'], default='x86_64')
parser.add_argument('--verify-regression', action='store_true', help='Prove the range-origin test fails with only the origin fix removed')
parser.add_argument('--verify-recovery', action='store_true', help='Prove fault injection fails if connection recovery is disabled')
args = parser.parse_args()
sdk = Path('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony')
work = root / 'artifacts/cache-integrity-20261107' / args.abi
work.mkdir(parents=True, exist_ok=True)
libs = root / '.local/ijk-native-rebuild/original/package/libs' / args.abi
target = 'x86_64-linux-ohos' if args.abi == 'x86_64' else 'aarch64-linux-ohos'
binary = work / 'cache_integrity'
extra = []
if args.verify_regression:
    original = (root/'scripts/ijk-dual-lab/cache.c').read_text(encoding='utf-8')
    assert original.count('if (pb) pb->pos = offset;') == 1
    baseline = work/'without-range-origin.c'
    baseline.write_text(original.replace('if (pb) pb->pos = offset;', ''),encoding='utf-8')
    extra = ['-DCACHE_UNDER_TEST="'+baseline.as_posix()+'"']
    binary = work/'cache_regression'
if args.verify_recovery:
    assert not args.verify_regression
    original = (root/'scripts/ijk-dual-lab/cache.c').read_text(encoding='utf-8')
    assert original.count('if (attempt >= 2)') == 1
    baseline = work/'without-read-recovery.c'
    baseline.write_text(original.replace('if (attempt >= 2)', 'if (attempt >= 0)'), encoding='utf8')
    extra = ['-DCACHE_UNDER_TEST="'+baseline.as_posix()+'"']
    binary = work/'cache_recovery_regression'
subprocess.run([str(sdk/'native/llvm/bin/clang.exe'), '--target='+target,
    '--sysroot='+str(sdk/'native/sysroot'), '-O1', '-g', '-DLOG_WARN=1',
    '-I'+str(root/'.local/ijk-dual/ohos-ffmpeg'),
    '-I'+str(root/'.local/ijk-native-rebuild/headers'),
    '-I'+str(root/'scripts/tests/prefix-stubs'),
    str(root/'scripts/tests/cache_integrity.c'), '-L'+str(libs),
    '-Wl,-rpath-link,'+str(libs), '-Wl,-rpath,$ORIGIN/libs',
    '-lavutil', '-o', str(binary), *extra], check=True)
remote = '/data/local/tmp/pura-cache-integrity'
hdc = [str(sdk/'toolchains/hdc.exe'), '-s', '8710', '-t', args.device]
def run(*parts):
    return subprocess.check_output(hdc+list(parts), text=True, encoding='utf-8', errors='replace', timeout=60)
print(run('shell', f'mkdir -p {remote}/libs'), end='')
for name in ('libavutil.so',):
    run('file', 'send', str(libs/name), remote+'/libs/'+name)
run('file','send',str(binary),remote+'/cache_integrity')
result = run('shell', f'chmod 700 {remote}/cache_integrity; mkdir -p {remote}/case-$(date +%s%N); '
    f'testdir=$(ls -dt {remote}/case-* | head -n 1); {remote}/cache_integrity "$testdir"')
(work/('recovery-regression.log' if args.verify_recovery else 'regression.log' if args.verify_regression else 'result.log')).write_text(result,encoding='utf-8')
print(result)
if args.verify_regression or args.verify_recovery:
    if 'assert' not in result.lower() or 'ALL CACHE INTEGRITY TESTS PASSED' in result:
        raise RuntimeError('Removing the fix did not reproduce the regression')
    print('PASS: disabling connection recovery reproduces the read failure' if args.verify_recovery else
          'PASS: removing only Range origin normalization reproduces incorrect media bytes')
    raise SystemExit(0)
if 'ALL CACHE INTEGRITY TESTS PASSED' not in result:
    raise RuntimeError('Native cache fault-injection failed')
