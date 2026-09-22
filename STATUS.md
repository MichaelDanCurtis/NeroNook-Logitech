# Logitech module status

0.2.0 development preview, September 22, 2026.

## Verified

- Independent Swift release build, ten bridge tests, package signature verification.
- Read-only SDK harness: handshake, 16:9 snapshot, single-line activity, and invalid device action rejected without a write.
- Installed and updated through NeroNook's signed-package review. Host reports Running, visible on both displays; built-in display selection and native dashboard inspected.
- Separate controls window visually inspected. Missing device disables apply controls and shows unavailable settings.

## Live hardware acceptance — repaired September 22

OpenLogi's agent log identified Input Monitoring denial. The owner renewed the grant. The local build shared the official 0.8.6 version string, leaving OpenLogi's registration-version marker stale across the signing change. Preserved that marker as a timestamped backup, relaunched the GUI to let its own SMAppService code re-register, stopped the old unmanaged agent and started the registered service. launchd now reports Running with the installed development TeamIdentifier 2GFVXB3249 and a supervised agent. Full reboot acceptance remains untested.

Actual agent inventory now reports the MX Master 3S and MX Keys S for Mac online. The module correctly selects the mouse. Fixed a separate battery decoding bug: OpenLogi emits `percentage`, whereas the first module and its fixture incorrectly used `percent`. The corrected test uses the actual field name.

Installed 0.1.1 and verified the native controls show 30% battery, 2,000 DPI and tactile mode. Clicked Apply DPI at the existing 2000 value: the module displayed "Read-back confirmed." Clicked Apply mode at existing Ratchet: it displayed "Other fields were preserved." The CLI also confirmed same-value DPI, mode and threshold writes with threshold 20 and torque 0 preserved. No test intentionally changed the user's settings. Eight bridge tests and the read-only SDK harness pass.

The matching protocol 32 OpenLogi source build is c65f4d7bf31da8f2e48d6d129ee2b315c330567d. Official 0.8.6 and configuration backups remain preserved. This is a local integration build, not an official upstream release. Button mappings, gestures and profiles remain in OpenLogi. Physical Stream Deck invocation, sleep/device reconnect and a full login/reboot remain separate acceptance steps.


## Keyboard support — 0.2.0

Installed and verified the MX Keys S for Mac dashboard on Odyssey Ark: Connected, 45% battery, and single-line Keyboard status. Native device window shows power state Discharging and no mouse-only controls. Switched to MX Master 3S and verified existing 2000 DPI/free-spin controls return, then selected the keyboard again. No hardware settings were changed during keyboard acceptance.

Ten tests pass, including keyboard selection, unknown battery, unavailable-device refusal, and rejection of DPI/wheel writes to keyboard targets before sending settings commands. Signed release packaging and the SDK handshake/invalid-action harness pass. Keyboard content uses its own original vector diagram within the shared 16:9 interface. Device selection was retained through the final package update and persists in plugin-owned settings; no OpenLogi rebuild or new permissions were needed.

The current CLI supports keyboard inventory only; key mappings open OpenLogi. Backlight/Fn lock/Easy-Switch controls and in-module remapping are not implemented.
