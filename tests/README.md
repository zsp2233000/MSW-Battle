# Battle verification

Run the local contract suite from the repository root:

```powershell
node --test tests/*.test.cjs
```

Runtime probes use the Maker server runtime, native `AttackComponent` / `HitEvent`, and `BattleSession`; JavaScript does not recreate combat.

## Maker runtime procedure

For every runtime probe, use a fresh Play test. Stop, clear logs, Refresh, read build logs, then Play and wait until `map01` reaches `DEPLOYMENT`. Pass the entire Lua file to `maker_execute_script` with `context=server_main`. A successful script dispatch is not a passing test: read normal logs until that probe's final `[M1][...Probe] PASS` or `[M1][...Probe] FAILURES=...` marker appears. Inspect all build and normal Error / Warning entries. The only expected diagnostic in this suite is the single `unsupported attack profile` message intentionally caused by the first invalid-profile case in `attack_execution_runtime_probe.lua`. Stop after each probe.

| Probe | Runtime role | Clock / evidence |
|---|---|---|
| `deployment_runtime_probe.lua` | Formal deployment bounds, capacity, removal, and registration | Production `TryDeployMonster` / removal commands; server side |
| `attack_execution_runtime_probe.lua` | Native attacks, accepted-hit policy, cancellation, reconfiguration, death, hit stop, and result | Owns and releases its manual clock; includes the one intentional unsupported-profile diagnostic |
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

Hand-clock probes must acquire `BeginManualSimulation` before preparing a scene and release only the clock they acquired, including exception paths. They may call the existing unit attack interface. They must not inspect `session._T`, write session state or counts, spawn through internal methods, remove roster indexes, call damage / knockback queues or settlement helpers, or force a result. A complete `AdvanceForTest` / `StepSimulation` owns damage resolution and result settlement. Manual clock time does not advance native Body movement; prove movement, contact, crowding, and knockback with Maker frames.

## Temporary MonsterData identity case

Only the dedicated identity case changes `RootDesk/MyDesk/Data/MonsterData.csv`. Run it as a guarded transaction using `withTemporaryMonsterCsv` from `monster_catalog_csv_fixture.cjs`:

1. Stop Maker and copy the original CSV bytes to a unique directory under the operating system temp directory. The guard records byte length and SHA-256, verifies the backup, and writes a temporary fixture with byte-checked output. The fixture changes `monster_tank` to `RenamedTank` and adds a row cloned from the tank with only `MonsterId=probe_tank_variant` and `MonsterName=VariantTank` changed.
2. Refresh, read build logs, start a new Play test, then execute the complete `monster_catalog_identity_runtime_probe.lua` in `server_main`. It queries the loaded catalog, compares the profile fields, checks the official options, and deploys both IDs through `TryDeployMonster`.
3. The guard requires Maker Stop, Refresh, and restored-catalog verification callbacks before it changes the CSV. When the probe succeeds, fails, throws, or receives a graceful SIGINT / SIGTERM / AbortSignal, it waits for an interrupted probe callback to settle as its cancellation acknowledgement, then awaits Maker Stop, restores the saved bytes, verifies byte equality and SHA-256, awaits Refresh, and runs the supplied restored-catalog verifier. Signal handlers remain active through the final Stop. If cleanup or verification fails, it retains the temp backup and reports its path for recovery. If an interrupted callback never settles, rollback stays pending with its backup intact; the helper does not refresh or delete evidence while Maker work may still be running.
4. The restored verifier uses a fresh Play test and the complete `monster_catalog_restored_runtime_probe.lua` in `server_main`; require its final PASS, then Stop. It checks `monster_tank` is again named `Tank`, the temporary ID is absent, the option count is three, and the session is in formal deployment.

The helper takes Maker lifecycle callbacks so filesystem rollback and Maker Stop / Refresh / catalog verification use the same `finally` path. The temporary row, renamed name, backup, and manifest are not tracked or committed. Neither identity probe needs a manual clock or real movement frames.

## Regression evidence

After restoration, re-run `node --test tests/*.test.cjs`, `deployment_runtime_probe.lua`, and `six_vs_six_full_battle_probe.lua` in separate fresh Play tests. Keep the formal battle within 45 seconds, require exactly one legal RESULT, and wait one additional real second to verify HP, combat serials, target, position, and knockback state remain stable. Capture the restoration SHA-256, the restored-catalog PASS, and each runtime verdict before concluding the fixture is clean.

The probes assert observed HP, `DamageTakenSerial`, `OnHitSoundSerial`, `AttackSerial`, events, positions, and results. Source-string assertions remain for structural contracts only; they do not substitute for runtime evidence.
