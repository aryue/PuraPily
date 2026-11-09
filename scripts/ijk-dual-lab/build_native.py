"""Rebuild both shipped native ABIs and the patched HAR, without the lab app.

Dependencies: Python 3, Git, DevEco SDK, and the pinned source checkouts in README
(ohos-ijk, ohos-ffmpeg, SoundTouch 2.3.3). Only writes beneath the project
(.local build tree, entry/libs).

The kernel (libijkplayer.so) is rebuilt from the ohos-ijk sources because the
shipped one paces video with a fixed 10 ms tick. Patches under kernel/patches
are applied idempotently before it is compiled.
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
SOUNDTOUCH_URL = ('https://mirrors.aliyun.com/ubuntu/pool/universe/s/soundtouch/'
                  'soundtouch_2.3.3%2Bds.orig.tar.xz')


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], check=True, cwd=cwd)


def apply_kernel_patches(cpp_root):
    """Apply kernel/patches/*.{patch,diff} to the ijkplayer sources; skip applied ones.

    Patch paths are relative to cpp_root (e.g. ijkplayer/ff_ffplay.c), while
    git apply resolves them against the repository root and silently skips any
    path outside the current subdirectory. Invoke it at the repo root with
    --directory pointing at cpp_root, otherwise every patch is a silent no-op.
    """
    repo_root = subprocess.check_output(
        ['git', 'rev-parse', '--show-toplevel'], cwd=cpp_root, text=True).strip()
    prefix = cpp_root.resolve().relative_to(Path(repo_root).resolve()).as_posix()
    patches = sorted((SOURCE / 'kernel/patches').glob('*.patch'))
    patches += sorted((SOURCE / 'kernel/patches').glob('*.diff'))
    for patch in patches:
        applied = subprocess.run(
            ['git', 'apply', '--directory', prefix, '--reverse', '--check',
             '-p1', str(patch)], cwd=repo_root, capture_output=True)
        if applied.returncode == 0:
            print(f'patch already applied: {patch.name}')
            continue
        run('git', 'apply', '--directory', prefix, '-p1', patch, cwd=repo_root)
        print(f'patch applied: {patch.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quota-probe', action='store_true', help='Diagnostic build: restore the removed 30-second quota')
    parser.add_argument('--probe-start-ms', type=int, default=-1, help='Diagnostic build: pin playback start; -1 uses normal resume')
    parser.add_argument('--probe-queue-mib', type=int, choices=range(1,16), default=15, help='Playback queue cap for controlled diagnostics')
    parser.add_argument('--probe-framedrop', type=int, choices=(0,1), default=1, help='Expired-frame dropping for controlled diagnostics')
    parser.add_argument('--studio', type=Path, default=Path('D:/Program Files/Huawei/DevEco Studio'))
    parser.add_argument('--ijk', type=Path, default=ROOT / '.local/ijk-dual/ohos-ijk')
    parser.add_argument('--ffmpeg', type=Path, default=ROOT / '.local/ijk-dual/ohos-ffmpeg')
    parser.add_argument('--soundtouch', type=Path,
                        default=ROOT / '.local/ijk-dual/third_party-src/soundtouch/soundtouch')
    args = parser.parse_args()
    for checkout, revision in ((args.ijk, '4cfc0031d0403a4663942022ce411eedc28eec98'),
                               (args.ffmpeg, '69c05840d1d5412007e50beb94c8508015e51d4f')):
        actual = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != revision:
            raise RuntimeError(f'Unexpected source revision: {checkout}: {actual}')
    if not (args.soundtouch / 'include/SoundTouch.h').exists():
        raise RuntimeError(
            f'SoundTouch 2.3.3 sources missing at {args.soundtouch}\n'
            f'download {SOUNDTOUCH_URL} and extract it there')
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
    cpp_root = args.ijk / 'ijkplayer/src/main/cpp'
    apply_kernel_patches(cpp_root)
    outputs = []
    for abi in ('arm64-v8a', 'x86_64'):
        libs = original / 'package/libs' / abi
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
            f'-DIJK_SOURCE={cpp_root}',
            f'-DFFMPEG_SOURCE={args.ffmpeg}', f'-DORIGINAL_LIBS={libs}', f'-DSDL_BASE={libs}',
            f'-DCMAKE_C_FLAGS=-I"{headers}"')
        run(cmake, '--build', build, '--target', 'purapily_ijk', 'ijksdl')

        # The kernel build links the freshly built ijksdl instead of the shipped copy.
        kernel_build = work / 'build' / f'kernel-{abi}'
        run(cmake, '-S', SOURCE / 'kernel', '-B', kernel_build, '-G', 'Ninja',
            f'-DCMAKE_MAKE_PROGRAM={ninja}',
            f'-DCMAKE_TOOLCHAIN_FILE={native / "build/cmake/ohos.toolchain.cmake"}',
            f'-DOHOS_ARCH={abi}', '-DOHOS_STL=c++_shared', '-DOHOS_PLATFORM=OHOS',
            '-DCMAKE_BUILD_TYPE=Release',
            f'-DIJK_SOURCE={cpp_root}', f'-DFFMPEG_INCLUDE={args.ffmpeg}',
            f'-DSOUNDTOUCH_SOURCE={args.soundtouch}',
            f'-DIJKSDL_LIB={build / "libijksdl.so"}', f'-DPREBUILT_LIBS={libs}')
        run(cmake, '--build', kernel_build, '--target', 'ijkplayer')

        dest = ROOT / 'entry/libs' / abi
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(build / 'libpurapily_ijk.so', dest)
        patched_libs = stage / 'package/libs' / abi
        shutil.copy2(build / 'libijksdl.so', patched_libs)
        shutil.copy2(kernel_build / 'libijkplayer.so', patched_libs)
        outputs.extend((dest / 'libpurapily_ijk.so', patched_libs / 'libijksdl.so',
                        patched_libs / 'libijkplayer.so'))
    output = ROOT / 'entry/libs/ijkplayer-2.0.13-purapily.har'
    with tarfile.open(output, 'w:gz') as archive:
        archive.add(stage / 'package', arcname='package')
    outputs.append(output)
    manifest = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in outputs}
    (work / 'sha256.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Native build complete. Run ohpm install in entry, then assembleHap.')


if __name__ == '__main__':
    main()
