# Development and review workflow

The active project is the sole development source. The original local Git
history is private and has no push remote. The existing privacy-clean publishing
checkout is only an export/review destination. Never push original local history.

## Issue to PR

1. Inspect existing work and related Issues/PRs; preserve valuable uncommitted work.
2. Use a descriptive Issue with expected behavior, acceptance criteria, labels
   and an approved milestone. Split large features into useful native sub-issues
   and record dependencies. Avoid duplicates and unapproved future scope.
3. Create a feature/fix branch, normally `codex/<purpose>` here. Implement and
   test in the active project, committing coherent changes as they progress.
4. Export only reviewed source/configuration/tests/tools and public-safe docs
   to a clean publishing branch based on its proper review base. Preserve its
   existing history; never merge private commits, reset main or force-push.
5. Run `tool/ci_guard.py --staged` and `--history` in the clean checkout; review
   the diff, push the named development branch and open a linked PR. These checks
   are bounded and do not replace a manual audit. Private reports/Steam inventories,
   personal screenshots, credentials, vaults and binaries are not exported.
6. Resolve CI/review failures. Use Refs rather than closing references while
   acceptance remains pending. Candidate work stays draft and unmerged until
   approved. Do not manufacture retrospective feature branches/commit history.
7. Report local and publishing branches/commits, Issues/PRs, pushes, checks and
   remaining owner acceptance. An approved workflow PR may be merged separately;
   merging workflow files must not merge candidate application changes.

## Testing before owner acceptance

- Resolve dependencies against pubspec.lock; run `flutter analyze --no-pub` and
  the complete `flutter test --no-pub` suite, plus focused regressions.
- `scripts/test_native.ps1` locates the installed Visual Studio C++ toolchain
  and runs both C++17 inactivity suites with assertions, in isolated output.
- Add/update meaningful tests for important behavior and root-cause fixes.
- For app changes, use an isolated Windows build and disposable test vault.
  Verify startup/shutdown, persistence, failure handling and responsive layouts
  where practical. Existing build/startup evidence can be reused if app source
  and artifacts are unchanged. Never replace the stable runtime during testing.
- Hardware/gameplay, moved real Steam games, exact Steam UI agreement, a second
  PC and external-service availability are not guaranteed by CI. Live HLTB tests
  are opt-in and must not be enabled as flaky public-PR gates. Never inject user
  credentials into public PR workflows. Keep mocked/live/manual evidence distinct.
- CI has Privacy guard and Windows validation checks. Actions are SHA pinned;
  the token is read-only. CI resolves dependencies, analyzes/tests, runs native
  suites and builds Release on a disposable Windows runner. It uploads no runtime,
  user data or release assets and has no release/deployment action or tag trigger.
- Workflow-only changes require guard/script/template validation and real PR CI;
  do not rebuild or relaunch personal/candidate apps unnecessarily.

## Roadmap and repository protection

Use the V2.3.0 milestone and linked issues for approved scope. Native sub-issues
and blocked-by links are available. The current CLI lacks Projects scopes, so
no GitHub Project was created. If the owner later authorizes browser-based
`gh auth refresh -s project`, create a simple board using existing issues:
Backlog, Ready, In Progress, In Review, Done; Priority; Target version; Category.
Do not create duplicate issues or infer new future-version requirements.

Proposed protection for main (not applied without approval): require PRs plus
Privacy guard and Windows validation; prevent force-push/deletion; no mandatory
second-person approval for a solo owner; retain an owner emergency bypass.
Owner review/approval still governs candidate merges and publication. No visibility,
license, permission or protection setting is changed by the workflow files.

## Stable installation and release

See `RELEASE_CHECKLIST.md` and AGENTS.md. One explicit version-specific publication
approval authorizes the coordinated GitHub release and local stable upgrade;
no separate approval is needed for those two actions. Development/CI success and
PR creation/merge alone are not release approval. Significant failures, privacy,
security, licensing or history concerns still require stopping before publication.

Stable remains at `build/windows/x64/runner/Release/gamevault.exe` relative to
this project. Preserve V1, Debug and Release vaults independently, private backups,
previous versions/candidates, and all earlier tags/releases/downloads. Never merge
vaults or run flutter clean during release preparation. Before builds that could
affect data, verify independent backups outside disposable build directories.

Always build final Release with `-t lib/main.dart`. Use the existing
`scripts/build_private_release.ps1 -Version <version> -BuildDirectory <isolated>
-SymbolDirectory <private>` helper, on the project drive, after safeguards pass.
It temporarily configures Flutter's relative build directory and neutral package
URI for the generated registrant, restores settings/package_config byte-for-byte,
and keeps debug symbols private. Do not run concurrent builds while it runs.
`tool/package_release.py <version> --build-dir <isolated> --output-dir <new>`
verifies and packages the complete runtime, excluding PDBs/vault_data. Run the
privacy guard on the ZIP and verify SHA256SUMS.txt. Never overwrite an old ZIP.

## Current V2.3 provenance

Tracking: [V2.3.0 milestone](https://github.com/ahmad-akoum/GameVault/milestone/1),
[acceptance/release gate #2](https://github.com/ahmad-akoum/GameVault/issues/2),
[Steam Update Center parent #6](https://github.com/ahmad-akoum/GameVault/issues/6),
and [workflow foundation #1](https://github.com/ahmad-akoum/GameVault/issues/1).

Candidate 2 (2.3.0+10) was implemented and built before Issue tracking existed.
It was checkpointed as one present-day local commit, not reconstructed into a
fictional development history. The clean PR is a reviewed source export. Owner
acceptance/publication is pending; stable remains V2.2.0. Existing candidate and
live-test evidence is preserved; this workflow task changes no application code.

## Verification tooling

`tool/ci_guard.py` checks tracked/staged file names and content without printing
matching values. `scan_history` also examines reachable clean publishing blobs,
so deleting a leaked value from the latest tree cannot hide it. `scan_zip` checks
runtime members and required core files; release packaging additionally verifies
all runtime bytes and checksums. The guard covers known credential signatures,
private Windows user paths, personal-data locations and unwanted artifacts; it
cannot detect every arbitrary secret or prove third-party licensing. Manual
review of the complete proposed publication is still required. It intentionally
fails on a private development repository containing historical private reports;
run publication/history scans in the clean export checkout.

`test/ci_guard_test.py` uses temporary synthetic Git history to test filename,
credential and deleted-secret detection without emitting the secret fixture.
`scripts/test_native.ps1` discovers Visual Studio with vswhere and compiles/runs
both input tests without NDEBUG. Local runs use new private output; CI uses its
disposable temp directory. The workflow never writes to a personal vault.
