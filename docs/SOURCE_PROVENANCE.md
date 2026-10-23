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

Stabilized V2.0 source exported from original local commit `b18692fc1c8f6ef68d969809b7d7dd8fbb8ec715`. Private history was not imported. Runtime source is unchanged by export.

Final V2.0 source: `32583123ec2b0e9dc1206d56a62ac64a76c87820`, including the shutdown fix found during portable runtime testing.

V2.1 source exported from original commit `0d03964e1fa56f1076ed1e1f1ee682e35ba4d41c`. Application source and locked dependency versions match; only public documentation/ignore rules differ. Both final versions include the separate shutdown fix.

Final local V2.1 documentation/tag checkpoint: `f0b3356d7026b55448a768c7703a576c6437bda7`. Runtime source is identical to the implementation checkpoint above.

## Unapproved V2.3 candidate 2 source review

The candidate (2.3.0+10) was implemented and built before the Issue/PR workflow
was introduced. It is now imported as one honestly dated source checkpoint from
the active development project. No original private history or personal data is
pushed, no earlier feature commits are invented, and the existing public history
is retained. The source PR remains draft pending owner acceptance. Workflow
setup is a separate PR; neither PR publishes a release or upgrades stable.
