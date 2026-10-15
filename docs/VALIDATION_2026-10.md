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
