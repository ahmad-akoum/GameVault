"""Package only Windows runtime files; never include portable personal data."""
import hashlib
import argparse
import os
import re
import subprocess
import pathlib
import zipfile

parser = argparse.ArgumentParser(description='Package a Windows portable runtime.')
parser.add_argument('version')
parser.add_argument('--build-dir', default=os.environ.get('GAMEVAULT_BUILD_DIR', 'build'))
parser.add_argument('--output-dir')
args = parser.parse_args()
version = args.version
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected semantic release version')
root = pathlib.Path(__file__).resolve().parents[1]
build_root = pathlib.Path(args.build_dir)
if not build_root.is_absolute():
    build_root = root / build_root
release = build_root / 'windows/x64/runner/Release'
out = pathlib.Path(args.output_dir) if args.output_dir else root / 'release_artifacts/ready' / ('v' + version)
if not out.is_absolute():
    out = root / out
out.mkdir(parents=True, exist_ok=True)
exe_path = release / 'gamevault.exe'
actual = subprocess.check_output(['powershell', '-NoProfile', '-Command', f"(Get-Item -LiteralPath '{exe_path.as_posix()}').VersionInfo.ProductVersion"], cwd=root, text=True).strip()
if actual.split('+')[0] != version:
    raise SystemExit('Executable version differs from requested release')
archive = out / f'GameVault-v{version}-windows-x64.zip'
if archive.exists():
    raise SystemExit('Refusing to overwrite an existing release archive')
files = [release / 'gamevault.exe', release / 'flutter_windows.dll', release / 'data/icudtl.dat', release / 'data/app.so']
assert all(p.is_file() for p in files), 'Incomplete runtime'
files = sorted(set([release / 'gamevault.exe', *release.glob('*.dll'), *release.glob('native_assets.json'), *(p for p in (release / 'data').rglob('*') if p.is_file())]))
assert not any('vault' in p.relative_to(release).parts[:-1] or 'vault_data' in p.parts for p in files)
for file in files:
    content = file.read_bytes().lower()
    for private_path in [str(root), os.environ.get('USERPROFILE', '')]:
        if not private_path:
            continue
        for spelling in [private_path.replace('\\', '/'), private_path.replace('/', '\\')]:
            for encoding in ['utf-8', 'utf-16le']:
                if spelling.lower().encode(encoding) in content:
                    raise SystemExit('Private build path in runtime; rebuild with --split-debug-info before packaging')
with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
    for file in files:
        z.write(file, file.relative_to(release).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(files)
    for file in files:
        assert hashlib.sha256(file.read_bytes()).digest() == hashlib.sha256(z.read(file.relative_to(release).as_posix())).digest()
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
(out / 'SHA256SUMS.txt').write_text(f'{sha}  {archive.name}\n')
print(f'{archive}\n{len(files)} runtime files, all verified\nSHA256 {sha}')
