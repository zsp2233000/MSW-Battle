# Battle verification

Run the local contract suite from the repository root:

```powershell
node --test tests/*.test.cjs
```

Runtime probes use the Maker server or client runtime, native `AttackComponent` / `HitEvent`, and `BattleSession`; JavaScript does not recreate combat.

## Maker runtime procedure

For every runtime probe, use a fresh Play test. Stop, clear logs, Refresh, read build logs, then Play and wait until `map01` reaches `DEPLOYMENT`. Pass the entire Lua file to `maker_execute_script` with `context=server_main`, except the client probes identified below. A successful script dispatch is not a passing test: read normal logs until that probe's final `PASS` or `FAILURES=...` marker appears. Inspect all build and normal Error / Warning entries. The only expected diagnostic in this suite is the single `unsupported attack profile` message intentionally caused by the first invalid-profile case in `attack_execution_runtime_probe.lua`. Stop after each probe.

| Probe | Runtime role | Clock / evidence |
|---|---|---|
| `deployment_runtime_probe.lua` | Formal deployment bounds, capacity, removal, and registration | Production `TryDeployMonster` / removal commands; server side |
| `attack_execution_runtime_probe.lua` | Native attacks, accepted-hit policy, cancellation, reconfiguration, death, hit stop, and result | Owns and releases its manual clock; includes a later native HitEvent delivered to a dead defender while BATTLE remains active, and the one intentional unsupported-profile diagnostic |
| `attack_clock_runtime_probe.lua` | Manual-clock ownership, automatic/manual exclusion, and restored automatic attacks | Owns and releases its manual clock; confirm the release paths in logs |
| `tank_contact_runtime_probe.lua` | Native tank contact, per-target cooldown, lethal contact, and knockback boundaries | Manual clock for hit sequencing; real Maker frames for movement / knockback evidence |
| `shooter_runtime_probe.lua` | Native shooter movement, impact timing, hitscan, and natural result | Manual clock for attack timing; real Maker frames for movement evidence |
| `targeting_crowding_runtime_probe.lua` | Nearest-target selection, ties, invalid/dead retargeting, overlap, and natural WIN / LOSE / DRAW | Manual clock only for acquisition assertions; real Maker frames for crowding, movement, and result stability |
| `six_vs_six_batch_outcome_probe.lua` | Native-hit WIN / LOSE, both same-batch DRAW hit orders, per-hit damage and sound serials, and terminal rejection | Owns its manual clock; uses `DriveAttack` / `AdvanceAttack` to produce native `HitEvent`s, then settles with one full `AdvanceForTest` step |
| `six_vs_six_runtime_probe.lua` | Six official deployments against the six fixed map enemies | Public state and natural registered roster; server side |
| `six_vs_six_full_battle_probe.lua` | Natural twelve-unit battle, result matching final alive counts, one RESULT, and terminal stability | Real Maker timers / frames; 45-second battle limit plus one second after RESULT |
| `controlled_scenario_runtime_probe.lua` | Maker-only controlled rosters, atomic input validation, clock ownership, scene replacement, and pending-hit isolation | Owns and releases a manual clock. Pending old-scene work comes from a native tank contact and is discarded by scene replacement. |
| `monster_catalog_identity_runtime_probe.lua` | Temporary catalog rename and duplicate TANK identity through `MonsterCatalog` and official deployment | No manual clock; fresh Play with temporary CSV; execute in `server_main` |
| `monster_catalog_restored_runtime_probe.lua` | Confirm the original formal catalog is loaded after the temporary fixture is removed | No manual clock; fresh Play after restore and Refresh; execute in `server_main` |
| `deployment_ui_runtime_probe.lua` | Connected named-card / start events, deployment removal and input locking | `client`; final `[M1][DeploymentUIProbe] PASS` |
| `six_vs_six_ui_runtime_probe.lua` | Connected named-card selection, repeated deployment, capacity, natural six-versus-six result UI, and full death playback | `client`; observes native renderer events; final `[VRF][SixVsSixUI] PASS` |
| `monster_catalog_validation_runtime_probe.lua` | Real catalog values, missing / duplicate ID, invalid type / numeric cells, blank impact frame, rename and shared resources | `server_main`; public `MonsterCatalog:ParseRow` returns validation diagnostics without logging expected invalid inputs as errors; final `[VRF][CatalogValidation] PASS` |
| `monster_catalog_variant_runtime_probe.lua` | Independently configured same-type identities, shared resources and same-ID opposing factions using native contact hits | `server_main` with the numeric variant fixture below; owns and releases its manual clock; final `[VRF][CatalogVariant] PASS` |
| `monster_catalog_variant_ui_runtime_probe.lua` | Renamed original and same-type variant produce separate named cards bound to their IDs | `client` with the numeric variant fixture; fresh Play before execution; final `[VRF][VariantUI] PASS` |

