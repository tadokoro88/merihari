# Merihari Test Cases

## Preconditions
- Hammerspoon running and config loaded.
- Accessibility/Automation permissions granted.
- Color Filters shortcut configured correctly.
- Config has valid `START` and `END` values.

## Cases

1. In-window enforcement ON
- Setup: time within window, grayscale currently OFF, session active.
- Expect: within 60s, grayscale toggles ON and `turned ON` log appears.

2. Out-of-window enforcement OFF
- Setup: time outside window, grayscale currently ON, session active.
- Expect: within 60s, grayscale toggles OFF and `turned OFF` log appears.

3. No-op when already correct (in-window)
- Setup: in-window, grayscale ON, session active.
- Expect: no toggle log; notification still sent by policy.

4. No-op when already correct (out-of-window)
- Setup: out-of-window, grayscale OFF, session active.
- Expect: no toggle log and no notification.

5. Skip while inactive
- Setup: locked/sleeping/inactive session.
- Expect: no toggle attempt, no new notification from periodic check.

6. Recovery on unlock/wake
- Setup: lock during window boundary crossing, then unlock.
- Expect: activation event flushes notifications and delayed apply runs; state converges within short time.

7. Missed activation event fallback
- Setup: assume unlock event missed.
- Expect: periodic 60s cycle eventually corrects state once session is considered active.

8. Transient failure handling
- Setup: force one or more temporary toggle failures.
- Expect: retries continue on next cycles/events; app eventually converges without manual restart.

9. Notification flush on activation
- Setup: accumulated notifications exist; trigger wake/unlock/become-active event.
- Expect: notifications are flushed immediately via activation path.

10. Long-run scheduler continuity
- Setup: leave app running across sleep/wake and several hours.
- Expect: debug timer logs continue; checks do not silently stop.
