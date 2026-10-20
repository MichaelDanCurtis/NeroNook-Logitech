# Keyboard events for Automations

Logitech Module 0.4.0 offers connection and battery events from the selected
keyboard. OpenLogi still owns the device connection. Watching is off initially;
it collects no keys, typed text, application input or screen content.

1. In the Nook, choose Logitech → Keyboard and select your keyboard.
2. Set **Low at** to 1–50%, then choose **Watch changes**. The first healthy read
   establishes a quiet baseline. **Stop watching** stops event publication.
3. In Settings → Modules → Actions and connections, choose Automations. Allow
   **Logitech keyboard connection and battery changes** and only the actions
   your workflow needs. The installed example uses **Show a notice in the Nook**.
4. Open Automations and choose **Keyboard — low battery notice**. It filters
   `kind` for `low_battery`, then passes the event's message into a Nook notice.
   The portable graph is [in Examples](Examples/keyboard-low-battery.neroworkflow).
5. Choose **Arm events for this session**. Changing actions still need their
   normal review; event-triggered progress and review open in the Nook.
   **Disarm events** stops the workflow subscription. Restart does not rearm it.

Watching and arming are separate: a module can publish changes without any
workflow executing them. The example is installed disarmed, with watching off.

## Event contract

The generic `actions-v1` event channel is
`cafe.nero.plugin.logitech/keyboard_events`. It publishes `event_id`, exact
`device`, `kind`, `connected`, optional `battery` (0–100), `observed_at` (Unix
seconds), and a short `message`. Kinds are `connected`, `disconnected`,
`low_battery` and `battery_recovered`. Each event has a unique request ID matching
`event_id`. The host contains no Logitech-specific implementation.

Healthy inventory is sampled about every six seconds while watching. Unchanged
reads do not emit events. Battery recovery needs a five-point margin above the
chosen threshold. Unknown battery, source failure, a changed target/threshold,
restart or a gap over twenty seconds establishes another quiet baseline.
Unavailable OpenLogi does not pretend that the keyboard disconnected. No history
is replayed when arming or reconnecting. A busy host workflow does not queue
another event for later replay.

This connection does not expose Easy-Switch, Fn lock or backlight commands.
It cannot tell which host channel the keyboard selected or automatically map
that channel to an Ark source. Those need a separate upstream integration.

## Validation

23 module tests, the signed isolated inventory/event process fixture, and the
read-only live protocol harness pass. Host 0.28.1 passes 88 tests. Native Watch /
Stop watching, exact preference retention, explicit Arm / Disarm, recorded-input
simulation and both monitor layouts were inspected. The physical keyboard was
online at 100%; actual power-switch and battery-crossing acceptance remains open.
See [delivery evidence](reports/keyboard-events-2026-10-14/README.md).
