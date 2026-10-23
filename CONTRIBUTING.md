# Contributing and reviewing GameVault

Start with an existing Issue or propose a focused one. Include expected behavior
and acceptance criteria; use the approved version milestone. Large features can
use parent/sub-issues and blocked-by relationships. Do not invent roadmap scope.

Use a descriptive feature/fix branch and meaningful Conventional Commits. Add
appropriate tests and concise feature documentation. Open a coherent PR linked
to the issue with behavior/reasons, implementation notes, actual test results,
risks and remaining manual acceptance. Include UI screenshots using synthetic
data when practical; do not publish private libraries, paths, vaults or credentials.
Use closing references only for completed work. Do not create artificial PRs.

The owner retains private original development history; public review branches
are reviewed source exports from that active project. Never push private history
or force-push main. This is an honest import workflow, not invented old commits.

Keep `pubspec.lock` tracked. Store credentials in an OS credential store outside
Git; ignore rules do not remove secrets from existing history. Use
`GAMEVAULT_DATA_DIR` with a disposable test location, never personal data or a
production migration just to validate publication changes. Original snapshot
provenance remains in `docs/SOURCE_PROVENANCE.md`. Never use push --all/--mirror,
fabricate a historical V1 binary release, or move an existing version tag.

Required PR checks are Privacy guard and Windows validation. The latter uses
Flutter 3.38.5, locked dependencies, analysis, the complete offline Flutter suite,
both C++17 inactivity suites and a Windows x64 Release build. See
[development instructions](docs/DEVELOPMENT.md) for local testing, privacy tooling
and manual hardware/service limitations. CI never publishes a release.

Passing CI does not replace owner acceptance or authorize a stable merge/release.
Candidate PRs remain draft until ready. One explicit version-specific publication
approval later authorizes the coordinated GitHub release and local stable upgrade,
subject to [release safeguards](docs/RELEASE_CHECKLIST.md). Preserve prior versions
and all personal data. Public visibility does not itself grant an open-source
license; do not assume reuse permission or add a license without owner approval.
