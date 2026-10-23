# Coordinated release checklist

Use only after explicit owner approval for the named version. A clear publication
approval covers both GitHub publication and the matching usual local stable
installation. Never infer approval from a candidate, CI, general feature request
or PR merge. A release is complete only when both sides are verified.

## Confirm and prepare

- [ ] Record the exact approved version, clean source commit/PR and candidate.
- [ ] Owner acceptance is recorded; significant open failures, privacy/security,
      licensing or Git-history concerns are resolved for the approved scope.
- [ ] Relevant analysis, full Flutter tests, focused regressions, both native
      suites and practical live/application checks passed. Clearly state limits.
- [ ] Verify version/build metadata, CHANGELOG and professional Added/Changed/
      Fixed/Known Limitations notes; link relevant PRs/issues without exaggeration.
- [ ] Reuse a verified matching Release when possible; otherwise verify data
      backups first and build in an isolated directory. No flutter clean.
- [ ] Package the complete EXE, DLLs and data runtime. Verify ZIP members against
      source runtime, run privacy/credential checks, and generate/recheck SHA256.
      Exclude personal vaults, sessions, artwork, settings, reports, symbols,
      credentials and backups. Never overwrite older packages.
- [ ] Review clean publishing files and reachable history. Do not push original
      private history. Verify the intended tag does not exist; never move tags.
- [ ] Record repository visibility, main/tag/release identities and existing
      assets for post-operation comparison. No license/visibility changes.

## Protect and upgrade local stable

- [ ] Verify GameVault is safely closed. Ask the owner to close it if necessary;
      never force-kill it while sessions/data may be unsaved.
- [ ] Create/refresh a separate private backup of current Release vault_data and
      verify every relative file path and SHA256. Do not alter the original.
- [ ] Archive the complete previous stable Release folder under
      `previous_versions/v<previous-version>/Release` and verify its file hashes.
      Never overwrite an existing archive; verify/reuse an identical one or stop
      on a collision requiring a decision. Preserve earlier independent backups.
- [ ] Verify the approved candidate ZIP/checksum and extract it into staging.
      If installing a version already published, use its official verified ZIP.
- [ ] Install only its complete runtime at
      `build/windows/x64/runner/Release/gamevault.exe` relative to the active
      project. Preserve vault_data exactly; never merge Debug, V1 or other data.
- [ ] Verify installed version/runtime files and unchanged vault file hashes.
      Preserve historical V1, both vaults, old releases and prior candidates.

## Publish and verify

- [ ] Complete the explicitly approved clean-history PR/release merge after
      required checks. Create the correct annotated version tag on that approved source.
- [ ] Publish the separate GitHub Release with accurate notes, Windows portable
      ZIP and SHA256SUMS.txt. Mark newest stable Latest. Preserve prior releases,
      tags/downloads and source history; keep visibility unchanged.
- [ ] Download published assets, verify access, filenames, ZIP/runtime contents
      and hashes, and confirm agreement with the installed approved version.
- [ ] Verify earlier releases/assets/tags are unchanged and no private data was
      uploaded. Confirm originals/backups remain safe and no app was left running
      by verification tests.
- [ ] Report installed version/path, public commit/PR/tag, release and download
      URLs, filenames/hashes, tests, limitations and preservation results.

## Failure and partial completion

Stop on failed checks or significant unexpected concerns. Do not bypass CI,
repair history through force-push, change integration scope or delete data to
finish a release. Preserve current/archived runtime and vault; use verified
backups for a safe runtime rollback when needed, without overwriting newer user
data. Report whether local installation, publication, both or neither succeeded.
If publication is incomplete, do not claim the installed version is officially
released. Obtain direction for substantial recovery or scope changes. No routine
release deletes earlier versions, releases, candidates, tags or personal data.
