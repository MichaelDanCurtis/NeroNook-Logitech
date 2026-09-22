# Logitech Module for NeroNook

Independent native macOS plugin, version 0.2.0. Uses the installed OpenLogi application and its agent to read mouse and keyboard status and apply temporary DPI or SmartShift adjustments. NeroNook remains usable without this module, and the module builds without NeroNook source.

## Included

- Separate 16:9 mouse and keyboard dashboards with original vector illustrations, live battery and connection status.
- Device selection directly in the Nook and in the module window, with automatic refresh and remembered selection. Keyboard view includes battery power state and an OpenLogi shortcut for key mappings.
- Native controls for advertised DPI values and presets, separate wheel mode and sensitivity changes, and explicit apply/read-back results.
- Persistent exact device and OpenLogi application selection; unavailable devices cannot silently retarget another device.
- Shared SDK actions `read_status`, `set_dpi` and `set_wheel_mode`, plus a status channel. Device-changing actions require host review and an exact device ID.
- Bounded background CLI execution, no shell evaluation, no automatic write retry, disabled unavailable controls, and independent plugin storage.

OpenLogi owns HID, Input Monitoring/Accessibility permissions, saved profiles, gestures and button mappings. The OpenLogi buttons open its application; these functions are not reimplemented here. The module does not import its configuration files or proprietary images.

## Requirements and installation

macOS 14+, NeroNook 0.12.0+, and a matching OpenLogi CLI/agent **protocol 32** build from [OpenLogi PR #1563](https://github.com/AprilNEA/OpenLogi/pull/1563). Official OpenLogi 0.8.6 uses protocol 31; this module cannot use that release unchanged. No OpenLogi executable is distributed in this plugin.

Build with `swift test` and `bash scripts/package.sh`. Set `NERONOOK_SIGNING_IDENTITY` for a stable development signature. Install `build/Logitech Module.app` through NeroNook Settings → Modules → Install or Update Plugin…. Then choose Logitech in the per-monitor selector and open Device controls. The app can also be opened independently for settings and diagnostics.

Configuration is private to `~/Library/Application Support/NeroNookPlugins/cafe.nero.plugin.logitech/settings.json`. Changes are temporary and may be replaced by OpenLogi's saved profiles. If a write fails or times out, refresh before trying again.

## Validation

`swift test` exercises decoding, compatibility, offline/ambiguous targeting, supported DPI, read-back mismatch, partial wheel arguments and literal subprocess arguments. `python3 scripts/test-protocol.py` performs a read-only live host-protocol handshake and rejects an invalid action; it never changes a mouse setting. Physical-device acceptance is recorded in STATUS.md.

The shared SDK snapshot is vendored from NeroNook commit `eaa9196b828309e01aaa798bfce820c83012181a` (0.12.0). No module depends on the host checkout or another module. Ark and Weather remain standalone plugins with no companion application dependency.

Keyboard support is status-only in 0.2.0. The installed agent-backed CLI exposes no keyboard-setting commands. Remapping and profiles remain in OpenLogi; backlight, Fn lock and Easy-Switch are not controllable through this integration. Mouse actions reject non-pointer targets before sending a settings request.