Hand-clock probes must acquire `BeginManualSimulation` before preparing a scene and release only the clock they acquired, including exception paths. They may call the existing unit attack interface. They must not inspect `session._T`, write session state or counts, spawn through internal methods, remove roster indexes, call damage / knockback queues or settlement helpers, or force a result. A complete `AdvanceForTest` / `StepSimulation` owns damage resolution and result settlement. Manual clock time does not advance native Body movement; prove movement, contact, crowding, and knockback with Maker frames.

## Temporary MonsterData identity case

Only the dedicated identity / independent-stat cases change `RootDesk/MyDesk/Data/MonsterData.csv`. Run them as a guarded transaction using `withTemporaryMonsterCsv` from `monster_catalog_csv_fixture.cjs`:

1. Stop Maker and copy the original CSV bytes to a unique directory under the operating system temp directory. The guard records byte length and SHA-256, verifies the backup, and writes a temporary fixture with byte-checked output. The default fixture changes `monster_tank` to `RenamedTank` and adds a row cloned from the tank with only `MonsterId=probe_tank_variant` and `MonsterName=VariantTank` changed. For the independent-stat case, pass `variantStats: { MaxHp: 650, MoveSpeed: 0.7, AttackDamage: 25, AttackIntervalSeconds: 1.3, AttackRange: 0.8, ContactCooldownSeconds: 1.3 }`; original-row statistics and all resource cells remain unchanged.
2. Refresh, read build logs, start a new Play test, then execute the complete `monster_catalog_identity_runtime_probe.lua` in `server_main` for the default fixture. It queries the loaded catalog, compares the profile fields, checks the official options, and deploys both IDs through `TryDeployMonster`. For the independent-stat fixture, execute `monster_catalog_variant_runtime_probe.lua` in `server_main`, require PASS, then Stop and start a separate fresh Play test for `monster_catalog_variant_ui_runtime_probe.lua` in `client`. Require its PASS before leaving the fixture stage.
3. The guard requires Maker Stop, Refresh, and restored-catalog verification callbacks before it changes the CSV. When the probe succeeds, fails, throws, or receives a graceful SIGINT / SIGTERM / AbortSignal, it waits up to 30 seconds for an interrupted probe callback to settle, then awaits Maker Stop, gives the probe one more bounded chance to settle, restores the saved bytes, verifies byte equality and SHA-256, awaits Refresh, and runs the supplied restored-catalog verifier. Each Maker lifecycle callback has a 120-second timeout. Signal handlers remain active through the final Stop. If cancellation, logging, or a lifecycle callback times out or fails, the guard still attempts restoration and verification but retains the temp backup and reports incomplete cleanup with its path; it never reports that transaction as successful.
4. The restored verifier uses a fresh Play test and the complete `monster_catalog_restored_runtime_probe.lua` in `server_main`; require its final PASS, then Stop. It checks `monster_tank` is again named `Tank`, the temporary ID is absent, the option count is three, and the session is in formal deployment.

The helper takes Maker lifecycle callbacks so filesystem rollback and Maker Stop / Refresh / catalog verification use the same `finally` path. The temporary row, renamed name, backup, and manifest are not tracked or committed. Neither identity probe needs a manual clock or real movement frames.

`node tests/monster_catalog_fixture_driver.cjs` supplies the independent-stat fixture and a line-based bridge for an MCP orchestrator. Each JSON request has an increasing `id`, `request`, and `details`. Complete the actual Maker operation and require the runtime verdict before writing `{"id":<matching request id>,"ok":true}` to its stdin; report failures with the same ID, `ok:false`, and `error`. The `variant-probe` request covers both independent-stat probes above. `restored-probe` covers a fresh Play and `[M1][CatalogRestoreProbe] PASS`. The driver asks for Stop separately before installation, before restoration, and after restored verification. A cancelled probe rejects its pending request; a late acknowledgement with that probe's ID cannot acknowledge cleanup Stop. Overlapping requests are rejected. `[VRF][CatalogFixture] PASS` is emitted only after the complete guarded transaction succeeds.

## Regression evidence

After restoration, re-run `node --test tests/*.test.cjs`, `deployment_runtime_probe.lua`, and `six_vs_six_full_battle_probe.lua` in separate fresh Play tests. Keep the formal battle within 45 seconds, require exactly one legal RESULT, and wait one additional real second to verify HP, combat serials, target, position, and knockback state remain stable. Capture the restoration SHA-256, the restored-catalog PASS, and each runtime verdict before concluding the fixture is clean.

The probes assert observed HP, `DamageTakenSerial`, `OnHitSoundSerial`, `AttackSerial`, events, positions, and results. Source-string assertions remain for structural contracts only; they do not substitute for runtime evidence.

Issue #10's recorded Maker verdicts, map inventory, restoration hash and human verification boundary are in [BattlePOC-M1-Regression.md](../docs/BattlePOC-M1-Regression.md).
