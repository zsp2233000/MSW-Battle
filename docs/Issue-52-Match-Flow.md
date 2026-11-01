# #52 大廳配對與戰後返回整合

依 [#52](https://github.com/zsp2233000/MSW-Battle/issues/52) 串接 #50 的單組儲存／client 未儲存變更，以及 #51 的戰鬥 HUD／自身結果。程式與本機往返已有正向證據；下方實體滑鼠與發布環境項目仍未驗收，不據此關閉 issue。

## 行為

- 配對只從 `formationlobby` 開始。client 入口與伺服器 `QueueForUser` 都檢查地圖；整備內的舊事件或直接 RPC 不會排隊。
- 送出開始／取消後立即鎖住整備；只有正式 `IDLE` 且沒有在途狀態請求才解鎖。大廳選組、雙擊整備、POC 入口及 local 編輯共用這個條件；配對期間清除尚未完成的整備進場意圖。
- `MatchProbe.IsFormationLocked` 供伺服器選組、儲存、啟用與移動重驗證，涵蓋請求中的 yield、等待、取消未確認、入場與返回。原有 transfer lock 仍由 FormationService 管理。
- 原生取消成功後才寫入取消終態。取消或終態寫入失敗都維持鎖定並提供重試；配對預約寫入未確認也保留待取消的票券，不提前呈現可編輯狀態。
- 固定本局編隊、經過時間、直接入場、confirmed-only 交接與結果仍沿用既有服務。選組預覽不改出戰組，配對不儲存編輯內容，不新增 Ready 或倒數。
- 返回失敗原因在後續結果狀態發布中保留；重試送出後先顯示「返回中…」。重試／確認結果按鈕先啟用再寫文案，避免首次建立原生 UI 時使用舊的樣板文案。
- 沒有改 `.ui`、地圖、模型、怪物數值或血條。

## 本機證據（2026-11-01）

原生 Maker，四張地圖均維持 RectTile。真實本機 client 加 `hf2602` 虛擬玩家；這不是兩個真實帳號或跨 WorldInstance 的驗收。

| 項目 | 探針／證據 |
|---|---|
| 完整 contract suite | `node --test tests/*.test.cjs`：53/53 |
| UIBuilder lint | FormationGroup、MatchGroup、BattleGroup、BattleConfigErrorGroup：0 error；保留既有 3／0／2／0 warning |
| Maker build | 0 Error；`IsPCPlatform` 舊 API warning，以及 16:43 的既有 BattleViewAvatar warning |
| client 腳本 LSP | FormationLobby、FormationEditSession、MatchProbeInput：0 error／warning。另兩個 server 腳本仍有本機原生事件定義缺失的既有診斷，以 Maker build 與 runtime 核對 |
| 單組儲存、切組／返回三選擇、空組與不合法站位、捨棄後重開 | `editor_save_flow_runtime_probe.lua`：`[VRF][Save50] PASS`，含 S1–S10 |
| 五組保存、第三組啟用、更新其版本後返回 | `match_flow_runtime_probe.lua` PREPARE：`PREPARE PASS five saved groups; explicit active choice; updated active version; clean lobby return` |
| 預覽組獨立、舊入口被擋、等待超過六十秒 | 同探針 QUEUE：`QUEUE PASS ... real wait >60s`；實際等候 63 秒，未修改顯示時鐘 |
| 取消寫入失敗與恢復 | CANCEL_FAILURE／CANCEL_RECOVER 皆 PASS；取消完成前整備入口不可用，成功後可再進整備，整備內直接 RPC 仍被拒絕 |
| 配對預約寫入失敗 | `RESERVATION_FAILURE PASS locked until cancellation`，隨後 `RESERVATION_RECOVER PASS` |
| 伺服器儲存拒絕／固定內容 | 等待時 SaveForUser 回覆 REJECTED，保存內容不變；修改取出的 roster 不影響下一次讀取。舊 queue probe 同步改為檢查等待時拒絕修改 |
| 入場版本、DB 邊界與舊資料相容 | roundtrip：`ENTERING fixed slot=3 revision=2; confirmed-only DB; legacy content ignored` |
| 戰鬥 HUD、自身結果、返回失敗及重試 | 既有 result UI probe：`BATTLE_VIEW ... hud=1/1 roster=1/1`、`PASS own WIN counts=1 / 1 vs 0 / 1`、`RETURN_FAILED msg=RETURN_MOVE ok=false`、`RETRY_PENDING`，其後正式返回成功 |
| 兩名玩家返回後保存完整 | `match_flow_roundtrip_runtime_probe.lua`：`PASS five groups; active/version retained; no automatic save; confirmed handoff; both returned`（19:19:57） |
| 返回後再次配對／取消 | `matched_battle_lobby_ui_runtime_probe.lua`：`[VRF][MatchedLobbyUI] PASS` |
| 既有 POC 入口與自然結果 | 從正式大廳 POC 按鈕進入 template，等待卡片建立完成，再執行 `deployment_ui_runtime_probe.lua`：`[M1][DeploymentUIProbe] PASS`；最後這次 Play 的 runtime 0 Error／Warning |
| 儲存失敗／逾時／晚到回覆 | 既有 `editor_save_failure_runtime_probe.lua` 的 FAIL、SILENT、LATE；失敗保留內容、逾時禁止切組與離開、恢復讀取後手動儲存、晚到成功不執行已中止的返回 |

本機探針只透過正式 ButtonClickEvent、map input handler 與伺服器服務操作，不代表實體滑鼠點擊。測試前幾次的 FAIL 涉及探針前置狀態：非第一組、尚未完成切圖／讀取、返回 session 尚未還原，以及序列化字串比較。已改為等待可操作狀態與資料還原，並逐欄檢查五組內容、版本與 writeId；保留失敗紀錄，不將派送成功當作 PASS。POC 初次複驗過早讀取 optionsReady 而卡片尚未完整建立，只有卡片數量檢查失敗，其餘部署至自然結果皆通過；重跑需同時等待 optionCards 與 optionData 數量相同。

## 重跑與清理

1. 全新 Play，等待 `maker_get_context_keys` 確認 `server_main`／`client`。將 `_FormationService.StorageKey` 設為唯一的 `Issue52...` 鍵；單玩家等待／取消測試也可隔離 `_FormationHandoff.StorageKey`。
2. 在 client 執行 `editor_save_flow_runtime_probe.lua`，再執行 Flow52 PREPARE。將 `PHASE` 換為 QUEUE；等待最後 PASS 後，在 server_main 注入 `ConfigureMakerFaults(0, 1, 0)`，執行 CANCEL_FAILURE，清除故障後執行 CANCEL_RECOVER。
3. 往返時每個 room 必須使用同一個 handoff key。此次使用原本的 `BattleTransferV2`，只寫本機測試的短期票券；編隊存檔仍使用隔離鍵。新增 `hf2602` 虛擬玩家，從真實 client 大廳按鈕開始並等待 QUEUED，再在 server_main 執行 roundtrip probe。
4. 進房會重設 client context。取得新的 `server_instance_*` key 後，在該 context 設 `ConfigureMakerTransferFaults(0, 1)`，並立即在 client 派送既有 result UI probe，才能看到正在進行的戰鬥。
5. 真實 client 返回後，從該 instance 對 `hf2602` 呼叫 ReturnForUser；主房間 roundtrip coroutine 會等兩者的保存資料都完成還原才驗證。最後在 client 執行 lobby UI probe。
6. 儲存故障探針各使用新的隔離編隊鍵，將 server session 的 editSlot 設為 1，且先返回大廳並清除測試的 local 變更。依既有檔案註解注入 FAIL／SILENT／LATE，完成後將 `ConfigureMakerSaveResponse('', 0)`、`ConfigureMakerFaults(0, 0, 0)`、`ConfigureMakerTransferFaults(0, 0)` 復原，還原兩個預設 StorageKey，Stop Play。沒有清空 DataStorage，也沒有覆寫正式編隊存檔。

## 原生視覺與待驗收

已讀取 Maker 原生截圖：大廳、等待／配對預約錯誤、整備、離開確認與勝利結果。確認必要控制項可見、確認選項未被遮住、結果與返回操作分開呈現。截圖在 Maker `McpScreenshots` 目錄：`185159_572`（等待）、`190927_433`（錯誤）、`191633_777`（大廳）、`192106_123`（整備）、`192143_990`（確認）、`191301_077`（結果）；日期前綴均為 `maker_play_20261101_`。戰鬥 HUD 本輪取得 runtime 正向證據，未取得戰鬥進行中的截圖，外觀亦沿用 #51 已確認的版面。

尚未驗收：五個畫面的實體 PC 滑鼠、hover／pressed／disabled 外觀、首次顯示的繪製延遲、較小 PC 視窗、手機，以及失敗／平手結果外觀。Maker mouse_input 工具明示不能點擊標準引擎 UI，不能用 SendEvent 冒充實體點擊。未對本機實際入場傳送失敗或 RETURN_SAVE_FAILED 提示做完整故障回歸；本輪返回失敗使用 MoveToLobby 邊界，相關既有探針與服務保留。

發布環境仍須兩個真實帳號、不同 WorldInstance，驗證原生配對續期／取消競態、跨 instance 交接、原生傳送失敗與返回。沒有將本機兩玩家往返當成此項通過。

## 審查

已依 code-review 的 Standards／Spec 兩軸由主代理檢視改動與相連程式；平行 sub-agent 啟動回報不支援的模型，未產生獨立審查報告。檢視包含 RPC 身分、服務端鎖定、取消與 storage yield、舊 attempt／延遲回覆、固定編隊與 session 還原、UI 群組及 POC 相容性。未新增依賴或替換戰鬥與資料模型；剩餘驗收邊界如上。
