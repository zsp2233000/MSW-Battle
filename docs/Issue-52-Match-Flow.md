# #52 大廳配對與戰後返回整合

依 [#52](https://github.com/zsp2233000/MSW-Battle/issues/52) 串接 #50 的單組儲存／client 未儲存變更，以及 #51 的戰鬥 HUD／自身結果。程式與本機往返已有正向證據；下方實體滑鼠與發布環境項目仍未驗收，不據此關閉 issue。

## 行為

- 配對只從 `formationlobby` 開始。client 入口與伺服器 `QueueForUser` 都檢查地圖；整備內的舊事件或直接 RPC 不會排隊。
- 送出開始／取消後立即鎖住整備；只有正式 `IDLE` 且沒有在途狀態請求才解鎖。大廳選組、雙擊整備、POC 入口及 local 編輯共用這個條件；配對期間清除尚未完成的整備進場意圖。
- `MatchFlow.IsFormationLocked` 供伺服器選組、儲存、啟用與移動重驗證，涵蓋請求中的 yield、等待、取消未確認、入場與返回。原有 transfer lock 仍由 FormationService 管理。
- 原生取消成功後才寫入取消終態。取消或終態寫入失敗都維持鎖定並提供重試；配對預約寫入未確認也保留待取消的票券，不提前呈現可編輯狀態。
- 取消等待使用票券外的 `cancelling` 旗標，保留真正的排隊／入場階段，對外呈現 `CANCELLING`；原生回覆失敗不再留下假取消終態。取消確認後、取消終態寫入尚未確認時仍呈現 `CANCELLING`，只有持久確認才清掉票券並回到 `IDLE`；玩家已離線時則放掉記憶體票券，重連後再由持久狀態恢復。
- 取消期間收到配對成功會暫存，取消失敗後接續同一票券；已在準備中的配對則等取消回覆後才越過 `COMMITTING` 邊界。取消成功會阻止入場，恢復入場時清掉過期的取消錯誤，保留原本的本局隊伍與版本。
- `CancelMatching` 共用既有原生回覆判斷，供可見取消及 `Depart` 使用；斷線清理收到取消失敗時不再寫入取消終態。Maker 專用的 `ConfigureMakerCancelFaults` 只注入回覆與延遲，不修改正式環境的原生服務路徑。
- `FormationHandoff.Close` 先驗證原票券與世代，再讀回持久狀態，讓逾時後才完成的預約或取消寫入能由同一取消操作恢復。讀取失敗、較新的票券或已進入交接的狀態仍拒絕取消；已持久完成的相同終態可直接確認，不重寫 payload。
- 儲存逾時後，只有讀回 `READY`／`NEW` 才恢復返回操作；保留服務端的晚到寫入防護。client 在 `CONFLICT`、`LOADING` 或 `ERROR` 且結果未確認時持續禁止離開，確認後可以放棄變更返回，不必再儲存一次。
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
| client 腳本 LSP | FormationLobby、FormationEditSession、MatchFlowInput：0 error／warning。另兩個 server 腳本仍有本機原生事件定義缺失的既有診斷，以 Maker build 與 runtime 核對 |
| 單組儲存、切組／返回三選擇、空組與不合法站位、捨棄後重開 | `editor_save_flow_runtime_probe.lua`：`[VRF][Save50] PASS`，含 S1–S10 |
| 五組保存、第三組啟用、更新其版本後返回 | `match_flow_runtime_probe.lua` PREPARE：`PREPARE PASS five saved groups; explicit active choice; updated active version; clean lobby return` |
| 預覽組獨立、舊入口被擋、等待超過六十秒 | 同探針 QUEUE：`QUEUE PASS ... real wait >60s`；實際等候 63 秒，未修改顯示時鐘 |
| 取消寫入失敗與恢復 | CANCEL_FAILURE／CANCEL_RECOVER 皆 PASS（c7295f8 後的程式於 11-01 23:52 再跑）；取消完成前整備入口不可用，成功後可再進整備，整備內直接 RPC 仍被拒絕 |
| 配對預約寫入失敗 | `RESERVATION_FAILURE PASS locked until cancellation`，隨後 `RESERVATION_RECOVER PASS` |
| 伺服器儲存拒絕／固定內容 | 等待時 SaveForUser 回覆 REJECTED，保存內容不變；修改取出的 roster 不影響下一次讀取。舊 queue probe 同步改為檢查等待時拒絕修改 |
| 入場版本、DB 邊界與舊資料相容 | roundtrip：`ENTERING fixed slot=3 revision=2; confirmed-only DB; legacy content ignored` |
| 戰鬥 HUD、自身結果、返回失敗及重試 | 既有 result UI probe：`BATTLE_VIEW ... hud=1/1 roster=1/1`、`PASS own WIN counts=1 / 1 vs 0 / 1`、`RETURN_FAILED msg=RETURN_MOVE ok=false`、`RETRY_PENDING`，其後正式返回成功 |
| 兩名玩家返回後保存完整 | `match_flow_roundtrip_runtime_probe.lua`：`PASS five groups; active/version retained; no automatic save; confirmed handoff; both returned`（19:19:57） |
| 返回後再次配對／取消 | `matched_battle_lobby_ui_runtime_probe.lua`：`[VRF][MatchedLobbyUI] PASS` |
| 既有 POC 入口與自然結果 | 從正式大廳 POC 按鈕進入 template，等待卡片建立完成，再執行 `deployment_ui_runtime_probe.lua`：`[M1][DeploymentUIProbe] PASS`；最後這次 Play 的 runtime 0 Error／Warning |
| 儲存失敗／逾時／晚到回覆 | 既有 `editor_save_failure_runtime_probe.lua` 的 FAIL、SILENT、LATE；失敗保留內容、逾時禁止切組與離開、恢復讀取後手動儲存、晚到成功不執行已中止的返回 |
| 晚到預約／取消寫入後重試 | `match_recovery_runtime_probe.lua` 的 RESERVE／CANCEL：修正前兩者皆重現取消重試仍鎖定；修正後 21:02:09／21:02:39 均 `PASS`，已儲存組別、版本及出戰選擇不變 |
| 確認逾時結果後直接放棄返回 | `editor_save_failure_runtime_probe.lua` SILENT phase 3：修正前返回被阻擋；修正後 `NEW`（21:04:10）與 `READY`（21:05:52）皆 PASS，未再次儲存，保存版本不變 |
| 讀取中／讀取失敗不提前解鎖 | `edit_session_runtime_probe.lua`：新增 `CONFLICT`／`LOADING`／`ERROR` 的未確認狀態，以及保留 guard 的 `READY`；修正前 LOADING 失敗，修正後 21:07:08 `[VRF][EditSession] PASS` |
| 返回清理、舊寫入與舊票券 | 重跑 `formation_handoff_failure_runtime_probe.lua`，改用隔離鍵下的本機玩家，額外斷言舊 ticket 不能 Close 新 attempt；21:08:07／21:08:12 兩項 PASS，晚到舊寫入與舊鎖定釋放仍被阻擋 |

本機探針只透過正式 ButtonClickEvent、map input handler 與伺服器服務操作，不代表實體滑鼠點擊。測試前幾次的 FAIL 涉及探針前置狀態：非第一組、尚未完成切圖／讀取、返回 session 尚未還原，以及序列化字串比較。已改為等待可操作狀態與資料還原，並逐欄檢查五組內容、版本與 writeId；保留失敗紀錄，不將派送成功當作 PASS。POC 初次複驗過早讀取 optionsReady 而卡片尚未完整建立，只有卡片數量檢查失敗，其餘部署至自然結果皆通過；重跑需同時等待 optionCards 與 optionData 數量相同。

## 重跑與清理

1. 全新 Play，等待 `maker_get_context_keys` 確認 `server_main`／`client`。將 `_FormationService.StorageKey` 設為唯一的 `Issue52...` 鍵；單玩家等待／取消測試也可隔離 `_FormationHandoff.StorageKey`。
2. 在 client 執行 `editor_save_flow_runtime_probe.lua`，再執行 Flow52 PREPARE。將 `PHASE` 換為 QUEUE；等待最後 PASS 後，在 server_main 注入 `ConfigureMakerFaults(0, 1, 0)`，執行 CANCEL_FAILURE，清除故障後執行 CANCEL_RECOVER。
3. 往返時每個 room 必須使用同一個 handoff key。此次使用原本的 `BattleTransferV2`，只寫本機測試的短期票券；編隊存檔仍使用隔離鍵。新增 `hf2602` 虛擬玩家，從真實 client 大廳按鈕開始並等待 QUEUED，再在 server_main 執行 roundtrip probe。
4. 進房會重設 client context。取得新的 `server_instance_*` key 後，在該 context 設 `ConfigureMakerTransferFaults(0, 1)`，並立即在 client 派送既有 result UI probe，才能看到正在進行的戰鬥。
5. 真實 client 返回後，從該 instance 對 `hf2602` 呼叫 ReturnForUser；主房間 roundtrip coroutine 會等兩者的保存資料都完成還原才驗證。最後在 client 執行 lobby UI probe。
6. 儲存故障探針各使用新的隔離編隊鍵，將 server session 的 editSlot 設為 1，且先返回大廳並清除測試的 local 變更。依既有檔案註解注入 FAIL／SILENT／LATE，完成後將 `ConfigureMakerSaveResponse('', 0)`、`ConfigureMakerFaults(0, 0, 0)`、`ConfigureMakerTransferFaults(0, 0)` 復原，還原兩個預設 StorageKey，Stop Play。沒有清空 DataStorage，也沒有覆寫正式編隊存檔。
7. 恢復修正：單一玩家在大廳時，以 server_main 執行 `match_recovery_runtime_probe.lua`，分別設 `MODE='RESERVE'`／`'CANCEL'`；探針自行建立隔離保存與交接鍵，將 timeout 設為 1 秒、寫入延遲設為 2.5 秒，待晚到寫入完成後直接重試取消，不先呼叫 Read 或 Recover 修復快取。最後自動復原鍵、timeout、故障與選組，讀回原本存檔並等待成功，避免記憶體保留測試隊伍；補上清理後於 21:19:35／21:20:19 複驗兩個模式皆 PASS，且各自記錄 original session reload complete。
8. 放棄返回：隔離的新存檔先執行 SILENT phase 1，清除 acknowledgement fault 後執行 phase 3。再以新隔離鍵透過 SaveForUser 保存第一組一隻 `monster_tank`（-5, 0）、ActivateForUser 啟用，設 `EXISTING=true`，重跑 phase 1／3，涵蓋 `READY`；不得在確認與放棄之間另存一次。此次修正的最終 Play runtime 為 0 Error／Warning，build 維持 0 Error 及兩個既有 Warning。

## 原生視覺與待驗收

已讀取 Maker 原生截圖：大廳、等待／配對預約錯誤、整備、離開確認與勝利結果。確認必要控制項可見、確認選項未被遮住、結果與返回操作分開呈現。截圖在 Maker `McpScreenshots` 目錄：`185159_572`（等待）、`190927_433`（錯誤）、`191633_777`（大廳）、`192106_123`（整備）、`192143_990`（確認）、`191301_077`（結果）；日期前綴均為 `maker_play_20261101_`。戰鬥 HUD 本輪取得 runtime 正向證據，未取得戰鬥進行中的截圖，外觀亦沿用 #51 已確認的版面。

尚未驗收：五個畫面的實體 PC 滑鼠、hover／pressed／disabled 外觀、首次顯示的繪製延遲、較小 PC 視窗、手機，以及失敗／平手結果外觀。Maker mouse_input 工具明示不能點擊標準引擎 UI，不能用 SendEvent 冒充實體點擊。入場傳送失敗與 RETURN_SAVE_FAILED 的本機故障回歸已補上，證據如下；原生服務在發布環境的失敗仍須另外驗收。

發布環境仍須兩個真實帳號、不同 WorldInstance，驗證原生配對續期／取消競態、跨 instance 交接、原生傳送失敗與返回。沒有將本機兩玩家往返當成此項通過。

## 審查

主代理已依 Standards／Spec 兩軸檢視改動與相連程式，包含 RPC 身分、服務端鎖定、取消與 storage yield、舊 attempt／延遲回覆、固定隊伍與 session 還原、UI 群組及 POC 相容性。未新增依賴或替換戰鬥與資料模型。

初版 Spec 子代理確實回覆了 `5fe25f7...5f52e1c` 的報告：未發現範圍擴張，指出實體驗收與入場／返回寫入失敗的驗證缺口，以及取消失敗後仍保留 CANCELLED 的疑慮。這份報告保留作為初版審查，不能當成 `04d313d` 及後續修正的重審。

恢復修正的 Standards 子代理回報無硬性違規，另有狀態判斷重複的維護性建議；測試 session 清理風險已補上原選組與存檔讀回。後續 Spec 呼叫仍回傳舊版報告，且自述新任務為密文，未取得可靠的更新版獨立審查。主代理已逐項核對下列重現與修正；子代理啟動或回傳舊報告均不算更新版審查通過。

## 取消失敗與競態修正（2026-11-01，基線 04d313d）

重現時透過 `ConfigureMakerCancelFaults(1, 1)` 讓共用取消邊界回覆 `InternalError`。修正前 21:46:07 的正式按鈕探針失敗：原隊列被留在 CANCELLED。另於 22:31:44 重現準備中的配對恢復到 COMMITTING 後，取消錯誤仍覆蓋新狀態；已在可繼續入場時清除過期錯誤。

2026-11-01 該輪（c7295f8 之前）Maker Play 的正向證據；其後的審查修正與重跑見下一節：

| 案例 | 探針／結果 |
|---|---|
| 取消回覆失敗、保留原隊列與固定隊伍、重試才解鎖 | `match_cancel_runtime_probe.lua` FAILURE，22:38:33 PASS |
| 已進入 SAVING 後取消成功，提交等待取消、雙方均不入場 | `match_cancel_race_runtime_probe.lua` SUCCESS，22:42:17 PASS；VRF 同時記錄 requested state=SAVING 與 commit waits for cancellation |
| SAVING 途中取消失敗、配對繼續、舊錯誤不蓋住 COMMITTING | 同 server probe 的 SEAL_FAILURE，加 client probe 的 PROGRESS，22:48:40／22:49:04 PASS |
| 取消期間收到配對成功、取消失敗後接續入場，再注入傳送失敗 | server probe ENTRY，22:49:22 PASS；client probe ENTRY，22:49:48 PASS，原因可見且正式取消入場按鈕還原大廳 |
| 自然戰鬥結束後，返回資料寫入失敗仍保留結果並提供重試 | `matched_battle_return_save_runtime_probe.lua`，22:51:55 PASS；22:56:24 確認已回大廳 |
| 既有晚到預約／取消寫入恢復 | 重用 `match_recovery_runtime_probe.lua`，篩選非 hf2602 的本機玩家，其餘流程不變；22:56:28／22:57:25 PASS |
| 斷線清理指令遇到取消失敗，不能寫入假取消終態 | `match_cancel_disconnect_runtime_probe.lua`，22:59:56 PASS；最後在同一取消邊界確認成功後清理票券 |
| 清理與診斷 | 23:02:49 所有故障、StorageKey 復原，原 session 讀回成功；runtime 0 Error／Warning，Maker build 0 Error、兩個既有 Warning；contract suite 53/53；client LSP 0 Error／Warning，server 仍只有既有原生事件定義缺失的 10 個診斷 |

重跑先以唯一的 FormationService.StorageKey，透過既有 Load／SaveForUser／ActivateForUser 建立一隻合法單位的第一組出戰隊伍；此輪使用 monster_warrior，站位 (-5, 0)。新增 hf2602 後須等其實體及原票券恢復完成，再用相同隔離鍵建立同樣隊伍。跨 room 的 Handoff.StorageKey 維持預設 BattleTransferV2。每個 race 模式跑完才開始下一個；SEAL_FAILURE 的 client PROGRESS 先派送，server timer 透過同一 StateForUser 觀察 SAVING 後才取消，不靠固定延遲猜階段。

ENTRY 保留移動故障直到 client 完成可見的取消入場，之後重設 ConfigureMakerTransferFaults(0, 0)，並由 ReturnForUser 還原另一位參與者。正常配對後，先把新 instance 的 FormationService.StorageKey 設成同一隔離鍵，等雙方入場後注入 ConfigureMakerFaults(0, 1, 0)，再執行返回存檔故障探針。斷線清理探針最後才執行，僅呼叫正式 Depart 指令，不代表真實網路斷線已驗證。最後重設所有取消／傳送／儲存故障、還原兩個 StorageKey、Load 原 session，再 Stop Play；沒有清空 DataStorage 或寫入原本的隊伍存檔。

前幾次延遲探針曾在準備階段尚未開始、票券仍寫入或虛擬玩家尚未建立時取值，屬前置狀態不足。已改成等待 StateForUser 的 SAVING、確認寫入完成與實體就緒，最後一輪全部通過。實體操作、真實網路斷線、兩個真實帳號及跨 WorldInstance 原生取消競態仍未驗收。

提交前複查另補兩處。重連後的取消若與 `Depart` 在途的取消重疊，修正前 `match_cancel_reconnect_runtime_probe.lua` 於 23:21:59 失敗，鎖定不會解除；現在由 `Depart` 擁有該票券，新的取消不再重入，23:24:50 PASS。重試取消開始時也清除前次失敗，途中不再顯示失敗文案：`match_cancel_runtime_probe.lua` FAILURE 新增斷言，23:24:38 PASS；這項沒有取得修正前的有效紅燈。同一輪 `match_recovery_runtime_probe.lua` CANCEL 也重跑。

### 雙軸審查後的修正（基線 36dc7b6、c7295f8）

第一輪（`04d313d...36dc7b6`）Standards／Spec 子代理報告都核對過基線，指出三個問題，已在 c7295f8 修正：

- 只有持久票券、沒有 live record 時，`CancelForUser` 會提前返回並留下 `busy`。現在只有另一張 live 票券才算被取代。
- `Depart` 取消失敗後票券被清掉，重連玩家在原生佇列可能仍存活時已解鎖。現在大廳重連會走 `Recover` 重新鎖定持久票券；對局房間的重連仍不重新入場。
- 重連時 `Depart` 還在等回覆，client 會停在舊狀態。現在清理結束後由 `Recover` 發布結果。

`match_cancel_reconnect_runtime_probe.lua` 擴充後在修正前重現紅燈（2026-11-01 23:33:03，`locked=false` 且持久狀態未到 CANCELLED）。

第二輪（`04d313d...c7295f8`）Spec 子代理指出兩個重大缺失，根因相同：`Depart` 的原生取消失敗時丟棄票券。

- 已重連的線上玩家，延後的配對回覆（`matchPending`）隨票券遺失。
- 票券丟棄後，`Recover` 讀取失敗就發布 `IDLE`，取消未確認即解鎖。

現在取消失敗時保留票券並維持鎖定。`ResumeDeferredMatch` 讓 `CancelForUser`、仍在線的 `Depart` 與 `Recover` 接續同一張票券；續期計時器等待 `ticket.cancelling`；大廳重連時 `Recover` 後再發布狀態。同時修正固定寫 `online=false` 的 VRF 值與過期註解。新增 `RECONNECT_MATCH` race 模式，修正前紅燈（23:49:24，`durable=CANCELLED live=IDLE locked=false`，回覆已遺失）。

第三輪（HEAD c7295f8 加這批修正）Spec 子代理結論為無重大缺失。它另列出、未修改的低到中風險：取消失敗後才到達的回覆，離線票券會轉 `QUEUE_ERROR`，玩家須手動取消（原生回 `AlreadyMatched` 時對手端落空）；離線且取消失敗的票券留在記憶體；`RENEWING` 的票券不自動續期。三者都有手動取消可走，不違反「取消失敗不提前 CANCELLED、回覆不遺失、確認前不解鎖」，須在發布環境確認。

#### 驗證證據

修正後（程式自 11-01 23:51 起未再變動）：

| 案例 | 探針／結果 |
|---|---|
| 重連的四個情境（OVERLAP、DURABLE、FAILED_ONLINE、FAILED_OFFLINE） | `match_cancel_reconnect_runtime_probe.lua`，11-01 23:51:19–23:51:25 PASS；client 讀回 `IDLE`（23:51:37，由 client 端人工讀取，不是已提交的斷言） |
| flow CANCEL_FAILURE／CANCEL_RECOVER、cancel FAILURE | 11-01 23:52:28／23:52:35／23:52:45 PASS |
| 恢復 RESERVE／CANCEL | `match_recovery_runtime_probe.lua`，11-02 19:27:52／19:27:59 PASS |
| 重連後取消失敗，回覆接續 | race RECONNECT_MATCH，19:29:35 PASS；log 依序為 deferred → native InternalError → resume pending match |
| SAVING 取消成功／失敗、入場移動失敗 | race SUCCESS／SEAL_FAILURE／ENTRY，19:30:09／19:30:43／19:31:27 PASS；client PROGRESS／ENTRY，19:30:19／19:31:31 PASS |
| 自然戰鬥後返回存檔失敗、重試 | `matched_battle_return_save_runtime_probe.lua`，19:32:27 PASS，隨後 RETURNED（19:32:29） |
| 斷線清理遇取消失敗 | `match_cancel_disconnect_runtime_probe.lua`，19:35:16 PASS |

11-02 該輪 runtime 共 775 筆 log，全為 Info，無 Error／Warning。Maker build 0 Error，僅既有的 `IsPCPlatform` 一個 Warning；contract suite 53/53。

#### 範圍與限制

- 重連、flow、cancel 三組探針在重啟前的 Play（11-01）通過，程式未變，重啟後沒有重跑。其餘為重啟後的 11-02 結果。
- Maker 上執行的是探針的內嵌版本，等待時間、fixture 與清理依 Play 狀態調整，斷言與已提交檔案相同；`hf2602` 須等玩家加入後才能建立 fixture。
- 11-02 的返回存檔探針，房間 instance 沒有設定隔離的 `StorageKey`，用的是預設 `BattleFormationsV2`。探針沒有呼叫儲存，事後讀回原本玩家的存檔為第 2 組出戰、版本 6，不是 fixture 的第 1 組、版本 1，所以未被覆蓋；但沒有與測試前逐欄比對。重跑時須先對該 instance 設隔離鍵。
- `UserReconnectEvent` 的派送不等於真實網路斷線。Maker adapter 會關閉過期佇列，原生 adapter 的 `QUEUE_OWNER_LOST` 路徑沒有執行。
- 原生取消回 `AlreadyMatched` 仍視為確認完成。對手可能停在入場狀態直到逾時或手動取消入場，須於發布環境以兩個真實帳號確認。
