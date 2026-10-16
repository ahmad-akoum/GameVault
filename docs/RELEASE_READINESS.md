# Release verification — 2026-10-16

The owner approved V2.0.0 and V2.1.0 publication after V2.1 testing, including the artwork flicker fix with CONTROL Resonant and S.T.A.L.K.E.R. 2.

V2.0.0 retains its separately validated stabilized source and Windows runtime. V2.1.0 includes crop-aware artwork decoding and stable cached-image resolution during tracker updates. V2.1 static analysis passed and all 68 Flutter tests passed. Both prepared Windows portable archives have 15 verified runtime files, including the executable, Flutter engine, plugins, ICU data and app bundle. No rebuild was required for publication.

V2.0 ZIP SHA-256: `3b513082d48fa07ebd9835321836025620b78289611ddd2e2bbc4796ebd8ae1b`.
V2.1 ZIP SHA-256: `6846e354943f1da3a27c19ae54fb5371b02011c0ff9e352f158a336f6c8e6139`.

Packages exclude personal vaults, artwork caches, sessions and private debug symbols. Publication uses reviewed source history, separate from private development records. See version-specific release notes for limitations. Existing HowLongToBeat behavior is unchanged; no official license or endorsement is claimed, and public-distribution permissions remain unresolved. The separate Explorer is deferred. Repository visibility must remain unchanged.
