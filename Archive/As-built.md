# Battle POC — As-built log

> Running record of the world's implementation. Survives across milestones. This is an AI / handoff reference; the GDD and regression documents remain the user-facing records.

## Current state (by system)

| System | Built | Where (key files) | Notes / gotchas |
|---|---|---|---|
| Battle session | `@Component` | `RootDesk/MyDesk/Combat/BattleSession.mlua` | Server-authoritative M1 session; fixed one player Assault versus one enemy Assault; phase/result snapshot and single-result guard. |
| Battle unit | `@Component` | `RootDesk/MyDesk/Combat/BattleUnit.mlua` | Retargets every 0.5s, moves with `MovementComponent`, stops at range, applies death hold and post-result stop. |
| Assault attack | `@Component` / `AttackComponent` | `RootDesk/MyDesk/Combat/AssaultAttack.mlua` | Native Attack→Hit path with 0.7s interval, 0.18s impact delay, fixed 35 damage, and faction filtering. |
| Unit model | `.model` | `RootDesk/MyDesk/Models/Monsters/BattleUnit.model` | `KinematicbodyComponent` for `RectTile`; placeholder non-empty `SpriteRUID` is retained for the MSW platform contract. Human combat assets are not integrated. |
| Battle map | `.map` | `map/map01.map` | `TileMapMode=1` (`RectTile`); map root owns `script.BattleSession`. |
| DefaultPlayer / camera | runtime logic | `BattleSession.mlua` (`DisableDefaultPlayer`) | DefaultPlayer remains visible while controller, body, collision, trigger, hit, and target participation are disabled; camera is fixed for the full field. |
| Regression contract | Node test | `tests/battle_session_contract.test.cjs` | Covers snapshot, result, stop, HitEvent boundary, and death immunity contracts. |

## Standing issues & handoff rules   (update in place — never re-append)

| Issue / rule | Workaround / rule | Count | First → last seen |
|---|---|---:|---|
| Maker workspace cache after script/model edits | Run Maker `refresh` before Build Console and Play verification. | 1 | 09-21 → 09-21 |

## Log   (entries: the ACTIVE milestone only + ONE summary per completed milestone)

### 2026-09-21 Phase 1 complete

- Completed the one-to-one Assault automatic battle vertical slice for M1.
- `map01` stays `RectTile`; units use `KinematicbodyComponent` and frame-based movement.
- Native Attack→Hit, retargeting, cooldown, impact delay, fixed damage, death immunity, and WIN/LOSE/DRAW boundary are implemented.
- DefaultPlayer remains visible but cannot move, collide, be targeted, or affect the result.
- Node contract tests, Maker Play runtime checks, and user visual/interaction verification passed.
- Phase 2 still owns deployment input, one-to-six player formation, fixed six-enemy formation, and battle locking.
