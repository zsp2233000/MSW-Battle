# Issue #84 — GM 面板入口與唯讀怪物等級

`GMCommandService.Execute(requesterProfile, command, complete)` is the ServerOnly boundary. It checks the hard-coded whitelist before every command, supports `IDENTITY` and `LOAD_LEVELS`, and refuses other commands. The owner's published ProfileCode and the current Maker account both resolve to `6Y9NGB` (confirmed from the server's `[VRF][GMIdentity]` log). `GMPanelService.Request` derives the requester from `senderUserId`; the target ProfileCode is a separate value. Replies target only that sender. There is no Maker-only gate on the GM path.

The lobby entry and panel live in `ui/GMPanelGroup.ui`, authored through UIBuilder. The entry starts hidden and requires a positive server reply; map travel and the lobby matchmaking lock close the panel. Loading uses the existing `FormationStorage.Read` boundary and the monster-level decoder. All catalog monsters appear, absent progress defaults to Lv1 / 0, and damaged saves appear as literal raw text with 「存檔損壞」. Reads never create or modify saves. This ticket adds no save, delete, audit, or restore action from the parent issue.

## Repeatable checks

Run `node --test tests/gm_panel_contract.test.cjs` for sender identity, whitelist-before-dispatch, read-only/client boundaries, published availability and UI bindings. Run `node --test tests/*.test.cjs` for the full Node suite. mLua has no separate repository typecheck command: Maker Refresh conversion and build logs are the compiler checks.

In Maker, open this workspace's `formationlobby` map. Stop → clear normal logs → Refresh → inspect **build** and **normal** logs → Play. Wait for `[VRF][GMPanel] ready`, `authorized=true`, and the lobby to be ready. Use `maker_get_context_keys` before executing the probes. All checks below run in the same Play:

1. Execute `tests/gm_panel_runtime_probe.lua` in `server_main`; require final `[VRF][GMPanelServerProbe] PASS ... CLEANUP_PASS`. It tests every named command as a non-GM, then absent/valid/corrupt reads, self/explicit target, invalid targets and a storage failure. It compares stored bytes before/after, uses a unique disposable key, deletes it and restores `MonsterLevelStorage.StorageKey` even on assertion failure.
2. Execute `tests/gm_panel_ui_fixture.lua` in `server_main` with its default `CLEANUP=false`; require `[VRF][GMPanelUIFixture] READY`. It writes only a unique isolated key for the current player and synthetic `GM84CORRUPT` profile. Production save keys remain untouched. Do not queue a battle while the level key is isolated.
3. Execute `tests/gm_panel_ui_client_runtime_probe.lua` in `client`; require final `[VRF][GMPanelUIProbe] PASS`. It drives the connected `ButtonClickEvent`s: entry, target load, myself and close; observes actual rendered table cells, defaults, scrolling, raw corruption text and late-reply handling. The negative identity UI state is a **synthetic denied observation**; actual server refusals are covered by step 1. No real second account is impersonated.
4. **Always**, including after a probe failure, rerun the fixture in `server_main` with `CLEANUP=true`; require `[VRF][GMPanelUIFixture] CLEANUP_PASS`. This restores the original level key and deletes/read-checks both disposable fixture keys. The fixture's cleanup record is test-owned state on the Logic, never production state.
5. Inspect normal logs for terminal results and unexpected errors, recheck build logs, then Stop. A script-dispatch `ok` is not a test result.

## Verification recorded on 2026-11-17

Node: **149/149 PASS** (`node --test tests/*.test.cjs`). UIBuilder lint: clean for `GMPanelGroup.ui`. Maker Refresh/build: **0 Error**, only the existing `IsPCPlatform` deprecation warning. One fresh successful Play produced these terminal log lines (Maker log times):

- 21:13:05, server: `[VRF][GMPanelServerProbe] PASS ... CLEANUP_PASS`
- 21:13:59, client: `[VRF][GMPanelUIProbe] PASS ...`
- 21:14:49, server: `[VRF][GMPanelUIFixture] CLEANUP_PASS`

The successful run's normal log had no Error or Warning; Maker was stopped afterwards. An earlier client-probe attempt failed because it queried the server-only `MonsterData` dataset; its fixtures were cleaned up, and the client probe now uses the ten-monster fixture count while the server probe checks full dataset coverage. Production code did not change for that correction. The manual checks below were not run.

## Manual acceptance

- [ ] Published world: `6Y9NGB` sees the lobby entry and can load self and another real offline player's ProfileCode.
- [ ] A real non-GM account sees no entry and cannot obtain a reply with another player's save through a forged RPC requester.
- [ ] Maker and published saves remain separate; test each in its own environment.
- [ ] Real mouse: entry, target typing, load, myself, scroll/drag/scrollbar, close and reopen are usable; no overlap with lobby controls.
- [ ] Mobile/small viewport: labels, input, table and long damaged-save text remain readable and scrollable.

Button click/hover sounds are optional polish and are not wired by this ticket.
