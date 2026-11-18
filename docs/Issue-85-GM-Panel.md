# Issue #85 — GM 怪物等級修改與操作紀錄

Extends the GM panel from #84. The server authenticates every command using the requester's ProfileCode derived from the RPC sender. GM actions work in Maker and published worlds; fault injection works only in Maker.

## Acceptance checks

- Valid monster level/experience edits round-trip; invalid progress leaves the stored document unchanged.
- Save compares against the bytes loaded when the panel opened. Conflict shows 「存檔在你開啟後已變動」 with 「強制覆蓋」 and 「重新讀取」. Force-save re-reads and uses CAS again; its operation record contains the actual overwritten bytes.
- Reset returns all monsters to Lv1 / 0 and retains the settled match list. Normal edits and force-save cannot edit that list.
- Corrupted documents can be replaced with validated content or deleted. A healthy document cannot be deleted through this action.
- Global GM operation records are keyed by target player and retain the latest 20. A pending record must persist before changing the player's save. The service records the result afterwards. Audit failure leaves the player's save untouched.
- Timeout and Credit failures are errors, including failures while recording the outcome.

## Storage

`GMAuditV1` stores the newest slot and record ID at the target ProfileCode key. Each of the 20 slots has metadata at `<profile>_<slot>` and byte-exact snapshots in its `_before` and `_after` keys. A transaction advances the cursor and replaces all three slot values together. The metadata includes UTC milliseconds in `timeMs` and indicates whether each snapshot represents an existing save. Outcome updates use CAS against the unique pending record so a late update cannot touch a reused slot.

Corrupt-save deletion checks the audited bytes under the same cross-instance guard used to create a missing save. Battle settlement rejects corrupt saves and CAS-protects updates to readable saves. When storage returns a timeout on a first creation, deletion or audit append, the guard stays held until the relevant bytes or deletion can be confirmed.

## Verification

Run `node --test tests/gm_panel_contract.test.cjs` for the security/RPC/UI contracts and `node --test tests/*.test.cjs` for the complete Node suite. Maker Refresh and build logs provide the mLua compiler check; this repository has no separate typecheck command.

Start a fresh Play in `formationlobby` after Maker Refresh and check `maker_get_context_keys`. The probes write only to disposable level keys and synthetic audit targets. Wait for each log marker before dispatching the next script.

1. Run `tests/gm_level_write_runtime_probe.lua` in `server_main`. Require `[VRF][GMLevelWriteProbe] PASS` with `CLEANUP_PASS`.
2. Set `TOKEN` to the same eight fresh uppercase hexadecimal digits in both `tests/gm_panel_edit_ui_fixture.lua` and `tests/gm_panel_edit_ui_client_runtime_probe.lua`. Run the fixture in `server_main` with `MODE='SETUP'` and wait for `READY`. Run the client probe with `MODE='EDIT'` and wait for `EDIT_PASS`.
3. Run the server fixture with `MODE='CHANGE_FOR_RELOAD'` and wait for its marker. Run the client with `MODE='RELOAD'` and require `RELOAD_PASS`.
4. Run the server fixture with `MODE='CHANGE_FOR_FORCE'` and wait for its marker. Run the client with `MODE='FORCE'` and require `[VRF][GMPanelEditUIProbe] PASS`.
5. Run the fixture with `MODE='CLEANUP'` even if a UI step fails. Require `[VRF][GMPanelEditUIFixture] CLEANUP_PASS` before stopping Play.

### Recorded on 2026-11-18

- Node contracts: **150/150 PASS**. GM panel UIBuilder lint: **0 errors, 0 warnings**.
- Maker Play in `formationlobby` reached `GMLevelWriteProbe PASS` and cleanup at 11:30:54, `GMPanelEditUIProbe PASS` at 11:31:02, and `GMPanelEditUIFixture CLEANUP_PASS` at 11:31:03 (Maker log times). Timeout and Credit failures were exercised through Maker fault injection.
- Issue #84 read and authorization regression probes reached `GMPanelServerProbe PASS` at 11:31:04 and `GMPanelUIProbe PASS` with fixture cleanup at 11:32:21. The client probe selects its own fixture explicitly so it also runs after the #85 editor probe.
- Shared storage regressions reached `FormationStorage PASS` at 11:33:25 and `LevelStorage65 PASS` with cleanup at 11:34:20. The storage probe uses a GUID for its disposable key to avoid decimal punctuation in shared-memory names. Corrupt-save and exhausted-retry cases in the settlement probe emitted their expected diagnostics.
- Maker build logs contained **0 errors** before and after Play, with the existing `IsPCPlatform()` deprecation warning. Maker returned to edit mode.

## Manual checks

- [ ] Published world with real GM and non-GM accounts.
- [ ] Real mouse and keyboard editing, scrolling, reload and force-save.
- [ ] Mobile/small viewport layout.

Formation maintenance, handoff maintenance, operation-record browsing and restore actions remain assigned to later GM panel issues.
