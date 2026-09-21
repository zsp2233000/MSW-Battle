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
| 1. 建立 `BATTLE` / `RESULT`、雙方 faction、alive count、單次結果與 session snapshot | 🟡 Implemented (untested) | `RootDesk/MyDesk/Combat/BattleSession.mlua`；待 Maker Play log |
| 2. 建立 RectTile 單位 model 與逐幀直線追擊，停止於攻擊距離 | 🟡 Implemented (untested) | `RootDesk/MyDesk/Models/Monsters/BattleUnit.model` + `BattleUnit.mlua`；待 Maker Play 位置觀察 |
| 3. 每 0.5 秒 retarget、0.7 秒 attack、0.18 秒 impact、35 damage、死亡免疫與 Win/Lose | 🟡 Implemented (untested) | `AssaultAttack.mlua` + model native `HitComponent`；待 native HitEvent log |
| 4. 固定 full-field 相機；DefaultPlayer 可見但不可移動、碰撞、被選取或參與勝負 | 🟡 Implemented (untested) | `BattleSession:DisableDefaultPlayer()`；待 Maker Play 視覺/互動確認 |
| 5. 高階 elapsed-time harness 與外部契約測試 | 🟡 Implemented (untested) | `AdvanceForTest()` + `tests/battle_session_contract.test.cjs`；Node 靜態契約 PASS，runtime 待 Maker |

## Verification boundary

目前工作環境沒有 Maker Refresh / Play / runtime log connector，因此本階段先交付可 Refresh 的 `.mlua`、builder 產出的 `.model` / `.map` 與 Node 契約測試。`BattleUnit.model` 的非空 SpriteRUID 是 MSW 平台要求的 documented placeholder，不是資產搜尋／選擇結果；人類資產仍待補。未取得 Maker runtime 證據前，不得把 runtime 項目標成 `✅ Tested`，也不得刪除此 Phase 文件。
