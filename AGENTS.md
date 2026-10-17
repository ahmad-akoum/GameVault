# GameVault project instructions

## Feature documentation

Whenever implementing or significantly changing an important feature, add or
update concise technical documentation in the repository, organized by
feature. Explain what it does, how it works in beginner-friendly language,
which main source files, classes, and functions are involved, and the important
design decisions and reasons behind them. Record significant bugs with their
root causes and fixes, and summarize how the feature was tested. Keep the
documentation accurate and lightweight; avoid unnecessary detail or repeating
information already documented elsewhere. Do not retroactively document
unrelated existing features unless the owner asks.

## Permanent release workflow — V2.2 and later

When the owner explicitly confirms that a particular GameVault version is
complete, tested, and approved for release, prepare and publish that version as
a new GitHub Release in `ahmad-akoum/GameVault`. That confirmation authorizes
the corresponding GitHub publication and release-asset uploads; do not request
separate publishing permission.

Approval is version-specific. Never infer approval from a development request,
test result, or approval of an earlier version. Never publish unfinished
versions, experimental builds, or versions without explicit owner approval.
This instruction is a standing workflow, not approval to publish any version now.

### Before publication

- Run the appropriate automated tests and static analysis. Verify the Windows
  release build corresponds to the approved source and version. Reuse an already
  verified matching build when appropriate; do not rebuild unnecessarily.
- Verify the portable ZIP contains `gamevault.exe` and every required Windows
  runtime dependency. Check archive integrity and runtime completeness.
- Prepare accurate version-specific release notes with Added, Changed, Fixed,
  and Known Limitations sections. Describe only implemented functionality and
  verified testing; disclose relevant limitations without implying endorsement
  or licensing that has not been established.
- Generate `SHA256SUMS.txt` for the final ZIP. Attach both files to the release.
- Inspect all proposed source files and publishing history, plus release
  artifacts, for credentials, private data, personal vaults, session history,
  private backups, screenshots containing private information, and sensitive
  local paths. Exclude them from publication.
- Verify the version tag points to the correct approved source and matches the
  prepared build. Use the established privacy-clean publishing workflow; never
  push the private development history. The existing publishing checkout is an
  export destination, not another active development project.
- Check the repository's current visibility and existing releases/tags before
  publishing so they can be verified unchanged afterward.

If any verification fails, or a significant privacy, security, licensing, or Git
history concern is found, stop and explain the issue to the owner before
publishing. Ask for direction rather than bypassing checks or undertaking a
substantial history repair. This exception takes precedence over automatic
publication after approval.

### After publication

- Mark the newest stable version as Latest.
- Preserve all earlier releases, tags, downloads, and source history. Never
  overwrite or retarget an existing published version.
- Keep the repository's existing visibility unchanged.
- Verify the published tag, release description, attached files, and download
  access. Download the uploaded assets and compare their checksums with the
  validated local artifacts.
- Report direct GitHub links to the release, Windows ZIP, and checksum file,
  together with the verification outcome and unchanged repository visibility.

### Local preservation

- Keep this directory as the sole active development project. Preserve the
  historical V1 directory and its personal vault without modification.
- Preserve the active personal vault, artwork, sessions, settings, metadata,
  private backups, and all older release packages independently. Never merge
  historical and current vaults automatically.
- Before a build or cleanup that could affect personal data or existing release
  artifacts, verify protected backups outside disposable build directories and
  refresh them if the originals have changed. Preserve originals and keep
  backups private. Close the application before replacing its executable.
- Do not modify game files, Steam settings, or unrelated projects for release
  preparation.

Carry these release instructions into the reviewed publishing source when
preparing future versions, without copying private development records.
