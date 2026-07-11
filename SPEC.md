# Merihari SPEC

## Goal
Merihari automatically enforces grayscale during a configured time window and color outside that window, while keeping behavior resilient across sleep/lock/wake transitions.

## Inputs
- Time window from `~/.config/merihari/config`
  - `START=HHMM`
  - `END=HHMM`
- Current grayscale setting (system accessibility state)
- Session active/inactive signal (best-effort)

## Core Behavior
Run `apply_state()` every 60 seconds.

When session is active:
1. If current time is in-window and grayscale is OFF, toggle ON.
2. If current time is out-of-window and grayscale is ON, toggle OFF.
3. If current time is in-window, send a notification.

When session is inactive:
- Skip toggle and notification.

## Event Behavior
On session activation-related events (wake/unlock/become-active):
1. Flush outstanding notifications.
2. Schedule one delayed `apply_state()` run (debounced).

## Failure Behavior
- Toggle failures are expected to happen transiently (e.g., lock/wake transition).
- Do not block future runs after a failure.
- Retry naturally on next periodic cycle or next activation event.
- Keep failure logs sparse enough to avoid noise.

## Reliability Principles
- Prefer eventual correction over perfect one-shot transitions.
- Keep runtime timer/watcher references alive for the lifetime of the config.
- Avoid complex gating that can stall all future checks.

## Screen Topology Resync
When an external display is connected/disconnected (screen topology change), macOS may not apply the color filter consistently across all displays.

On topology change (debounced by 2 seconds):
1. Skip if session is locked/asleep (`screen_resync_allowed` flag).
2. Skip if within cooldown period (20 seconds since last resync).
3. If the current filter state already matches the desired state, double-toggle (off-on or on-off-on) to force macOS to refresh the filter across all displays.
4. If the state is wrong, single-toggle to correct it.
5. After resync settles, run a normal `apply_state()` for verification.

The `screen_resync_allowed` flag is set to `false` on lock/sleep events and `true` on unlock/activation events, preventing resync attempts during inactive sessions.

## Non-Goals
- Perfect lock/sleep detection in all macOS edge cases.
- Zero transient toggle failures during wake/login timing windows.
