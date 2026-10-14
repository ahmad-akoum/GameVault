# Roadmap — plans, not implemented features

## V2 acceptance

The owner has not personally accepted V2. Test ordinary Windows use, real game
launching/process detection, focus changes, idle/controller behavior, persistence,
restart/recovery and migration using a copy of data before declaring stable v2.0.0.

## V2.1 ratings research

Research has demonstrated authenticated RAWG and IGDB access and keyless Steam Store
metadata access. The proposed design uses platform-specific RAWG Metacritic critic
scores, a verified PC Steam fallback, and separately labeled IGDB community ratings.
Coverage is incomplete; unmatched or unsupported scores must remain unavailable.
Actual Metacritic User Scores have no verified practical integration yet.

No V2.1 provider, rating UI or credential configuration is implemented here. Research
credentials remain outside the repository. Confirm licensing, cache permissions,
attribution and distribution architecture before implementation/public delivery.
Never embed a shared Twitch secret in a distributed client.

## V3 and later

Possible account/achievement integrations and broader platform support require
separate design, authorization, reliable APIs and testing. Historical AFK time cannot
be reconstructed from Steam's total hours. These are possibilities, not promises.

Every future release follows CONTRIBUTING.md: reviewed source, changelog, tests,
appropriate build, annotated tag and owner-approved GitHub publication.
