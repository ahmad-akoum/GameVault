# Storage Overview

Open Storage Overview from navigation to see sizes for games in My Library.
The page groups verified installations by drive and sorts each group by size.
Click the game to open its profile or the folder icon to open its installation.

StorageOverviewPage resolves each game's current folder through VaultController
before asking InstalledStorageService for a cached result. Opening the page
does not traverse installation trees. Refresh checks games in order and
reuses the result for duplicate paths. Cancel finishes the current check and
leaves the remaining folders alone. Cached sizes older than 24 hours are
marked stale; missing and unreadable installations have no measured size.

Totals count case-insensitive duplicate paths and measured descendants of an
already measured parent once. A missing parent does not hide a measured child.
Totals cover known logical bytes, include stale values with a visible count,
and are not measurements of all files, free space, or allocated disk space.
Displayed KB/MB/GB follow binary Windows-style scaling. Cached byte counts
are unchanged. No game files are modified.

Tests cover shared and nested paths across drives, unit boundaries, cached
loading, and cancellation at narrow window width.
