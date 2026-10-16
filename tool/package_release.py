"""Package only Windows runtime files; never include portable personal data."""
import hashlib
import os
import re
import subprocess
import pathlib
import sys
import zipfile

version = sys.argv[1]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected semantic release version')
root = pathlib.Path(__file__).resolve().parents[1]
release = root / 'build/windows/x64/runner/Release'
out = root / 'release_artifacts/ready' / ('v' + version)
out.mkdir(parents=True, exist_ok=True)
actual = subprocess.check_output(['powershell', '-NoProfile', '-Command', "(Get-Item -LiteralPath './build/windows/x64/runner/Release/gamevault.exe').VersionInfo.ProductVersion"], cwd=root, text=True).strip()
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
