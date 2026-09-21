# Battle POC M1 — Phase 1 一對一突擊自動戰鬥

> 來源：GitHub Issue #2 / `docs/BattlePOC-M1-GDD.md`。本文件是 Phase 1 的執行真相；每個項目在寫碼後先標記 `🟡 Implemented (untested)`，完成 Maker Refresh + Play 驗證後才可改為 `✅ Tested`。

## Scope

- Maker Play 固定一個 player formation 的 `突擊`單位，對戰一個 fixed enemy 的 `突擊`單位。
- 戰鬥階段自動開始，採 native Attack→Hit pipeline；結果只會進入一次 `WIN` / `LOSE` / `DRAW`。
- M1 固定兩個起點並給 enemy `0.12s` opening delay，保留同批傷害的 `DRAW` 防護並讓一般局 deterministic 地先產生 `WIN` 或 `LOSE`。
- RectTile 保留；單位使用 `KinematicbodyComponent` + `MovementComponent:MoveToDirection` 逐幀直線移動。
- 不新增部署 UI、資產搜尋、地形/重力/跳躍/pathfinding。

## Checklist

| 項目 | 狀態 | 證據 / 待驗證 |
|---|---|---|
| 1. 建立 `BATTLE` / `RESULT`、雙方 faction、alive count、單次結果與 session snapshot | ✅ Tested | Maker Play 2026-09-21 20:04:55 記錄 `BATTLE started: PLAYER assault vs ENEMY assault`；20:05:01 記錄 `RESULT=WIN` |
| 2. 建立 RectTile 單位 model 與逐幀直線追擊，停止於攻擊距離 | ✅ Tested | Maker Play runtime 完成一對一戰鬥；使用者人工確認單位位置、直線追擊與攻擊距離行為正常 |
| 3. 每 0.5 秒 retarget、0.7 秒 attack、0.18 秒 impact、35 damage、死亡免疫與 Win/Lose | ✅ Tested | Node 外部契約 PASS；Maker Play runtime 產生 `RESULT=WIN`；使用者人工確認攻擊、傷害、死亡與結果行為正常 |
| 4. 固定 full-field 相機；DefaultPlayer 可見但不可移動、碰撞、被選取或參與勝負 | ✅ Tested | `BattleSession:DisableDefaultPlayer()`；使用者人工完成 Maker Play 視覺／互動驗收並確認正常 |
| 5. 高階 elapsed-time harness 與外部契約測試 | ✅ Tested | `AdvanceForTest()` + `tests/battle_session_contract.test.cjs`；Node 靜態契約 PASS，Maker Play start/result/stop PASS |

## Verification boundary

Maker MCP 已可用。2026-09-21 已完成 `stop → clear_logs → refresh → build logs → play → normal logs → stop`：map01 進入 Play，建立 `server_main`／`client` context，並取得 `BATTLE started` 與 `RESULT=WIN`；Build Console 僅回報 34 筆 `Info` 型 API 檢查項，未見 `Error`。使用者已完成 Maker Play 功能／視覺／互動驗收並回報正常，因此第 1–5 項皆可標記 `✅ Tested`。`BattleUnit.model` 的非空 SpriteRUID 是 MSW 平台要求的 documented placeholder，不是資產搜尋／選擇結果；正式人類資產仍待後續視覺 Phase。
