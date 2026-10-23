# QueueAppUpdate: focused investigation

2026-10-23; continuation of Issue #16 / draft PR #17. Candidate 4 stays at
2.3.0+12, unchanged. This work creates no updater, client connection or new
candidate. No QueueAppUpdate call, installation, injection or Steam write occurred.

## What the interface is

Millennium commit `f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a` was inspected.
Its Downloads.ts is a TypeScript **interface declaration**, not an implementation.
It describes a numeric AppID method returning void that adds an update to the
queue, alongside distinct Resume and queue-order methods. These declarations
are community descriptions, not a Valve support contract or an execution trace.
The companion SteamClient.ts declares an existing global SteamClient object;
importing these types into another program does not create the native binding.

Read-only inspection of the installed client's steamui/sp.js found a call to
SteamClient.Downloads.QueueAppUpdate with **two** arguments: the game AppID and
CurrentViewingRemoteClientID. Separate ResumeAppUpdate calls include the same
client identifier; a Resume callback is associated with the MoveToTop UI action.
No bundled code was executed or copied into the public repository. Private
inspection evidence records the bundle SHA256 and bounded snippets. This
supports the conclusion that the binding belongs to Steam's client context,
not that Millennium implements its download engine.

The second argument is a concrete compatibility difference from the one-argument
community type. Its valid local-client sentinel and failure/return behavior
were not established. Do not guess that value or inherit a remote client from
the currently viewed Downloads page. A one-argument call is not validated by
finding its name or checking function.length.

### Queueing is not confirmed downloading

The declaration says queue, not unconditional start-now. Immediate scheduling,
paused/global-pause interactions, priority and existing-entry behavior remain
unverified. Void supplies no documented acknowledgement or error payload.
A returned call could mean only that a request was dispatched. A future
implementation must correlate a fresh result for the same AppID and **local**
client, separately reporting request sent, queued, active transfer, completion,
error and timeout. Do not call Resume, reorder the queue, globally enable
all downloads or set launch-on-completion to manufacture success.

## Execution context and architecture

Millennium's SDK starts inside Steam's web UI and waits for Steam's builtin
App initialization. The framework's inspected backend uses CDP target
attachment, script/world creation, JS evaluation and frontend/backend IPC.
Its webkit world manager also contains a CSP-bypass operation. This is source
inspection only: none of those operations was performed here. This framework
path does not satisfy a requirement for zero client modification/injection or
security-boundary changes.

The installed helper processes include remote-debugging flags, discovered only
as booleans from process metadata. No debugger address, token or session was
extracted, no endpoint was contacted, and no debugger was attached. A debugging
flag is not permission or proof of a usable supported external API. Running
Runtime.evaluate inside Steam would cross the no-injection boundary for this
investigation even if the expression were read-only.

GameVault's current Flutter Windows app has no bridge exposing this JS global.
An external Node test process genuinely reports SteamClient absent. That proves
absence in that process, not the mathematical impossibility of every IPC path.
No supported direct QueueAppUpdate route into stock Steam was identified.
Adding a WebView or importing a .d.ts file cannot grant Steam-native bindings.

## Integration choices

| Option | Requirements and decision |
| --- | --- |
| Direct call from current Flutter process | Binding/context missing; no validated callable bridge. Do not implement. |
| Attach to existing CEF debugger | Requires authorized client-context evaluation and a validated target/client ID. Not attempted; not an approved default solution. |
| Optional Millennium companion | Could run inside the client context and expose a narrow bridge. Requires explicit installation and client-modification approval. This is a potential design, not a working integration. Current framework behavior also conflicts with the preferred no-injection/no-boundary-change constraints. |
| Another purpose-built companion | Still needs a legitimate Steam-side entry point. Merely moving code into another EXE does not create one. No validated alternative found in this focused scope. |

A companion should be optional, off by default and unavailable without a
capability handshake. Suggested future transport: a per-user ACL-restricted
named pipe, versioned protocol, authenticated pairing outside the vault,
fixed action allowlist (never arbitrary JS/URLs), request IDs, timeouts and
replay/rate limits. Revalidate installed AppID, local target and Available state
at dispatch; leave queued/paused/updating games untouched. Current Millennium
IPC internals should not simply be exposed as a general-purpose local eval API.
These are design recommendations, not implemented security guarantees.

## Read-only proof of concept

`tool/queue_context_probe.cjs` inspects the shape of a supplied JavaScript
context. It validates a positive uint32 AppID, checks whether Downloads has a
QueueAppUpdate function, and reports the limitation. It has no socket, IPC,
client attach, method invocation or execute switch. canRequestUpdate,
requestSent and downloadConfirmed always remain false. A property getter can
run while inspecting a supplied object, so pass only trusted contexts; this
experiment was run in an ordinary external Node process or synthetic objects,
never inside Steam. AppID validation does not prove ownership or installation.

Actual external-process result: valid AppID, Steam binding absent, no request
possible through that context. Mock tests expose a function which throws if
called and verify zero calls. They cover missing/malformed/throwing contexts,
invalid AppIDs and differing function arities. The Python unittest wrapper runs
these assertions in CI. Positive mock capability detection is **not** a real
Steam capability or successful update test. No new mandatory app dependency.

## Recommendation and live-test boundary

Do not ship a default QueueAppUpdate integration now. An optional companion is
technically plausible, but not proven maintainable, authenticated or safe with
the current Steam build. Client changes can break the signature, context,
initialization and callbacks; the local second-argument discrepancy is direct
evidence of that risk. Millennium itself is not intrinsic to Steam's method,
but some authorized way into Steam's client context is necessary for this route.

A live test is unnecessary to establish the missing direct bridge. To explore
the optional route further, first approve a specific companion/client-context
mechanism and review its security behavior; do not bundle/install Millennium
silently. A separate test machine is preferable. First test only capability
and local-client identification without queue calls. Only then approve one
named, installed, unqueued pending game, expected size and bandwidth effects.
A real queue test may consume bandwidth/disk or leave partial files, and cannot
promise immediate transfer. Stop on identity/state changes. Rollback must use
Steam's own controls with approval and remove the optional companion, restoring
reviewed configuration backups; bytes already downloaded cannot be undone as
if nothing happened. Never roll back by editing manifests or download files.
No such live-test permission is assumed or requested as part of this checkpoint.

## Pinned primary sources

- [Downloads declaration](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/typescript/sdk/src/sharedjscontext/globals/steam-client/Downloads.ts).
- [Global binding declaration](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/typescript/sdk/src/sharedjscontext/globals/SteamClient.ts).
- [SDK initialization](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/typescript/sdk/src/index.ts).
- [Client hook setup](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/instrumentation/internal/steam_hooks.cc).
- [Webkit context manager](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/engine/plugin_webkit_world_mgr.cc).
- [IPC context evaluation](https://github.com/SteamClientHomebrew/Millennium/blob/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a/src/engine/core_ipc.cc).

Local Steam source is proprietary implementation evidence, not an official API
contract. It is not reproduced in this report or shipped with the probe.
