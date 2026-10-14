# Source provenance

| Source snapshot | Original local commit | Published purpose |
| --- | --- | --- |
| Genuine V1 | `664de5f64d66af306bbacec975082e95fd03ba95` | Historical `v1.0.0` source tag |
| Existing V2 | `c36e31284969e0bb86400a8d47365a12d9f836d8` | `v2.0.0-rc.1` candidate |

V1 predates V2 in the original Git history. V2's implementation checkpoint is
`a56fa4e`, followed by the documentation checkpoint above. The publishing history
uses new, honestly dated import commits; original commit identities are recorded here.
The original repository and all its commits remain untouched locally.

Application source, tests, Windows runner and dependency manifests are unchanged
from their respective snapshots. The original app metadata remains `2.0.0+2` in V2;
the Git tag and GitHub prerelease identify its unapproved release-candidate status.
Future release builds may override build metadata without rewriting existing binaries.

Private inventories, raw logs, local validation reports and screenshots of a personal
library are omitted from every publishing commit. A machine-specific Steam audit
helper is also omitted. Synthetic test fixtures remain; they contain no user vault.
README, ignore rules and publication documents are new preparation work.

No historical public release or personal V2 acceptance test is claimed.
