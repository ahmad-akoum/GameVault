# Release readiness - 2026-10-16

Status: V2.0 and V2.1 are prepared locally for owner testing and approval. No stable GitHub release, asset upload, push or visibility change has been performed. The existing GitHub repository is still private with its original V2 release candidate.

## V2.0 stabilization
- Settings version comes from native Flutter build metadata (2.0.0+2).
- Standard DualSense Raw Input supplements unchanged keyboard/mouse GetLastInputInfo and XInput sampling. Supports simple/enhanced Bluetooth and USB input reports for vendor 054c/product 0ce6; meaningful buttons, D-pad, sticks and triggers update only an activity timestamp. Neutral reports and small analog values are ignored; no button histories or output reports are collected.
- Idle monitoring avoids unnecessary UI notifications. Artwork loading avoids synchronous file existence probes and bounds decode width. No measured 120/180 FPS claim.
- Windows shutdown now explicitly destroys the engine/window before COM teardown. An actual close crash found during package testing was fixed and retested with exit 0.

## V2.1 visual customization
Six presets, independent accent/background/surface controls, RGB/hex preview, Dark/Light/System modes and contrast adaptation; persistent Compact/Comfortable/Expanded profiles; full-window artwork viewer with aspect-preserving zoom/pan/reset and Escape/Close. No ratings integration or HLTB Explorer.

## Verification
- V2.0 stabilization: analysis and original 53 Flutter tests passed; final V2.0 native runtime passed extracted-package startup/close after the shutdown fix.
- Final V2.1: analysis clean and all 61 Flutter tests passed, including all existing scanner, selective import, persistence, session/AFK and UI tests.
- Native C++ activity parser tests passed for report layouts, drift boundaries, triggers, buttons/D-pad, neutral and malformed reports.
- V2.1 native fixture passed launch, process detection/termination, unique association, missing-executable rejection, persistence and native version 2.1.0+3. No commercial game or Steam URI was launched; foreground focus was not observed in the automation environment.
- V2.1 upgrade test on a private copy preserved full game/session records and settings after reopening. Original V1/V2 vaults were checksum-verified unchanged, independently of their backups.
- Both Windows x64 ZIPs contain 15 verified runtime files, pass ZIP integrity checks, and pass extracted-app startup plus close with exit 0 using separate empty QA vaults.
- Runtime privacy checks reject local project/home paths; final release builds use a temporary generated-package alias and private debug symbols. No SDK edit, dependency addition, source relocation or binary patching is involved. The generated configuration is restored byte-for-byte.
- Prepared publishing files and complete existing publishing history were scanned for known credential patterns, private paths and personal vault files; no findings. This is a bounded pattern audit, not a universal guarantee that any arbitrary secret format could be detected.

## Artifacts
Both are under release_artifacts/ready, outside disposable build folders. Each directory includes the ZIP, SHA256SUMS.txt, an extracted portable runtime and release notes. Earlier unpublished draft artifacts and all original historical releases are retained privately; use only the ready packages.

```
3b513082d48fa07ebd9835321836025620b78289611ddd2e2bbc4796ebd8ae1b  GameVault-v2.0.0-windows-x64.zip
2aa6e07d675af01b846b8d442f5c633c3b00567da86c3dc73c803ef089ca6fdd  GameVault-v2.1.0-windows-x64.zip
```

V2.0 is built from its own stabilized source, before V2.1 feature changes. Original history is retained; new commits were appended. The initial unpublished V2.0 preparation tag is preserved under checkpoints/v2.0.0-before-shutdown-fix, and the local V2.0 release tag now points to the final shutdown fix. Existing published V1 and V2 release-candidate tags were not changed. Only the approved clean main history and two stable tags should be pushed, never private original history or checkpoint tags indiscriminately.

## Owner acceptance and public distribution
Test DualSense Bluetooth with Steam Input enabled and disabled: buttons, both sticks, shoulders, D-pad and triggers; neutral idle for over 60 seconds; resume input; Alt+Tab beyond the configured focus grace. Verify keyboard/mouse and existing XInput on available hardware, real Steam launching, ordinary collections/progress use and appearance after app restart. Test actual 180 Hz scrolling; no physical high-refresh measurement was performed. A clean second Windows PC and physical Android testing remain unverified.

HLTB Explorer is postponed by the owner. Existing website-based HLTB access is unchanged. A documented authorized API/redistribution agreement has not been verified; the site's parent terms restrict automated extraction except where permitted. Public distribution is not cleared. Options: obtain written provider permission, or separately approve disabling/replacing website retrieval while preserving existing cached data and appropriate source links. No such change will be made without owner approval. Dependency notices do not grant rights to external artwork/data, and no open-source license for original GameVault code has been selected.

Next: owner tests V2.1; resolve any issues, then explicitly approve private GitHub publication and its assets. Public visibility requires separate approval plus the HLTB/licensing decision.
