# Development and release workflow

Use the existing active project. Preserve original local history; publish through the existing privacy-clean export repository, never by pushing private development history. No worktrees or per-version source projects are needed.

Before rebuilding, close the app and verify independent vault backups plus a complete known-good portable release outside disposable build folders. Never run flutter clean while the only vault copy is under build.

Run flutter analyze --no-pub and flutter test --no-pub. The native activity parser test is test/dualsense_activity_test.cpp; compile as C++17 (without NDEBUG) and run it. Windows native smoke testing uses tool/windows_smoke.dart and tool/native_fixture.cpp with GAMEVAULT_PROJECT_ROOT set to the active project. It writes synthetic data under build; the Debug runner is a test fixture after this build, not the normal application.

Always build the final Release with -t lib/main.dart. Confirm executable ProductVersion matches pubspec.yaml. tool/package_release.py creates the complete ZIP plus SHA256SUMS.txt and checks every archive member against the source runtime file. It does not package PDB files or vault_data. V2.0 must be committed and packaged before V2.1 changes; do not relabel V2.1 source as V2.0.

Prepare version-specific notes and a changelog. Export only reviewed source/configuration/tests/tools and public-safe documentation to the existing clean publishing history. Scan all reachable publishing blobs and packaged runtime content for private data and credentials. Original local private reports are excluded. Create annotated local tags only after checking the version-specific source. Do not move existing tags.

Ask the owner before pushing prepared publication commits, publishing releases, uploading assets or changing repository visibility. GitHub source ZIP/tar.gz will come from the approved clean tags. Keep prior releases. Public distribution also requires resolving service licensing and an explicit license decision for GameVault's own code.

Release packages are prepared under release_artifacts/ready/<version>. Private debug symbols remain under release_artifacts/private-symbols and must not be uploaded. A package privacy guard rejects local project/home paths embedded in runtime files. Use separate debug-symbol directories for each version.

The private-release helper temporarily gives Flutter's generated plugin registrant a neutral package URI in generated package_config.json, compiles the same source, then restores that configuration byte-for-byte in a finally block. No dependency, SDK edit or source relocation is introduced. Debug splitting alone does not remove that URI. Do not run concurrent builds while the helper is running.
