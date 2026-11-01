# #51 雙方視角戰鬥 HUD、結果與返回

沿用 [#44](https://github.com/zsp2233000/MSW-Battle/issues/44) 的 Cardgame 棕色視覺，改版正式戰鬥的 HUD 與結果。戰鬥、相機與頭頂血條規則不變。

## 行為

- `BattleUIController` 是唯一的結果擁有者：Away 玩家的存活數與出戰數一起交換，配對戰以 `ResultForProfile` 取得自己的結果，POC 用 `session.Result`。`BattleDeploymentInput` 不再繪製結果。
- `MatchProbeInput` 依狀態選面板：大廳 `Match`；戰鬥中不顯示面板，保留戰場視野；其他房間狀態（等待、失敗、中止）`BattleMatch`；有自身結果時 `BattleResult`，位於結果視窗正下方。按鈕一樣送既有的 `RequestReturn`。送出後到伺服器回覆前顯示「返回中…」，重試也一樣。
- `BattleHud` 不再接收點擊。編隊 UI 在 `matchprobe` 維持停用（既有行為）。
- `BattleConfigErrorGroup` 已使用與確認視窗相同的彈窗素材，本票沒有修改，只補上契約檢查。POC 的 `DeploymentPanel` 也保持原樣。

## 驗證

2026-11-01，原生 Maker。`node --test tests/*.test.cjs` 全數通過（50 項），UIBuilder 嚴格 lint 無 error。第一輪 Refresh 後讀過 build logs，無 Error（沿用既有的 `IsPCPlatform`、`BattleViewAvatar` 兩項 Warning）；審查後修正 `Render` 的那一輪有 Refresh，但沒有重讀 build logs，以修正行為的 runtime 通過為準。runtime 無 Error，只有既有的 `LWA-3048`。

本機雙玩家（本機玩家＋`add_virtual_player`），隔離 `_FormationService.StorageKey`，正式佇列 6 對 1，自然戰鬥：

| 項目 | 探針 | 證據 |
|---|---|---|
| 戰鬥中只有 HUD，部署、結果、配對面板與編隊 UI 全部停用 | `matched_battle_result_ui` | `BATTLE_VIEW profile=6Y9NGB home=6Y9NGB hud=6/1 roster=6/1` |
| 交換 Home／Away，HUD 跟著視角 | `matched_view_swap` + 上者 | `SWAPPED_VIEW home=hf2602 hud=1/6`，權威單位快照不變 |
| 唯一結果與存活數 | 同上 | `PASS own WIN counts=6 / 6 vs 0 / 1 swapped=true`；伺服器 `home=WIN away=LOSE` |
| 待處理 | 同上 | `RETURN_PENDING status=正在返回大廳…` |
| 返回失敗（`ConfigureMakerTransferFaults(0, 1)`）與重試 | 同上 | `RETURN_FAILED msg=RETURN_MOVE ok=false`，留在結果畫面；`RETRY_PENDING`；`RETURN_RETRY_MOVE ok=true`、`RETURNED restored=true` |
| 返回後無殘留，可再配對與取消 | `matched_battle_lobby_ui` | `[VRF][MatchedLobbyUI] PASS` |
| POC（`template`）部署、開始、自然結果 | `deployment_ui` | `[M1][DeploymentUIProbe] PASS` |

分段的一次性檢查（不在 repo 的探針內，僅作輔助）：

- 實際 Away 視角、未改身分：`hud=6/1 home=hf2602 me=6Y9NGB`。
- 結果階段交換身分：`own=LOSE counts=0 / 1 vs 6 / 6`。

玩家切換房間時 client context 會重置，因此 `matched_battle_result_ui_runtime_probe.lua` 要在進房後派送。返回由 `ButtonClickEvent` 驅動已連接的按鈕，不是實體滑鼠。

### 可重跑程序

1. 全新 Play，在 `server_main` 設定隔離的 `_FormationService.StorageKey`，用 `add_virtual_player` 加第二名玩家。
2. 兩名玩家都以 `_FormationService:Load` 重新讀取，再存好並啟用不對稱編隊（六隻與一隻），然後 `QueueForUser`。必須重新讀取：本機玩家已在進場時讀過正式鍵，直接寫入隔離鍵會得到 `CONFLICT`。
3. 進房後在 `client` 派送 `matched_battle_result_ui_runtime_probe.lua`；在 `server_instance_*` 執行 `_MatchProbe:ConfigureMakerTransferFaults(0, 1)` 與 `matched_view_swap_runtime_probe.lua`。
4. 回大廳後在 `client` 派送 `matched_battle_lobby_ui_runtime_probe.lua`。虛擬玩家不會自己返回；要再配對時，先在 `server_instance_*` 對他呼叫 `ReturnForUser`。

## 2026-11-01 使用者畫面回饋

使用者截圖指出 HUD 遮住上方場地，「戰鬥結果」文字也壓在視窗邊框上：

- `matchprobe` 的 `CameraOffset.y` 由 0 改為 0.9。整備（`formationsim`）與 POC（`template`）維持原值，因為整備下方有怪物列表，上移會多蓋住場地。
- 彈窗素材四周有透明邊，可見上緣比 360px 的矩形低，因此 `Caption` 下移到 y=112，三個結果區塊下移到 y=34。

經使用者同意，以 Maker 原生截圖確認（1920×1080）：戰鬥中 HUD 只蓋到外牆，場地與地圖下緣完整可見；結果視窗的文字與邊框、分隔線都不重疊。

## LWA-3048

`BattleViewAvatar.model` 同時掛著 Body 與 Face 兩個 ActionSelector，生成 `ViewAvatar_1`／`_2` 時各報一次 `LWA-3048`，引擎也預告之後不再加入後者。Face selector 沒有編寫值，程式也沒有使用，已移除；重跑配對後 runtime 為 0 Warning，頭像與名牌正常。上方所記的既有 `LWA-3048` 只適用於移除之前。Build Console 的 `LWA-4013` 在 Refresh 後仍留著 16:43 的舊時間戳，尚未確認會在下次重新驗證時消失。

## 未驗收

- **原生外觀**：上述截圖只涵蓋參考解析度的戰鬥與勝利畫面。較小視窗、失敗／平手畫面，以及按鈕四種狀態的實體滑鼠操作還沒有畫面證據；其中結果面板的按鈕是否實際壓在 Dimmer 之上，也要由實體點擊確認（MatchGroup 的 GroupOrder 6 高於 BattleGroup 的 2）。
- 版面後續由使用者在 Maker 微調：HUD 高度與邊框、兩條 `TopAccent`（移到可見邊框內）、結果數據位置。這些調整已提交，提交後未再截圖。
- **視覺待確認**：`a21e588b…` 不在 #44 列出的素材表內，是目前確認視窗使用的彈窗；木紋 `79ed3b…` 只用在大廳，HUD 與結果面板和既有 `BattleMatch` 一樣沒有木紋。
- 未重跑：`six_vs_six_ui_runtime_probe.lua`（只改了結果實體的參照來源）。
- 平手結果未自然發生，由既有的 `ResultForProfile` 與結果實體邏輯涵蓋。
- `RETURN_SAVE_FAILED` 未注入。這個失敗會把狀態退回 `RESULT_*`，之後的狀態發布可能蓋掉失敗文字；這是既有的伺服器邏輯，本票沒有修改。
- 發布環境跨 WorldInstance 與兩個真實帳號仍在 #52 及既有邊界之外。
