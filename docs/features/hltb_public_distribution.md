# HowLongToBeat: V2.2 pause and V2.3 restoration

V2.2 disabled the provider, automatic lookup on import, profile search/refresh,
and live result controls for public distribution while integration rights were
unresolved. It preserved estimates, candidates and match identities.

V2.3 restores `WebsiteHltbProvider`, startup wiring, automatic lookup after an
explicit game import, profile search, manual match selection and refresh. Saved
estimates stay visible during requests and survive failures. A refresh uses the
saved match title and prefers its exact HLTB ID; it does not silently switch
editions because the local title differs. The old fixed warning is replaced by
actual request status and errors; legacy saved warning text is not displayed as
a current restriction. No database schema or existing estimate is reset.

`hltb_provider.dart` reuses the pre-V2.2 initialization, search payload, normal
website-issued token, response parsing and matcher. It uses an identifying
GameVault user agent. It does not inspect scripts, discover alternate endpoints
on denial, impersonate accounts, solve challenges or use proxies. HTTP 401/403
stops the request; 429 produces a cooldown. Timeouts, malformed responses and
network errors are failures, never invented empty-success results. Tokens and
response bodies are not logged.

## Verification on 2026-10-23

The earlier standalone initialization probe returned 403. It did not reproduce
the original request contract (including the timestamped initialization URL,
Origin and Referer headers), so it was insufficient evidence that restoration
was impossible. The restored adapter returned HTTP 200 for initialization and
search with its normal token flow. No script inspection or access workaround
was needed. We cannot infer the server's precise rule from the earlier probe.

`tool/hltb_live_check.dart` records only endpoint paths, status, safe response
metadata and retrieved public game entries. `hltb_live_roundtrip_test.dart`
passed actual search, manual selection, refreshed retrieval and persisted
match/estimate checks in a temporary vault. It runs only with the explicit
`GAMEVAULT_LIVE_HLTB=true` define. The normal suite uses mocked HTTP responses,
including denial, rate limits, malformed data and offline behavior.

These successful requests establish technical functionality, not permission,
licensing, endorsement, availability guarantees or public-distribution clearance.
The previous rights concern remains unresolved. This task authorizes a local
candidate only; publication requires the owner's separate release decision and
the project's distribution checks. The independent HLTB provider remains a
boundary if an authorized integration is required later.
