"""Package only Windows runtime files; never include portable personal data."""
import hashlib
import pathlib
import sys
import zipfile

version = sys.argv[1]
root = pathlib.Path(__file__).resolve().parents[1]
release = root / 'build/windows/x64/runner/Release'
out = root / 'build/dist' / ('v' + version)
out.mkdir(parents=True, exist_ok=True)
archive = out / f'GameVault-v{version}-windows-x64.zip'
if archive.exists():
    raise SystemExit('Refusing to overwrite an existing release archive')
files = [release / 'gamevault.exe', release / 'flutter_windows.dll', release / 'data/icudtl.dat', release / 'data/app.so']
assert all(p.is_file() for p in files), 'Incomplete runtime'
files = sorted(set([release / 'gamevault.exe', *release.glob('*.dll'), *(p for p in (release / 'data').rglob('*') if p.is_file())]))
assert not any('vault' in p.relative_to(release).parts[:-1] or 'vault_data' in p.parts for p in files)
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
