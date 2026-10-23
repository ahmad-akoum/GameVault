"""Bounded privacy guard for the clean publishing checkout, not a secret detector guarantee."""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import PurePosixPath

PRIVATE_PARTS = {'vault_data', 'credentials', 'secrets', 'backups', 'previous_versions',
                 'release_artifacts', 'build', '.ci-build', '.dart_tool', 'logs', 'cache'}
SOURCE_BINARIES = {'.exe', '.dll', '.pdb', '.zip', '.apk', '.aab', '.msix', '.msi', '.dpapi', '.pfx', '.p12', '.pem', '.key', '.jks', '.keystore'}
PATTERNS = [
    rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{30,}',
    rb'AKIA[0-9A-Z]{16}',
    rb'[A-Za-z]:[\\/]+Users[\\/]+(?!Public[\\/])[A-Za-z0-9_. -]+[\\/]',
]


def private_name(name, runtime=False):
    path = PurePosixPath(name.replace('\\', '/').lower())
    parts = set(path.parts)
    if PRIVATE_PARTS & parts or '..' in parts or path.is_absolute():
        return True
    if path.name.startswith('vault.json') or path.name == 'vault.lock':
        return True
    if path.name == '.env' or (path.name.startswith('.env.') and path.name != '.env.example'):
        return True
    if path.suffix in {'.db', '.sqlite', '.sqlite3', '.dpapi'} or '.db-' in path.name or '.sqlite-' in path.name:
        return True
    return path.suffix == '.pdb' if runtime else path.suffix in SOURCE_BINARIES


def sensitive(content):
    return any(re.search(p, content, re.IGNORECASE if i == 4 else 0)
               for i, p in enumerate(PATTERNS))


def git(*args):
    return subprocess.check_output(['git', *args])


def scan_files(staged=False):
    names = git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z') if staged else git('ls-files', '-z')
    failures = set()
    for raw in names.split(b'\0'):
        if not raw:
            continue
        name = raw.decode('utf-8')
        content = git('show', ':' + name)
        if private_name(name) or sensitive(content):
            failures.add(name)
    return failures


def scan_history():
    records = git('rev-list', '--objects', 'HEAD').decode('utf-8').splitlines()
    names = {}
    failures = set()
    for record in records:
        oid, _, name = record.partition(' ')
        names[oid] = name
        if name and private_name(name):
            failures.add(name)
    data = subprocess.check_output(['git', 'cat-file', '--batch'], input=('\n'.join(names) + '\n').encode())
    offset = 0
    while offset < len(data):
        end = data.index(b'\n', offset)
        oid, kind, size = data[offset:end].decode().split()
        size = int(size)
        content = data[end + 1:end + 1 + size]
        offset = end + 2 + size
        if kind == 'blob' and sensitive(content):
            failures.add(names.get(oid) or 'historical blob')
    return failures


def scan_zip(path):
    failures = set()
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            failures.add('archive integrity')
        for item in archive.infolist():
            if private_name(item.filename, runtime=True) or sensitive(archive.read(item)):
                failures.add(item.filename)
        required = {'gamevault.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so'}
        failures.update(required - set(archive.namelist()))
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    parser.add_argument('--history', action='store_true')
    parser.add_argument('--zip', dest='archive')
    args = parser.parse_args()
    failures = scan_zip(args.archive) if args.archive else scan_files(args.staged)
    if args.history:
        failures.update(scan_history())
    if failures:
        # Never print matching content or a secret value.
        print('Privacy review required for: ' + ', '.join(sorted(failures)), file=sys.stderr)
        return 1
    print('Privacy guard passed (bounded filename/credential/path checks).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
