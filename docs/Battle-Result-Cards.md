# 戰鬥結果畫面 — 存活怪物卡片

狀態：已依使用者確認實作，通過下述本機功能驗證；原生外觀待目視驗收。最後更新：2026-11-09。

本文件記錄使用者已確認的新增需求；既有結果、雙方視角及返回流程見 [#51 交付紀錄](Issue-51-Battle-HUD.md)。

## 已確認

- 戰鬥結束後，以卡片呈現仍存活的怪物。
- 每隻存活怪物各一張卡片，同種怪物不合併。例如剩三隻坦克，就顯示三張坦克卡。
- 每張卡片顯示怪物圖像、名稱及剩餘 HP／最大 HP；HP 表示本局結束時的生命值。
- 左右以正在觀看畫面的玩家為準：我方在左、敵方在右，不以主場／客場或伺服器陣營代碼固定左右。

| 觀看者的戰鬥結果 | 左側卡片 | 右側卡片 |
|---|---|---|
| 勝利 | 我方存活怪物，各一張 | 無 |
| 失敗 | 無 | 敵方存活怪物，各一張 |
| 平手（雙方全滅） | 無 | 無 |

平手時保留「雙方平手」，不改列已死亡或曾出戰的怪物。

## 版面與排序（Q5、Q6 已確認）

- 中央顯示勝負提示與返回大廳操作。
- 存活怪物卡片放在中央勝負視窗的左右兩側，依上表決定顯示側。
- 每列三張卡片，超過三張就換下一列。
- 依原本出戰順序逐列排列；同種怪物各自占一個位置，不按剩餘 HP 重新排序。

## 驗收條件

1. 我方獲勝時，左側列出我方全部存活怪物；我方失敗時，右側列出敵方全部存活怪物。主場與客場觀看者均依自己的視角判定。
2. 卡片數量等於該方存活怪物數；同種但不同實例的怪物不合併，各自顯示正確的圖像、名稱與結束時剩餘／最大 HP。
3. 四張以上會換列，每列至多三張，排列順序與原本出戰順序一致。
4. 平手時顯示「雙方平手」，左右都沒有怪物卡片。
5. 中央勝負提示及返回大廳操作可正常使用；離開戰場後，下一局不殘留上一局卡片。

以上為驗收標準；本輪實際覆蓋範圍見下方紀錄。

## 已核對的實作基礎

- `BattleUIController` 是現有結果畫面的唯一控制者；配對戰透過 `ResultForProfile` 取得觀看者自己的結果，單人 POC 使用 `session.Result`。
- 單位具有同步的 `MonsterId`、`MonsterName`、`Hp` 與 `MaxHp`；session 的單位紀錄同時保留死亡與存活單位，新增卡片時須按存活狀態過濾，並保留每隻實例的身分。
- `UnitSnapshots` 是診斷字串，含死亡單位且缺最大 HP，不直接作為卡片資料契約。
- #70 起，結果畫面的卡片改為清單：`BattleResultPanel/RowTemplate`（580×84，無按鈕、圖片不攔截點擊）。每列有圖像、名稱、怪物等級、進度條、進度文字與數值文字；存活清單與經驗清單共用 `BattleUIController:BuildResultRow`。左側永遠是我方：勝利時先放我方存活列，經驗列（含 LEVEL UP）接在其下；失敗時只有經驗列。右側永遠是敵方：失敗時放對手存活列，只顯示等級與血量，不顯示經驗或升級；勝利與平手時為空。
- 單位新增同步的 `DeploymentOrder`，由 session 在加入 roster 時指定，供卡片保留出戰順序。

## 2026-11-09 驗證

- TDD：`tests/battle_result_cards.test.cjs` 先因缺少結果卡片樣板失敗；加入樣板後通過。完整 `node --test tests/*.test.cjs` 為 57/57。
- 三個修改的 mLua 腳本均完成 LSP diagnose，Error／Warning 為 0。Maker Refresh 後 Build Console 無 Error，保留既有 `IsPCPlatform` Warning。
- Maker 同一次 Play 內，從大廳進入 `template`，以四隻坦克與不同剩餘 HP 建立受控結果。`tests/result_cards_runtime_probe.lua` 透過正式結果 UI 驗證名稱、圖像、各自 HP、數量、換列與左右位置。
- 正向證據：`PASS result=WIN count=4 own=PLAYER`、`PASS result=LOSE count=4 own=ENEMY`、`PASS result=DRAW count=0 own=ENEMY`、`PASS lobby cleanup`。本次 Play 的 runtime 無 Error，最後已 Stop。
- 客場案例使用測試用主客身分，並在 client 設定與配對地圖相同的 `RequireMatchedFormations=true`；它驗證視角對應，並非兩個真實帳號的配對測試。平手由受控 fixture 提供，並非自然戰鬥產生。
- 測試只改 Play 內的 session／單位，未寫入隊伍存檔或 DataStorage。
- UIBuilder 讀回比對確認原有 59 個 UI 實體內容皆相同，僅新增六個樣板實體；大幅文字 diff 來自 builder 序列化。
- 尚未目視驗收卡片素材、較小視窗與手機版面；本輪也未重跑真人配對、返回按鈕或返回失敗重試流程。

### 移除後重新部署的回歸

- 收尾檢查發現部署移除會縮短 roster，改以獨立遞增的出戰順序避免新怪物與仍在場的怪物共用排序值；每次重建 roster 時重設。
- 新增可重跑的 `tests/result_cards_fixture.lua`：全新 Maker Play，先將玩家移至 `template`，在 `server_main` 執行 fixture，再在 `client` 執行 `tests/result_cards_runtime_probe.lua`。
- 已驗證六隻坦克、移除第一隻再補回後的順序唯一，以及 `PASS result=WIN count=6 own=PLAYER`；移回大廳另取得 `PASS six-card lobby cleanup`。這輪更新後重新執行完整 Node suite 仍為 57/57，session 的 LSP Error／Warning 為 0。

## 雙軸審查

- 比較基準：`main`（`19b3550`）；兩個獨立代理審查 `137e295`，並納入後續出戰順序計數器修正與 server fixture。
- Standards：0 項硬性違規；1 項低風險觀察：同步資料未到齊或缺少樣板時等待重試，沒有額外等待提示或失敗 log。現有成功路徑已有 VRF 證據，保留此觀察供後續診斷。
- Spec：0 項未解決的重大缺漏或範圍擴張。移除後重新部署的順序問題已修正並驗證。
- 審查不代替前述原生外觀與真人配對驗收。
