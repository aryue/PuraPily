"""Rebuild both shipped native ABIs and the patched HAR, without the lab app.

Dependencies: Python 3, Git, DevEco SDK, and the pinned source checkouts in README.
Only writes beneath the project (.local build tree, entry/libs).
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quota-probe', action='store_true', help='Diagnostic build: restore the removed 30-second quota')
    parser.add_argument('--probe-start-ms', type=int, default=-1, help='Diagnostic build: pin playback start; -1 uses normal resume')
    parser.add_argument('--probe-queue-mib', type=int, choices=range(1,16), default=15, help='Playback queue cap for controlled diagnostics')
    parser.add_argument('--probe-framedrop', type=int, choices=(0,1), default=1, help='Expired-frame dropping for controlled diagnostics')
    parser.add_argument('--studio', type=Path, default=Path('D:/Program Files/Huawei/DevEco Studio'))
    parser.add_argument('--ijk', type=Path, default=ROOT / '.local/ijk-dual/ohos-ijk')
    parser.add_argument('--ffmpeg', type=Path, default=ROOT / '.local/ijk-dual/ohos-ffmpeg')
    args = parser.parse_args()
    for checkout, revision in ((args.ijk, '4cfc0031d0403a4663942022ce411eedc28eec98'),
                               (args.ffmpeg, '69c05840d1d5412007e50beb94c8508015e51d4f')):
        actual = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != revision:
            raise RuntimeError(f'Unexpected source revision: {checkout}: {actual}')
    native = args.studio / 'sdk/default/openharmony/native'
    cmake = native / 'build-tools/cmake/bin/cmake.exe'
    ninja = native / 'build-tools/cmake/bin/ninja.exe'
    if not ninja.exists():
        ninja = native / 'build-tools/cmake/bin/ninja'
    work = ROOT / '.local/ijk-native-rebuild'
    original = work / 'original'
    stage = work / 'staging'
    original.mkdir(parents=True, exist_ok=True)
    stage.mkdir(parents=True, exist_ok=True)
    har = ROOT / 'entry/libs/ijkplayer-2.0.13.har'
    with tarfile.open(har) as archive:
        # Never permit archive paths to escape the workspace.
        for member in archive.getmembers():
            target = (original / member.name).resolve()
            if not target.is_relative_to(original.resolve()) or member.issym() or member.islnk():
                raise RuntimeError(f'Unsafe HAR entry: {member.name}')
        archive.extractall(original)
    shutil.copytree(original / 'package', stage / 'package', dirs_exist_ok=True)
    # The fork's generated configuration is ABI-independent for our two 64-bit targets.
    headers = work / 'headers'
    (headers / 'libavutil').mkdir(parents=True, exist_ok=True)
    (headers / 'libavutil/avconfig.h').write_text(
        '#define AV_HAVE_BIGENDIAN 0\n#define AV_HAVE_FAST_UNALIGNED 1\n', encoding='utf-8')
    outputs = []
    for abi in ('arm64-v8a', 'x86_64'):
        libs = original / 'package/libs' / abi
        base = work / 'base' / abi
        base.mkdir(parents=True, exist_ok=True)
        data = (libs / 'libijksdl.so').read_bytes()
        name = b'libijksdl.so\0'
        if data.count(name) != 1:
            raise RuntimeError(f'Unexpected SDL SONAME table: {abi}')
        (base / 'libijksdx.so').write_bytes(data.replace(name, b'libijksdx.so\0'))
        build = work / 'build' / abi
        run(cmake, '-S', SOURCE, '-B', build, '-G', 'Ninja',
            f'-DCMAKE_MAKE_PROGRAM={ninja}',
            f'-DCMAKE_TOOLCHAIN_FILE={native / "build/cmake/ohos.toolchain.cmake"}',
            f'-DOHOS_ARCH={abi}', '-DOHOS_STL=c++_shared', '-DOHOS_PLATFORM=OHOS',
            '-DCMAKE_BUILD_TYPE=Release',
            f'-DPURA_PREFIX_QUOTA_PROBE={"ON" if args.quota_probe else "OFF"}',
            f'-DPURA_PROBE_START_MS={args.probe_start_ms}',
            f'-DPURA_PROBE_QUEUE_MIB={args.probe_queue_mib}',
            f'-DPURA_PROBE_FRAMEDROP={args.probe_framedrop}',
            f'-DIJK_SOURCE={args.ijk / "ijkplayer/src/main/cpp"}',
            f'-DFFMPEG_SOURCE={args.ffmpeg}', f'-DORIGINAL_LIBS={libs}', f'-DSDL_BASE={base}',
            f'-DCMAKE_C_FLAGS=-I"{headers}"')
        run(cmake, '--build', build, '--target', 'purapily_ijk', 'ijksdl')
        dest = ROOT / 'entry/libs' / abi
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(build / 'libpurapily_ijk.so', dest)
        patched_libs = stage / 'package/libs' / abi
        shutil.copy2(build / 'libijksdl.so', patched_libs)
        shutil.copy2(base / 'libijksdx.so', patched_libs)
        outputs.extend((dest / 'libpurapily_ijk.so', patched_libs / 'libijksdl.so',
                        patched_libs / 'libijksdx.so'))
    output = ROOT / 'entry/libs/ijkplayer-2.0.13-purapily.har'
    with tarfile.open(output, 'w:gz') as archive:
        archive.add(stage / 'package', arcname='package')
    outputs.append(output)
    manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}
    (work / 'sha256.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Native build complete. Run ohpm install in entry, then assembleHap.')


if __name__ == '__main__':
    main()
