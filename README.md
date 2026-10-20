**October 19 · local 0.5.4:** Nearly Nothing refinement: softer shared glass and controls, compact fit review and paired Light/Dark. Local package installed; visual checks do not imply fresh audio, device or network acceptance. [Evidence and limits](../NeroNook/reports/nearly-nothing-refinement-2026-10-18/README.md). No public update.

**October 18 · local 0.5.3 installed:** shared glass, paired Light/Dark, independent bundled presence/particle artwork and component motion. Saved connection/settings remain scoped to this plugin. [Rollout evidence and limits](../NeroNook/reports/redesign-ember-2026-10-18/README.md). No public release.

**October 17 · local 0.5.2:** fixed compact-stage control/status overlap, checked Mouse/Keyboard in the actual Nook and confirmed unchanged DPI through OpenLogi read-back. [Evidence and limits](reports/redesign-live-2026-10-17/README.md). No publication.

**October 14 · 0.5.1 installed:** Easy-Switch observation and generic channel exports are available with the matching OpenLogi host-event API. Existing mouse/keyboard controls support both the older protocol-32 connection and the current API. Watching defaults Off. [Setup and limitations](EASY-SWITCH.md). Physical source-link acceptance remains pending.

# Logitech Module for NeroNook

Independent native macOS plugin, version 0.5.2. Uses the installed OpenLogi application and its agent to read mouse and keyboard status and apply temporary DPI or SmartShift adjustments. NeroNook remains usable without this module, and the module builds without NeroNook source.

## Included

- Permanent Mouse and Keyboard tabs within the 16:9 module stage, with original MX Master 3S / MX Keys S for Mac illustrations, live battery and connection status. Other models receive generic artwork.
- Device selection directly in the Nook and in the module window, with automatic refresh and a separately remembered selection for each tab. Keyboard view includes battery power state and an OpenLogi shortcut for key mappings.
- Controls directly in the Nook and the separate window for advertised DPI values and presets, separate wheel mode and sensitivity changes, and explicit apply/read-back results.
- Persistent exact device and OpenLogi application selection; unavailable devices cannot silently retarget another device.
- Shared SDK actions `read_status`, `set_dpi` and `set_wheel_mode`, plus a status channel and opt-in keyboard connection/battery event channel. Device-changing actions require host review and an exact device ID.
- Bounded background CLI execution, no shell evaluation, no automatic write retry, disabled unavailable controls, and independent plugin storage.

OpenLogi owns HID, Input Monitoring/Accessibility permissions, saved profiles, gestures and button mappings. The OpenLogi buttons open its application; these functions are not reimplemented here. The module does not import its configuration files or proprietary images.

## Requirements and installation

macOS 14+, NeroNook with actions/custom views (0.28.1 verified), and a matching
OpenLogi CLI/agent **protocol 32** build from
[OpenLogi PR #1563](https://github.com/AprilNEA/OpenLogi/pull/1563). The installed
integration is based on 0.8.6. The latest official release checked on October 14
is [v0.8.13](https://github.com/AprilNEA/OpenLogi/releases/tag/v0.8.13); its newer
`api`/IPC contract needs a separate adapter and matched agent qualification.
Updating OpenLogi alone does not make it a compatible replacement for this
connection. No OpenLogi executable is distributed in this plugin.

Build with `swift test` and `bash scripts/package.sh`. Set `NERONOOK_SIGNING_IDENTITY` for a stable development signature. Install `build/Logitech Module.app` through NeroNook Settings → Modules → Install or Update Plugin…. Then choose Logitech in the per-monitor selector and choose Mouse or Keyboard. Connection details are behind the gear, not a tab. The app can also be opened independently for settings and diagnostics.

Configuration is private to `~/Library/Application Support/NeroNookPlugins/cafe.nero.plugin.logitech/settings.json`. Changes are temporary and may be replaced by OpenLogi's saved profiles. If a write fails or times out, refresh before trying again.

## Validation

`swift test` exercises decoding, compatibility, offline/ambiguous targeting, supported DPI, read-back mismatch, partial wheel arguments, literal subprocess arguments, legacy-selection migration, per-tab selection, missing remembered devices and stale cross-tab targets. `python3 scripts/test-protocol.py` performs a read-only live host-protocol handshake and rejects an invalid action; it never changes a mouse setting. Physical-device acceptance is recorded in STATUS.md.

The shared SDK is vendored from NeroNook 0.23.0; exact file hashes are recorded in `SDK-SNAPSHOT.json`. Both Nook tabs and the native window render the same plugin-owned assets through `PluginWebSurface`. View sizing follows the available width and height to keep controls inside the host stage. No module depends on the host checkout or another module. Ark and Weather remain standalone plugins with no companion application dependency.

Keyboard status and opt-in connection/battery events are available in 0.4.0.
[Watch and workflow setup](KEYBOARD-EVENTS.md). The installed agent-backed CLI exposes no keyboard-setting commands. Remapping and profiles remain in OpenLogi; backlight, Fn lock and Easy-Switch are not controllable through this integration. Mouse actions reject non-pointer targets before sending a settings request.

## Artwork

`Resources/Views/devices` contains original SVG illustrations; no manufacturer or OpenLogi asset is bundled. The full keyboard drawing is reproducible with `python3 scripts/make-keyboard-art.py`. Product geometry and Mac layout references: [MX Master 3S](https://www.logitech.com/en-us/shop/p/mx-master-3s), [MX Keys S for Mac](https://www.logitech.com/en-us/shop/p/mx-keys-s-for-mac). These drawings are illustrations, not detected finish/color or previews of backlighting and mappings.
