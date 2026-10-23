# GameVault project instructions

## Permanent development standard

- Start by reading these instructions, Git status/history/branches/tags/remotes,
  related Issues/PRs, and existing architecture. Preserve uncommitted work and
  candidate evidence; never reset, force-push, invent history or retag releases.
- Track meaningful work in an existing or new GitHub Issue with expected
  behavior, acceptance criteria, labels, related links and an approved-version
  milestone. Avoid duplicates. Use native parent/sub-issues and dependencies
  for coherent larger features, not trivial implementation details. Record old
  work retrospectively and honestly. Do not invent future-version scope.
- Use a descriptive feature/fix branch (normally `codex/<purpose>` in this
  environment; honor an explicitly requested branch name). Make logical,
  reviewable Conventional Commits during the task, not only at its end.
- The active repository retains private original history and must NEVER be
  pushed. Use the established clean publishing checkout as an export/review
  destination only, not another active development project. Create clean
  branches from the appropriate published/review base; export reviewed source
  and public-safe docs, scan proposed files and reachable history, then commit
  and push that branch. Do not import private commits or reports into it.
- Open coherent PRs linked to Issues. Explain behavior, reasons, implementation,
  actual testing, risks and remaining acceptance. Include synthetic-data UI
  screenshots when practical, or explain the available UI checks. Use closing
  references only for completed work. Keep unapproved candidates as draft PRs;
  never merge their release work into stable without owner approval.
- Development branch/PR publication is part of the requested workflow when
  appropriate; it is not release or stable-merge approval. Respect narrower
  task-specific restrictions. Check that pushes/PRs cannot auto-release.
- Keep GitHub CI verification-only, least-privilege and action-SHA pinned.
  Require dependency resolution, analysis, the full offline Flutter suite,
  native inactivity suites with assertions, Windows build verification, and
  bounded privacy/history checks. No release-on-merge/tag, secrets in PR jobs,
  automatic deployments or personal-data uploads. Never bypass failing checks.
- Before asking the owner to test: run relevant unit/widget/regression/native
  and practical integration tests; build and smoke-test an actual isolated
  executable where relevant; check disposable-vault persistence and failures,
  responsive UI and data safety. Reuse verified matching evidence for unchanged
  app code rather than rebuilding unnecessarily. Separate mocks, live-service
  results, application smoke checks, hardware/gameplay tests and owner acceptance.
  Report known failures and unavailable checks; never call incomplete real-world
  verification fully tested. End with a concise remaining acceptance checklist.
- Document important features per the guidance below; maintain CHANGELOG and
  version-specific notes. Follow `docs/RELEASE_CHECKLIST.md` after approval.
- Review repository protection/settings before changing them. Explain proposed
  permission or branch-protection changes and obtain approval before applying;
  avoid solo-developer lockouts. Never change visibility or add a license
  without explicit approval. Missing Projects scope is a reported limitation,
  not permission to silently broaden authentication.
- At the end of each task report branches, local and clean publishing commit
  hashes/summaries, Issue and PR links, push/merge state, checks/results, pending
  acceptance/permissions and data/release safety. Distinguish the two histories.


## V2.3 development safety

Build and test V2.3 only in an isolated candidate directory and separate test
vault. Preserve the current stable Release runtime and personal vaults. No tag,
publication, or stable installation upgrade is authorized by candidate testing.
On the V2.3 candidate branch, see `docs/features/installation_management.md`
and `docs/releases/v2.3.0.md`
for behavior, verification, and unresolved distribution limitations. Live HLTB
search/refresh is enabled in the current local candidate. Never
represent HLTB restoration as complete while live access is blocked, or bypass
website access controls to restore it.

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

## Permanent stable-install location and upgrade rule

The newest stable Windows application must always be installed at
`build/windows/x64/runner/Release/gamevault.exe` relative to this project root
(the owner's usual Release folder). For every approved stable-version upgrade:

- Close GameVault. Before replacing files, make a separate private backup of
  the current Release `vault_data` and verify every file by relative path and
  SHA-256. If the data changes during the operation, stop and investigate.
- For an existing published version, verify the official ZIP against its
  published SHA-256. During an approved coordinated release, verify the approved
  candidate ZIP/checksum before installation, then verify uploaded/downloaded
  assets after publication. Extract into a separate staging directory. Do not use a
  development build as the stable installer.
- Preserve the complete previous stable Release folder under
  `previous_versions/v<version>/Release`. Never overwrite an existing archive;
  verify the archived file paths and hashes against the original before
  installing the new version.
- Copy the official runtime files into the usual Release folder while leaving
  `vault_data` untouched. Never merge or replace it with Debug, V1, or another
  installation's data. Do not run `flutter clean` for an installation.
- Verify the installed executable's version, compare the installed runtime
  files with the official package, and confirm `vault_data` still matches the
  pre-upgrade backup. Keep archives and backups private and out of Git.
- Preserve the historical V1 project, Debug vault, private backups, and all
  earlier release folders, tags, and downloads. A prerelease or development
  build must never replace the newest stable installation.

## Permanent release workflow — V2.2 and later

A clear version-specific publication approval (for example, "Publish GameVault
V2.3 on GitHub"), or explicit confirmation that a version is complete, tested
and approved for release, authorizes BOTH its GitHub publication and upgrading
the usual local stable installation to that same approved version. Do not ask
for separate approvals for those two actions. It also permits the corresponding
reviewed release merge, tag and assets after required checks pass.

Approval is version-specific. Never infer approval from a development request,
test result, or approval of an earlier version. Never publish unfinished
versions, experimental builds, or versions without explicit owner approval.
This instruction is a standing workflow, not approval to publish any version now.

### Coordinated execution after approval

Follow `docs/RELEASE_CHECKLIST.md`: confirm the exact approved source/candidate
and checks; close the app safely; verify a fresh private vault backup; archive
and verify the complete previous stable runtime; install the approved runtime
without changing vault_data; verify version, runtime and vault; complete the
approved clean-history merge/tag/release and ZIP/checksum upload; download and
verify assets and installed-version agreement. Never delete prior versions.
If either local installation or publication fails, preserve data, report the
partial state, and recover using verified backups when needed. Do not claim a
completed release until BOTH installation and publication are verified.

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
