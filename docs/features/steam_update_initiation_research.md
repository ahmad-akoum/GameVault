# One-click Steam updates: investigation and read-only experiment

2026-10-23; Issue #16. Candidate 4 (2.3.0+12) remains the application baseline.
No automatic update initiation is implemented or verified. No real download,
launch, Steam modification, authentication extraction or client injection was
performed. No new candidate is warranted by this research-only checkpoint.

## Approaches examined

| Approach | Evidence and outcome | Reliability / cost / targeting |
| --- | --- | --- |
| Steam URI / client command line | Candidate 4's library-navigation URI works, but does not initiate updates. VDC protocol/CLI pages returned 403. No verified update-only contract found; no possibly mutating command executed. | Exact AppID navigation; low maintenance. Update initiation unverified. |
| Install URI in Playnite | SteamInstallController uses steam://install/AppID and watches for installation. Its watcher accepts an already installed game as installed; this does not prove a pending update started. | AppID target; source-confirmed install request, not an update-only guarantee. Requires a controlled test before any update claim. |
| Public Steamworks SDK | ISteamApps MarkContentCorrupt forces verification on next launch; it is not a supplied-AppID update dispatcher. InstallDLC targets optional DLC, not arbitrary base-game updates. | Reject for this task: wrong scope and launch/verification side effects. |
| SteamCMD / console | app_update is a lead for a separate content-management workflow, not a verified command to control the desktop client's existing pending queue. No console commands, installs, logins, linked library folders or SteamCMD changes were attempted. | AppID capable in principle; handling retail ownership, branches, destinations and existing queue behavior remains unverified. Not suitable to assume equivalence. |
| SteamKit2 | Project describes Steam network interoperability, rather than a ready-made control API for the installed client's update queue. | Separate network/session/content-client work; no drop-in local update method verified. Not installed or executed. |
| Reverse-engineered local IPC | Open Steamworks identifies itself as reverse-engineered client headers and is archived. No current compatible external AppManager binding tested. | Potentially AppID-specific, but ABI/client-version and lifetime risks; do not call unknown vtables or inject into Steam. |
| Internal client JavaScript / Millennium | Source types expose Downloads.QueueAppUpdate(appId), ResumeAppUpdate and other queue actions. Millennium is a Steam-client modding/plugin framework. Type declarations prove a known internal method name, not that stock external GameVault can safely call it. | Promising AppID-targeted lead, but requires a client-context bridge/plugin and version-dependent internal contract. Not installed, invoked or represented as officially supported. |
| Windows accessibility | Real Steam exposes named UPDATE buttons, including two copies in the inspected tree. The current page is queued; its document URL does not identify a selected AppID. | No blind coordinates required in principle. Unique visible/invokable control, correct game panel, localization, freshness and state revalidation still need a verified collector. Current observation must refuse. |

## Actual Windows inspection

Read-only Computer Use inspected the existing Steam library window twice. It
reported two UPDATE controls. The visible page still offered an UPDATE button
while displaying UPDATE QUEUED. That is important: a button label alone cannot
prove a new pending update is safe to start. The document URL was the generic
client page, not an AppID route. A title anywhere in the tree is insufficient,
because the sidebar contains many other games. We did not obtain a reliable
selected-AppID/control association, visibility disambiguation or Invoke-pattern
proof from this observation. No Update control was clicked.

The observation's queued state independently prevents an action under the
owner's rule: queued/paused downloads must not be altered. This is a concrete
blocker for this inspected target, not proof that all UI automation is impossible.
A future collector could use panel-scoped links/identity and UIA patterns, but
those bindings and their race behavior have not been implemented or validated.

## Isolated harness and tests

`tool/steam_update_probe.py` is a pure read-only eligibility model. Its JSON
input is supplied inspector evidence, not self-authenticating proof. It rejects
wrong/missing AppIDs, unverified windows, old observations, non-Available state,
and ambiguous/non-invokable controls. Positive synthetic input means only
eligible for a future controlled test. Every result explicitly says request_sent
false and download_verified false. There is no invoke, IPC, network, process,
click, Steam-file-write or execution option. It is not wired into GameVault.

`test/steam_update_probe_test.py` exercises safety refusal, no mutation,
synthetic eligibility and hidden-control filtering. The real observation was
projected to a private JSON containing only safety facts; the harness refused
it for missing selected identity, queued state and lack of a unique proven
control. Raw account/library screenshots and accessibility trees are not committed.
These are model tests and live read-only observation, not an end-to-end updater.
Installation drives do not enter the model: an eventual action must target an
AppID after the existing manifest/library resolver, never infer identity from a
folder or start a separate download into a guessed destination.

## Decision and next gate

Retain Candidate 4's honest manual-start guidance. Do not ship a theoretical
updater. The next useful experiment would be a read-only, panel-scoped collector
which can prove one eligible AppID and one visible enabled invokable UPDATE
control, refuse a queued/paused state, and revalidate immediately before action.
Only after that succeeds should the owner approve one named game's controlled
live update. A request acknowledgement and a later matching download/state
transition must be reported separately. No such approval or live transition is
claimed here. Plugin/internal API routes would additionally need an explicit
maintenance/dependency decision. Existing protections remain unchanged.

## Primary sources reviewed

- [Playnite install controller](https://github.com/JosefNemec/PlayniteExtensions/blob/master/source/Libraries/SteamLibrary/SteamGameController.cs).
- [SteamKit2](https://github.com/SteamRE/SteamKit).
- [Open Steamworks archive](https://github.com/SteamRE/open-steamworks).
- [Millennium Downloads interface](https://github.com/SteamClientHomebrew/Millennium/blob/main/src/typescript/sdk/src/sharedjscontext/globals/steam-client/Downloads.ts) and [framework](https://github.com/SteamClientHomebrew/Millennium).
- [Valve ISteamApps](https://partner.steamgames.com/doc/api/ISteamApps).
- [Microsoft UI Automation patterns](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-controlpatternsoverview).
- VDC [protocol](https://developer.valvesoftware.com/wiki/Steam_browser_protocol) and [command line](https://developer.valvesoftware.com/wiki/Command_line_options): access returned 403; contents not treated as verified. No restriction bypassed.
