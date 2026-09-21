# Battle POC — As-built log

> Running record of the world's implementation. Survives across milestones. This is an AI / handoff reference; the GDD and regression documents remain the user-facing records.

## Current state (by system)

| System | Built | Where (key files) | Notes / gotchas |
|---|---|---|---|
| Battle session | `@Component` | `RootDesk/MyDesk/Combat/BattleSession.mlua` | Server-authoritative Issue #3 session; fixed one player Tank versus one enemy Assault, with phase/result snapshot and single-result guard. |
| Battle unit | `@Component` | `RootDesk/MyDesk/Combat/BattleUnit.mlua` | Retargets every 0.5s, moves with `MovementComponent`, branches Tank contact from Assault attack, applies death hold and post-result stop. |
| Tank contact attack | `@Component` / `AttackComponent` | `RootDesk/MyDesk/Combat/TankContactAttack.mlua` | Native `AttackFrom` → `Hit` path; fixed 40 damage, independent 2.0s per-target cooldown, enemy-only 0.8 knockback queue, and no contact SFX/VFX. |
| Tank presentation | `@Component` | `RootDesk/MyDesk/Combat/TankPresentation.mlua` | Client-side Tank stand/move/hit/die AnimationClip switching plus the provided Tank hit/death SFX. Tank has no attack animation. |
| Assault attack | `@Component` / `AttackComponent` | `RootDesk/MyDesk/Combat/AssaultAttack.mlua` | Existing native Attack→Hit path with 0.7s interval, 0.18s impact delay, fixed 35 damage, and faction filtering. |
| Unit model | `.model` | `RootDesk/MyDesk/Models/Monsters/BattleUnit.model` | `KinematicbodyComponent` for `RectTile`; placeholder `SpriteRUID` remains the model contract, while Tank presentation applies supplied clips at runtime. |
| Battle map | `.map` | `map/map01.map` | `TileMapMode=1` (`RectTile`); map root owns only `script.BattleSession` for the active Issue #3 runtime. |
| DefaultPlayer / camera | runtime logic | `BattleSession.mlua` (`DisableDefaultPlayer`) | DefaultPlayer remains visible while controller, body, collision, trigger, hit, and target participation are disabled; camera is centered, zoomed out, and offset down to show the full field. |
| Battle UI | `.ui` / parked adapter | `ui/BattleGroup.ui`, `RootDesk/MyDesk/Combat/BattleDeploymentInput.mlua` | Existing deployment UI is retained for Phase 2 but hidden and not attached to `map01` during Issue #3. |
| Regression contract | Node test | `tests/battle_session_contract.test.cjs` | Covers RectTile/model invariants, fixed Tank/Assault spawn, Tank rules, supplied resource bindings, hidden parked UI, and no deployment runtime binding. |

## Standing issues & handoff rules (update in place — never re-append)

| Issue / rule | Workaround / rule | Count | First → last seen |
|---|---|---:|---|
| Maker workspace cache after script/model edits | Run Maker `refresh` before Build Console and Play verification. | 2 | 09-21 → 09-21 |
| Maker build console retains informational LIA diagnostics | Treat `Info` LIA entries as static-analysis notices; confirm no error-level build entries and verify the runtime log/snapshot. | 1 | 09-21 → 09-21 |

## Log (entries: the ACTIVE milestone only + ONE summary per completed milestone)

### 2026-09-21 Issue #3 Tank slice

- Rebased the active runtime to the ticket scope: one fixed player Tank versus one fixed enemy Assault, auto-entering `BATTLE`; the Phase 2 deployment UI remains parked and hidden.
- Added `TankContactAttack` with fixed 500 HP / 1.1 movement / 40 contact damage / independent 2.0s target cooldown. Contact uses the native `AttackComponent` → `HitEvent` path and can damage every overlapping enemy.
- Added queued enemy-only 0.8 world-unit knockback with RectTile boundary clamping. The Tank position is never displaced by its own contact attack, and no stun or contact attack SFX/VFX path is used.
- Applied the supplied Tank stand/move/hit/die AnimationClip RUIDs and hit/death sound RUIDs through `TankPresentation`. Tank hit and death sounds are separate from the Tank's silent contact attack.
- Adjusted the fixed camera to zoom out and offset downward so the lower map area remains visible.
- Node contract tests pass. Maker refresh/build produced no error-level entries. Maker Play produced `BATTLE started: PLAYER tank vs ENEMY assault`, `RESULT=WIN`, and a live multi-target contact check showed both overlapping enemies taking the same fixed damage and being clamped at the arena boundary.

### 2026-09-21 Phase 1 complete (summary)

- Completed the one-to-one Assault automatic battle vertical slice for M1.
- `map01` stays `RectTile`; units use `KinematicbodyComponent` and frame-based movement.
- Native Attack→Hit, retargeting, cooldown, impact delay, fixed damage, death immunity, and WIN/LOSE/DRAW boundary were implemented.
- DefaultPlayer remains visible but cannot move, collide, be targeted, or affect the result.
