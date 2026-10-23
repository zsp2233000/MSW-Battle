# Issue #38 verification — 2026-10-23

Spec: https://github.com/zsp2233000/MSW-Battle/issues/38
Branch: `feat/38-viewer-side-presentation`. Issue remains open; no push.

## Implementation and cleanup

Formal map-local `BattleView` owns viewer identity, mirrored presentation, enemy red bars, damage/effects and symmetric spectator avatars. Authoritative combat stays in the existing server session.
Formal visual/avatar models moved from Prototypes to Models/MapObjects.
The #36 prototype map, script and six prototype probes were removed. Maker Refresh removed its generated script metadata; metadata was not edited by hand.
The temporary Maker-wide manual-simulation hold was removed from BattleSession; that file has no final diff.
Historical #36 documentation and evidence are preserved.

## Visual evidence

- [Opening full HP](opening-full-hp.png) and [opposite viewer direction](swap-still-self-left.png): each viewer remains left, enemy right/red, symmetric inward-facing avatars.
- [Live damage](live-damage-numbers.png): living damaged bars, upright damage numbers and enemy crossing center.
- [Same monsters, hit effects and damage](same-monster-hit-effects.png): green/red ownership, native warrior hit effects attached to mapped targets and 35 damage numbers.
- [Natural draw](same-monster-natural-draw.png): same-monster 6v6 naturally ended DRAW/DRAW.
- [Natural result](result-away-lose.png) and [rematch result](rematch-result-away-lose.png): complementary results.

Screenshots were inspected through the image viewer, not inferred from flags.
The effect screenshot is a mid-battle capture, not the first-hit frame. No attack/damage/outcome was fabricated for it.

## Runtime verification

Maker was confirmed against formationlobby root UUID before testing; matchprobe TileMapMode=1 was read through MapBuilder.
The existing full-HP opening and side-swap captures preceded this continuation.
This continuation observed multiple naturally resolved 6v6 matches, including WIN/LOSE and DRAW/DRAW, with one terminal publication each.
After POC deletion, Refresh and Play restart, these formal matches completed without the temporary hold:

- `local-add5388177264be491228733f3dab125`: home WIN / away LOSE; RESULT_PASS; returned.
- `local-0a98695f3ee644d0a17b7e690a2aefde`: home WIN / away LOSE; RESULT_PASS; returned.

Both post-cleanup matches reported 6v6, stable terminal EventSerial=536, cleanup and RETURNED restored=true.
Client final probe confirmed lobby, visible authoritative player, and no viewer clones in lobby.
Main context final probe confirmed both users back in lobby, activeSlot=editSlot=1, pending=false, six saved units each; slots2–5 still empty/UNSAVED at revision0.
The local saved formation remains six warriors at revision6. Only the disposable virtual fixture was temporarily saved as six warriors for identical-monster effects evidence, then restored through the save API to six tanks (revision1 -> 3). No local saved formation was overwritten.

The updated swap probe rejects invocation after RESULT and restores identities outside pcall; the late post-cleanup invocation correctly reported SWAP_FAIL before acquiring the clock. This is not counted as a new swap PASS; actual opposite-direction evidence is the retained screenshot above.
One exploratory probe incorrectly read a nonexistent MonsterType field; that probe-only error was captured, and no such read was added to production. After the Play restart, no runtime Error entries were observed.
Final Maker state is edit mode.

## Checks and review

- `node --test tests/battle_view_contract.test.cjs`: 1/1 PASS.
- `git diff --check`: PASS.
- Full `node --test`: 25/29 pass; four failures also reproduced from an independent clean HEAD archive (24/28 pass before the new test).
  - stale CameraZoomPercent property expectation;
  - stale DeploymentMinDistance=0.6 source expectation;
  - existing terrain floor(-15,-8) expectation;
  - fixture assumes tank HP500 while current data is300.
- The shared camera contract now explicitly accounts for matchprobe zoom32/offset0; other maps retain their saved zoom60.
- Final build: zero errors, 114 diagnostics; warnings LWA1110 (IsPCPlatform deprecation) and LWA4013 (avatar selectors). Runtime avatar selector dependency warnings also remain.
- Parallel Standards/Spec review found no production defect. Probe findings were corrected: no persistent-data overwrite, unconditional identity/clock restoration, and dispatch is labeled DISPATCHED rather than PASS. Static review does not replace the runtime evidence above.

## Limits

PC Maker with a local client and a virtual peer, including viewer-identity exchange; no second physical client or cross-WorldInstance claim.
#31 cross-WorldInstance and #32–#34 race/save-failure/disconnect acceptance remain with their own issues.
Spectator Y=7.2 is the documented zoom32 display shortcut.

