# Stabilization validation

V2.0: Flutter analysis passed; all 53 existing Flutter tests passed. Standalone native parser tests cover four DualSense report layouts, neutral input, drift boundary, both stick directions, triggers, all face/shoulder buttons, D-pad and malformed reports.

Keyboard/mouse GetLastInputInfo and XInput sampling are retained. Raw Input only registers gamepads, filters Sony vendor 054c / standard DualSense product 0ce6, records only the latest meaningful activity timestamp and writes no input logs. No output/feature reports are sent. Real Bluetooth gameplay and Steam Input on/off remain user acceptance tests.

Scrolling: removed no-op controller notifications and synchronous image existence probes; bounded artwork decode width. No frame pacing override or engine upgrade was introduced. 180 Hz hardware frame timings have not been measured.

HLTB Explorer is deferred: the existing adapter accesses website search/init and can inspect public script files to discover changed endpoints. This is not a documented, authorized public API. No live HLTB requests were performed during this work. Ziff Davis terms prohibit automated extraction except as permitted; the exact site-specific authorization remains unconfirmed. Existing behavior is left unchanged as requested, but public distribution is not cleared.

References reviewed 2026-10-15:
- https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input
- https://github.com/nondebug/dualsense (protocol documentation; no code copied)
- https://github.com/torvalds/linux/blob/master/drivers/hid/hid-playstation.c (protocol reference; no GPL driver code copied)
- https://www.ziffdavis.com/terms-of-use

## V2.1
Flutter static analysis passed and the full 61-test suite passed after the final sidebar palette adjustment. Added tests cover backward-compatible settings defaults, malformed new fields, close/reopen persistence, no-op monitoring notifications, contrast for presets/extreme custom colors in both modes, metadata version display, three profile sizes at three desktop widths, artwork zoom/reset, Escape/Close and canceling a custom-color preview.

An isolated copy of the current V2 vault successfully loaded, saved the new appearance fields and reopened. All game records and complete historical session JSON remained identical. Originals were not opened for writing.

The native Windows fixture smoke test passed with metadata 2.1.0+3: ShellExecute launch, process detection/termination, one-process/one-game association, missing-executable rejection and session persistence. It recorded 10 seconds. Foreground focus was not observed in the automation environment, so this is not proof of real-game focus behavior. Existing automated tracker tests cover focus grace/idle accounting. Physical keyboard/mouse/XInput/controller gameplay and Steam URI launch remain acceptance checks.

The first package privacy scan found a build-directory path in Dart AOT debug metadata. Distribution builds use --split-debug-info and keep symbols private. Final packages must pass the package path guard. No application credentials are required or bundled. No personal screenshots are included.

Resumed 2026-10-16: the final privacy build uses a temporary generated package alias. Splitting symbols and obfuscation alone retained a generated plugin path; the SDK's assemble filesystem mapping did not rewrite this generated URI. No obfuscation is needed with the package alias. The private symbols must be retained for debugging and excluded from distribution. HLTB Explorer is explicitly postponed by the owner. Existing integration permissions still require resolution before public distribution.

Extracted-package testing uncovered a normal-close crash (0xc000041d/0xc0000005 in Flutter) after the window-manager plugin posted WM_QUIT. The runner now explicitly destroys its derived window and engine before CoUninitialize. The isolated startup/close check subsequently exited with code 0. The defect is fixed in both prepared release versions, not accepted as a successful close. Earlier draft packages are retained privately, not upload candidates.
