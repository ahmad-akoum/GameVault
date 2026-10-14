# Development and release workflow

## Branches and history

Use `main` for reviewed source and `codex/<short-description>` for changes. Keep
commits focused and descriptive. Do not force-push shared history or move published tags.
This repository's initial import commits preserve genuine V1/V2 source snapshots;
their original local commit IDs are recorded in docs/SOURCE_PROVENANCE.md.

The original development repository remains a local archive, including private
diagnostics. Do not push that archive's old branches or use `git push --all`/`--mirror`.
Continue future publication work from this clean history. Changes made in the old
working folder must be reviewed and transferred as source-only changes first.

## Safe development

Keep real vaults outside Git. Use `GAMEVAULT_DATA_DIR` pointing to an isolated
`build` subdirectory. Never copy real user data into tests, screenshots or release archives.
Store credentials in an OS credential store outside the checkout; `.gitignore` does
not remove secrets already committed. Keep `pubspec.lock` tracked for reproducible resolution.

Run `flutter pub get`, `scripts/prepare_windows.ps1`, `flutter analyze --no-pub` and
`flutter test --no-pub`. Build Windows from a clean checkout with `lib/main.dart`.
Do not run a production-data migration merely to validate publication changes.

## Release checklist

1. Review changes, update CHANGELOG.md and write `docs/releases/<tag>.md`.
2. Align application build metadata when making a new release build. The initial RC
   preserves V2's original `2.0.0+2`; its Git tag and prerelease notes control release status.
3. Run analysis/tests and relevant Windows/native checks. Record failures and untested cases.
4. For binary delivery, build in a clean checkout. Package only the release EXE, required
   runtime DLLs and Flutter `data` directory. Never package `vault_data`, logs or credentials.
5. Review every tracked file and all commits being pushed for secrets and personal data.
   Review screenshots and archive contents; record a SHA256 for any release archive.
6. Ask the owner to approve remote creation, pushes and release publication, naming the
   exact branch, tag, visibility, notes and assets. This is required for Codex-assisted releases.
7. After approval, create an annotated tag on the reviewed commit and push explicit refs.
8. Publish release candidates as GitHub **prereleases**, using their reviewed notes.
   Verify repository privacy, remote commit/tag IDs, prerelease status and assets afterward.

The first approved upload will contain `main`, historical `v1.0.0` and
`v2.0.0-rc.1`, plus a source-only RC prerelease. Do not create a stable `v2.0.0`
until the owner confirms acceptance testing. Do not publish a fabricated V1 release page.

Use rc.2/rc.3 for further candidate fixes. After acceptance, publish v2.0.0 from the
accepted source. Subsequent bug fixes use 2.0.x; approved additive ratings work can use
2.1.0 prereleases; incompatible or larger redesigns can use 3.0.0. Each version needs
its own changelog, verification and owner-approved publication.
