# Windows tray lifecycle

New empty vaults default to keeping GameVault in the tray when the window
closes. Older vaults without the setting retain the previous exit behavior.
Change it under Settings, General. Once hidden, activate the tray icon or
select Open GameVault to restore the same window. Exit GameVault finalizes
tracking, waits for pending Steam sidecar writes and releases the vault lock.

GameVaultApp distinguishes window close from explicit Exit. The Windows
FlutterWindow runner registers the notification icon before hiding and
restores the existing HWND, so opening from the tray creates no process.
Explorer restart re-registers the icon or restores the window if registration
fails. The normal exit path remains available if the shell rejects the icon.
The hidden window and its raw-input registrations stay alive. Duplicate exit
requests share one shutdown future.

Lifecycle tests exercise settings compatibility, hidden session accounting
with synthetic samples, and waiting for one shutdown before destroying the
window. Steam sidecar tests cover pending account confirmations and accepted
baselines. Native input tests cover signal processing separately. Physical
controller activity while hidden still requires gameplay acceptance.

If the final vault save fails, the controller keeps the finalized session
pending and retains the vault lock. The app reopens with the storage error
and a Retry Save and Exit button. Tracking stays stopped while the user
addresses the error. The tray regression injects a failed write and verifies
that retry submits the same session and then closes the window.
