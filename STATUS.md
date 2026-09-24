# Logitech module status

0.3.0 development preview, September 24, 2026.

## Device experience upgrade — 0.3.0

Installed independently through NeroNook's package review; host remains 0.23.0 with no runtime changes. Mouse and Keyboard are persistent separate panels, each with its own exact remembered device. Setup moved behind the gear. The Nook and standalone window share packaged custom HTML/SVG surfaces using the current public SDK. Original illustrations include an asymmetric MX Master 3S body, thumb wing, two metal wheels, and a full-size Mac keyboard with navigation cluster, number pad and Mac modifiers. Unknown device models get generic artwork.

DPI presets and all advertised DPI values, wheel mode and SmartShift sensitivity can be edited and applied directly in the Nook. Drafts do not write. Each write retains the exact mouse target, goes through OpenLogi and requires its read-back; no automatic retry. A missing remembered device stays unavailable. Existing keyboard selection migrated to its own tab without losing the mouse selection.

Validation: 15 Swift tests pass, including five migration/selection/unavailable/stale-target cases. Signed release build, strict signature verification and read-only protocol harness pass. The harness verifies separate custom panel identities, bounded view state, the single status line and invalid-action refusal. The SDK hashes are recorded in SDK-SNAPSHOT.json.

Live acceptance: installed native Mouse and Keyboard views were inspected. MX Master 3S reported 20% battery, 2000 DPI, Ratchet, sensitivity 20 and torque 0; MX Keys S for Mac reported charging, rising from 90% to 95% during the check. Native Apply DPI and Apply mode at the existing values returned confirmed read-back. The first Nook pass exposed sensitivity clipping due to the host header/tab budget; corrected viewport scaling to consider height as well as width, removed duplicate host action buttons, rebuilt and reinstalled. Final Odyssey Ark Nook screenshots show both tabs fully fitting. Apply sensitivity at existing 20 completed directly in the Nook with confirmed preservation of other fields. Ark selection was restored to Bambu Monitor and the temporary pin removed.

Keyboard backlight, Fn lock, Easy-Switch events/commands and in-module remapping remain unavailable. Source inspection found agent read_backlight IPC and a separate direct-HID diagnostic command, but the installed agent-backed control CLI has no keyboard-setting commands. The direct-HID path is intentionally not used. Latest official OpenLogi release is v0.8.7 (checked September 24); PR #1563 remains open. No OpenLogi build, hardware permissions, profiles or upstream PR were changed in this pass. Future upstream work must start by refreshing the release/base and preserving the existing PR.

Outstanding: reconnect/login/reboot acceptance, other hardware models, further artwork review, keyboard command/event integration and physical Stream Deck device-action routing.

## Earlier verification


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
