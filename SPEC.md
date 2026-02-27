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

## Non-Goals
- Perfect lock/sleep detection in all macOS edge cases.
- Zero transient toggle failures during wake/login timing windows.
