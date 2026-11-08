"""Test real FFmpeg timestamp wrapping using production attach_track on OHOS."""
from pathlib import Path
import argparse
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--verify-regression', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
sdk = Path('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony')
libs = root / '.local/ijk-native-rebuild/original/package/libs/x86_64'
work = root / 'artifacts/4k-stall-20261107/timestamp'
work.mkdir(parents=True, exist_ok=True)
source = root / 'scripts/tests/dual_timestamp.c'
if a.verify_regression:
    production = (root / 'scripts/ijk_dual_demux_lab.c').read_text(encoding='utf8')
    line = 'out->pts_wrap_bits = track->stream->pts_wrap_bits;'
    assert production.count(line) == 1
    baseline = work / 'without-wrap-bits.c'
    baseline.write_text(production.replace(line, ''), encoding='utf8')
    source = work / 'timestamp-regression.c'
    source.write_text((root / 'scripts/tests/dual_timestamp.c').read_text(encoding='utf8')
        .replace('../ijk_dual_demux_lab.c', baseline.as_posix()), encoding='utf8')
binary = work / ('timestamp-regression' if a.verify_regression else 'timestamp')
subprocess.run([str(sdk/'native/llvm/bin/clang.exe'), '--target=x86_64-linux-ohos',
    '--sysroot='+str(sdk/'native/sysroot'), '-O1', '-ffunction-sections', '-fdata-sections',
    '-DLOG_WARN=1', '-DLOG_ERROR=2', '-I'+str(root/'.local/ijk-dual/ohos-ffmpeg'),
    '-I'+str(root/'.local/ijk-native-rebuild/headers'), '-I'+str(root/'scripts/tests/prefix-stubs'),
    str(source), '-L'+str(libs), '-Wl,--gc-sections', '-Wl,-rpath-link,'+str(libs),
    '-Wl,-rpath,$ORIGIN/libs', '-lavformat', '-lavcodec', '-lavutil', '-o', str(binary)], check=True)
hdc = [str(sdk/'toolchains/hdc.exe'), '-s', '8710', '-t', '127.0.0.1:5555']
def run(*parts):
    return subprocess.check_output(hdc+list(parts), text=True, encoding='utf8', errors='replace', timeout=30)
remote = '/data/local/tmp/pura-timestamp'
run('shell', 'mkdir', '-p', remote+'/libs')
for library in libs.glob('*.so*'):
    # Copy dependencies already shipped with the application, never account data.
    run('file', 'send', str(library), remote+'/libs/'+library.name)
# This standalone demux test never opens a hardware decoder or window. Use
# SDK link stubs for those unavailable application-runtime-only services.
for name in ('libnative_media_vdec.so', 'libnative_media_venc.so', 'libnative_media_codecbase.so',
             'libnative_media_core.so', 'libnative_window.so', 'libdeviceinfo_ndk.z.so'):
    library = sdk / 'native/sysroot/usr/lib/x86_64-linux-ohos' / name
    run('file', 'send', str(library), remote+'/libs/'+name)
run('file', 'send', str(binary), remote+'/timestamp')
result = run('shell', f'chmod 700 {remote}/timestamp; LD_LIBRARY_PATH={remote}/libs {remote}/timestamp')
(work/('regression.log' if a.verify_regression else 'result.log')).write_text(result, encoding='utf8')
print(result)
if a.verify_regression:
    assert 'assert' in result.lower() and 'PASS:' not in result
    print('PASS: omitting only pts_wrap_bits reproduces the 2^33 timestamp jump')
else:
    assert 'PASS: both tracks' in result
