# Integration decisions — 13 October 2026

## Critic ratings: deferred to V3

No authorized rating-data source was verified for this release. V2 does not fetch,
cache, display or fabricate Metacritic/OpenCritic scores. The detail page states
that ratings are not connected. There are no placeholder numeric badges.

Research consulted the publishers' own pages:

- [Metacritic About](https://www.metacritic.com/about-us/) describes the critic
  Metascore and links its terms of use; it does not establish permission for this
  application's programmatic retrieval, caching or redistribution.
- [Metacritic support](https://metacritichelp.zendesk.com/hc/en-us) did not establish
  a public developer API or grant for GameVault. This is not a claim that private
  commercial licensing cannot be arranged.
- [Fandom terms](https://www.fandom.com/terms-of-use) are linked by Metacritic.
  The current terms page could not be retrieved by the research tool, so its
  precise current restrictions were not verified. No license is inferred.
- [OpenCritic portal](https://portal.opencritic.com/) and its
  [plugin guidance](https://portal.opencritic.com/wordpress-plugin) indicate an
  API-key access route. Access and desktop-app display/cache terms for this project
  were not established; no provider account or key was created.

Public accessibility of a website or an undocumented score field in a third-party
API is not treated as proof of an authorized source. No score scraper, bypass,
unofficial proxy, or title-slug guessing was implemented.

To enable this feature in V3, obtain provider access and confirm permitted desktop
display, attribution, deep links, cache duration, retention/deletion and distribution
terms. Then implement a provider with these constraints:

1. Match exact game identity and edition, preferably via Steam AppID/provider IDs;
   require user resolution for ambiguous matches.
2. Store critic-only ratings keyed by provider, game ID, platform and score type.
   Prioritize PC. Keep optional PS5 and Xbox Series X|S scores separate.
3. Store source URL, retrieval time, expiration, review count (when supplied), scale
   and provenance. Validate numeric ranges and reject user-score payloads.
4. Display attribution and a link to the exact matching page beside each rating.
   Mark stale cached data; respect provider refresh and retention limits.
5. An OpenCritic aggregate must be labeled OpenCritic and its true platform scope;
   never relabel an aggregate as a PC Metascore or average platform scores together.
6. Test mismatched editions/platforms, unavailable scores, authentication failures,
   expired cache, changed terms, rate limits and source removal.

## Achievements and historical Steam playtime: deferred account integration

Valve's documented [ISteamUserStats interface](https://partner.steamgames.com/doc/webapi/ISteamUserStats)
provides `GetPlayerAchievements` and `GetSchemaForGame`. The former requires a
Steam Web API user authentication key, SteamID and AppID. No account credentials
were supplied for this task; private-profile behavior and actual per-user data
could not be validated. V2 does not scrape achievements or imply zero unlocks.

V3 should add explicit account selection and legitimate key-based access with
secure secret storage, privacy/error states and identity validation. Historical
Steam playtime should be displayed separately from GameVault sessions. It cannot
reconstruct historical AFK time, and it must not be added to overlapping tracked
hours to produce an inflated total.

## Existing V1 integrations

Steam installation discovery remains local and read-only. Steam store artwork and
metadata enrichment are preserved; their public endpoint is not a contractual API.
Saved HowLongToBeat estimates and previously saved match candidates remain in
the local vault and are shown on game profiles. Live search, refresh and website
script inspection are disabled while an authorized integration is unavailable.
This distribution change does not establish broader rights to the service's
data. No new ratings or achievements provider was added.

## Native Windows references

- [GetLastInputInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastinputinfo): session-local keyboard/mouse idle signal.
- [XInputGetState](https://learn.microsoft.com/en-us/windows/win32/api/xinput/nf-xinput-xinputgetstate): supported controller states, with dead zones.
- [QueryFullProcessImageName](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew): executable identity using limited process access.

GameVault never injects into game processes, hooks input, records key/button
contents, requests elevation, bypasses protected processes or changes Steam files.
