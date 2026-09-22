# Logitech module status

0.1.0 development preview, September 22, 2026.

## Verified

- Independent Swift release build, eight bridge tests, package signature verification.
- Read-only SDK harness: handshake, 16:9 snapshot, single-line activity, and invalid device action rejected without a write.
- Installed and updated through NeroNook's signed-package review. Host reports Running, visible on both displays; built-in display selection and native dashboard inspected.
- Separate controls window visually inspected. Missing device disables apply controls and shows unavailable settings.

## Hardware acceptance pending

A local OpenLogi source build at `c65f4d7bf31da8f2e48d6d129ee2b315c330567d` is installed at `/Applications/OpenLogi.app` for protocol 32. The official 0.8.6 app and configuration were backed up before replacement. This is a local integration build, not an official upstream release.

The matching agent responds with protocol 32 / Ready but an empty device list. macOS permission renewal is pending for the locally signed OpenLogi Agent. Accessibility was reported unapproved by OpenLogi. Input Monitoring and actual device discovery must be checked after the owner renews permissions. No physical mouse setting was changed during this module acceptance.

The agent was started directly after its existing login-item registration retained the official signing identity. Persistent login-item registration and restart/reboot recovery must also be verified; a running process is not proof of durable startup.

Remaining gates: real mouse inventory and settings, DPI apply/read-back, partial wheel apply/read-back preserving unspecified fields, reconnect and login-item recovery. Button remapping, gestures and per-app profiles stay in OpenLogi for this first version. SDK actions are implemented, but physical Stream Deck invocation remains a separate acceptance step.
