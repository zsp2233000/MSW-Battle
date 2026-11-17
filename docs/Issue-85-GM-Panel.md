# Issue #85 — GM 怪物等級修改與操作紀錄

Extends the GM panel from #84. The server authenticates every command using the requester's ProfileCode derived from the RPC sender. GM actions work in Maker and published worlds; fault injection works only in Maker.

## Acceptance checks

- Valid monster level/experience edits round-trip; invalid progress leaves the stored document unchanged.
- Save compares against the bytes loaded when the panel opened. Conflict shows 「存檔在你開啟後已變動」 with 「強制覆蓋」 and 「重新讀取」. Force-save re-reads and uses CAS again; its operation record contains the actual overwritten bytes.
- Reset returns all monsters to Lv1 / 0 and retains the settled match list. Normal edits and force-save cannot edit that list.
- Corrupted documents can be replaced with validated content or deleted. A healthy document cannot be deleted through this action.
- Global GM operation records are keyed by target player and retain the latest 20. A pending record must persist before changing the player's save; the result is recorded afterwards. Audit failure leaves the player's save untouched.
- Timeout and Credit failures are errors, including failures while recording the outcome.

## Verification

Run `node --test tests/gm_panel_contract.test.cjs` for the security/RPC/UI contracts and `node --test tests/*.test.cjs` for the complete Node suite. Maker Refresh and build logs provide the mLua compiler check; this repository has no separate typecheck command.

Runtime verification uses one fresh Play in this workspace's `formationlobby` map, server probes in `server_main`, and UI probes in `client`. Test fixtures must use isolated player-save keys and a separate audit container, restore configured names and fault settings, and delete their disposable data even after assertion failure. A successful script dispatch is not a PASS: require terminal `[VRF]` PASS and cleanup evidence from the Maker normal logs.

Final runtime results will be recorded after verification.

## Manual checks

- [ ] Published world with real GM and non-GM accounts.
- [ ] Real mouse/keyboard editing, scrolling, confirmation, reload and force-save.
- [ ] Mobile/small viewport layout.

Formation maintenance, handoff maintenance, operation-record browsing and restore actions remain assigned to later GM panel issues.
