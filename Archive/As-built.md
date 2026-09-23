# Battle POC — As-built log

> Running record of the world's implementation. Survives across milestones. This is an AI / handoff reference; the GDD and regression documents remain the user-facing records.

## Current state (by system)

| System | Built | Where (key files) | Notes / gotchas |
|---|---|---|---|
| Battle session | `@Component` | `RootDesk/MyDesk/Combat/BattleSession.mlua` | Server-authoritative Issue #5 session; loads one strict `MonsterData` table, starts fixed six-versus-six (2 Tank + 2 Warrior + 2 Shooter per faction), batches damage, and guards the single result boundary. |
| Monster data | UserDataSet / CSV | `RootDesk/MyDesk/Combat/MonsterData.userdataset`, `RootDesk/MyDesk/Combat/MonsterData.csv` | Stable `MonsterId` rows hold names, types, combat values, impact frames, and explicit presentation RUIDs; missing, duplicate, invalid, or mismatched rows fail configuration. |
| Battle unit | `@Component` | `RootDesk/MyDesk/Combat/BattleUnit.mlua` | Retargets every 0.5s, moves with `MovementComponent`, branches Tank contact from Assault/Shooter attack, carries synced `MonsterId`/name, applies hit stop, death hold, and post-result stop. |
| Tank contact attack | `@Component` / `AttackComponent` | `RootDesk/MyDesk/Combat/TankContactAttack.mlua` | Native `AttackFrom` → `Hit` path; fixed 40 damage, independent 2.0s per-target cooldown, enemy-only 0.8 knockback queue; presentation owns attack SFX while collision SFX/VFX remain unused. |
| Tank presentation | `@Component` | `RootDesk/MyDesk/Combat/TankPresentation.mlua` | Client-side Tank stand/move/hit/die AnimationClip switching plus attack/onhit/die SFX hooks. Tank has no attack animation. |
| Shooter presentation | `@Component` | `RootDesk/MyDesk/Combat/ShooterPresentation.mlua` | Client-side attack/onhit/die SFX hooks driven by synced attack and damage serials. |
| Hit effect presentation | `@Component` | `RootDesk/MyDesk/Combat/BattleHitEffectPresentation.mlua` | Client-side attached hit effect; the attacker's RUID is resolved on the server and rendered on the defender entity. |
| Assault attack | `@Component` / `AttackComponent` | `RootDesk/MyDesk/Combat/AssaultAttack.mlua` | Existing native Attack→Hit path with 0.7s interval, 0.18s impact delay, fixed 35 damage, and faction filtering. |
| Unit model | `.model` | `RootDesk/MyDesk/Models/Monsters/BattleUnit.model` | `KinematicbodyComponent` for `RectTile`; placeholder `SpriteRUID` remains the model contract, while Tank presentation applies supplied clips at runtime. |
| Battle map | `.map` | `map/map01.map` | `TileMapMode=1` (`RectTile`); map root owns only `script.BattleSession` for the active Issue #5 runtime. |
| DefaultPlayer / camera | runtime logic | `BattleSession.mlua` (`DisableDefaultPlayer`) | DefaultPlayer remains visible while controller, body, collision, trigger, hit, and target participation are disabled; camera is centered, zoomed out, and offset down to show the full field. |
| Battle UI | `.ui` / parked adapter | `ui/BattleGroup.ui`, `RootDesk/MyDesk/Combat/BattleDeploymentInput.mlua` | Existing deployment UI remains parked and hidden; Issue #5 starts without deployment input or result UI. |
| Regression contract | Node contract + Maker runtime probes | `tests/battle_session_contract.test.cjs`, `tests/six_vs_six_runtime_probe.lua` | Covers RectTile/model invariants, strict data loading, fixed six-versus-six spawn, target retention/reacquisition, no blocking/pushing, Win/Lose/Draw, and terminal result stop. |

## Standing issues & handoff rules (update in place — never re-append)

| Issue / rule | Workaround / rule | Count | First → last seen |
|---|---|---:|---|
| Maker workspace cache after script/model edits | Run Maker `refresh` before Build Console and Play verification. | 2 | 09-21 → 09-21 |
| Maker build console retains informational LIA diagnostics | Treat `Info` LIA entries as static-analysis notices; confirm no error-level build entries and verify the runtime log/snapshot. | 1 | 09-21 → 09-21 |

## Log (entries: the ACTIVE milestone only + ONE summary per completed milestone)

### 2026-09-23 Issue #5 mixed six-versus-six feasibility

- Added the authoritative `MonsterData` UserDataSet/CSV with three stable rows: `monster_tank`, `monster_warrior`, and `monster_shooter`. Combat values and attack impact timing are read from the row; impact frames convert through the shared 60 FPS timing rule.
- Replaced the old fixed one-versus-one startup with a fixed six-versus-six roster: two Tank, two Warrior, and two Shooter per faction. Player and enemy references share the same `MonsterId` rows; enemy positions remain session settings and no formation dataset was added.
- Added strict configuration failures for unavailable columns, missing/duplicate IDs, invalid types, invalid required numbers, missing configured IDs, and failed component/adapter setup. Snapshots now expose MonsterId and editable MonsterName.
- Added the Maker high-level probe for equal-distance target retention, dead-target reacquisition, crowd movement without blocking/pushing, Win/Lose/Draw classification, and one-way RESULT stop. Node contract is 9/9; Maker build has no error-level entries; runtime probe ends with `[M1][SixVsSixProbe] PASS`.

### 2026-09-21 Issue #3 Tank slice

- Rebased the active runtime to the ticket scope: one fixed player Tank versus one fixed enemy Assault, auto-entering `BATTLE`; the Phase 2 deployment UI remains parked and hidden.
- Added `TankContactAttack` with fixed 500 HP / 1.1 movement / 40 contact damage / independent 2.0s target cooldown. Contact uses the native `AttackComponent` → `HitEvent` path and can damage every overlapping enemy.
- Added queued enemy-only 0.8 world-unit knockback with RectTile boundary clamping. The Tank position is never displaced by its own contact attack; collision SFX/VFX remain unused while the presentation layer owns attack SFX.
- Added a 0.2s server-side hit stop after each resolved non-lethal HitEvent; the damaged unit remains in place before resuming targeting and movement.
- Applied the supplied Tank stand/move/hit/die AnimationClip RUIDs and onhit/die sound RUIDs through `TankPresentation`; added attack sound and Shooter attack/onhit/die sound hooks with `TBD` placeholders where RUIDs are not yet supplied.
- Adjusted the fixed camera to zoom out and offset downward so the lower map area remains visible.
- Node contract tests pass. Maker refresh/build produced no error-level entries. The Maker runtime probe passed live multi-target contact, independent cooldown, 0.2s hit stop, no Tank recoil or stun, enemy-only boundary-clamped knockback, and result-stop checks; the normal Play run produced `BATTLE started: PLAYER tank vs ENEMY assault` and `RESULT=WIN`.

### 2026-09-21 Phase 1 complete (summary)

- Completed the one-to-one Assault automatic battle vertical slice for M1.
- `map01` stays `RectTile`; units use `KinematicbodyComponent` and frame-based movement.
- Native Attack→Hit, retargeting, cooldown, impact delay, fixed damage, death immunity, and WIN/LOSE/DRAW boundary were implemented.
- DefaultPlayer remains visible but cannot move, collide, be targeted, or affect the result.
