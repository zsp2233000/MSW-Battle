# #50 五組編隊的單組儲存、出戰與離開確認

沿用 [#49](./Issue-49-Editor.md) 的整備介面與 Cardgame 素材，依 2026-10-31 確認的新規則改寫編輯資料邊界。理由與舊規則的廢止範圍記錄在 [ADR 0003](./adr/0003-persist-formations-before-live-pvp.md) 的 2026-10-31 修訂；詞彙見 [CONTEXT.md](../CONTEXT.md)「未儲存變更」。

## 資料邊界

| 內容 | 位置 | 說明 |
|---|---|---|
| 已儲存編隊（五組）與出戰選擇 | 伺服器 session 與 DataStorage | 唯一權威。只有儲存成功或設為出戰成功才改變 |
| 未儲存變更 | 只在編輯者的 client（`FormationLobby.Draft`） | 不進伺服器 session、DataStorage 或配對交接資料；放置、移動、移除、切組都不產生 DB 寫入，也沒有任何伺服器往返 |
| 本局編隊 | 配對時固定，不隨編輯或儲存改變 | 不變 |

`*` 由內容比較決定：目前組的內容與已儲存版本不同即為有變更，還原成相同內容立即消失；未修改的空組沒有 `*`，清空原本有單位的組別有 `*` 但不能儲存。client 以 1e-6 容差比較座標（JSON 往返可能改變末位）。

## 命令與事件（伺服器）

- `FormationService.RequestSave(units, slotId, expectedRevision, requestId)`：取代 `RequestDraft`／`RequestSave(version, slot)`。伺服器以 RPC 傳送者決定身分，驗證怪物、一至六個單位、站位與間距（`ValidateUnits`，與 client 共用 `ValidateShape`），要求 `expectedRevision` 等於目前已儲存版本，只改該組並以 CAS 寫入。儲存非出戰組不會啟用它。
- 回覆走快照的 `result = { requestId, kind, slotId, status, code }`，`status` 為 `OK`／`REJECTED`／`FAILED`／`UNCONFIRMED`。明確失敗與拒絕都有真實原因文字；逾時為 `UNCONFIRMED`（寫入可能已提交），進入 `CONFLICT` 並保留延遲回覆防護。
- 已移除：`RequestDraft`、`UpdateDraftForUser`、`AutoSaveForMatch`、`drafts`／`draftVersion`／`savedDraftVersion`／`saveState` 等快照欄位、`MatchProbe.ReceiveState` 與 `MatchProbeInput.Observe` 的自動儲存提示參數、MatchGroup 的 `EditorMatch` 面板。
- 交接（`FormationHandoff`）只含已儲存編隊、出戰選擇、本局編隊、版本與必要配對狀態；`Seal` 不再儲存，`Capture` 不含草稿。舊的在途紀錄若仍帶 `drafts`，驗證時不再要求、讀取時忽略。

## client 行為

- 儲存：一律可見；沒有變更、載入中、內容無效、處理中或結果未確認時反灰並在狀態列說明原因；有效變更時以原生 ColorTint 的醒目色顯示。儲存中顯示「儲存中…」並暫停編輯、切組與離開。
- 切組／返回：有變更時詢問（儲存並切換／不儲存切換／繼續編輯；儲存並返回／不儲存返回／繼續編輯），沒有變更直接完成。確認視窗的儲存只處理當組，成功後才完成原操作；內容無效時儲存選項反灰，仍可捨棄或繼續編輯。
- 結果未確認：只有帶有該次 `requestId` 的回覆能完成延遲的切組或返回；逾時、失敗或 client 十五秒看門狗都會丟棄該動作，之後晚到的成功只更新已儲存內容，不會再跳轉。`CONFLICT` 且逾時未確認時，儲存、切組與返回全部停用，「確認結果」（重新讀取）是唯一出口；讀回後以內容比較決定是否仍有變更。
- 組別辨識：目前編輯組有金色特效框（`EditFrame`：低透明度填色加四條 8px 邊條，只有邊條脈動，填色維持 `.ui` 的值），出戰組有「出戰」徽章；兩者都在 `.ui` 內由 Maker 管理，大廳與整備各一份。第一版的脈動曾改寫填色透明度，原生截圖發現會蓋住組別文字，已改正並加入契約。
- 設為出戰：已出戰組、有變更、內容無效、處理中、載入未確認時反灰；先儲存成功才能設為出戰。
- 滑鼠殘影：新增與移動都顯示所選怪物的半透明殘影（獨立的 client 實體，不計入人數、碰撞或選取目標），合法位置保留原色、不合法位置為紅色；與實際本機操作共用 `CanPlaceAt`（左半場、可行走與鏡射後合法地形、0.3 間距、最多六個單位、移動時排除自身）。滑鼠在 UI 上時隱藏。有殘影時左鍵只嘗試提交操作，不會切換選取；右鍵只取消殘影，沒有殘影時才移除單位。
- 預設選取與單位選取：編輯器開啟時預設選著第一張怪物卡，所以預設就有殘影；依規格，有殘影時左鍵只嘗試提交操作，因此要先按右鍵取消殘影，才能點場上單位選取或移動（說明文字已寫明）。若希望一開啟就是「未預覽」，需要改預設選取，這會影響右側情報預設顯示，未在本票處理。
- 怪物卡：一般與選取的卡框由 `.ui` 模板管理（模板根節點為變暗的一般框，`SelectedFrame` 為排在裝飾下方的亮框），`Render` 只切換啟用狀態，不再寫入任何卡框素材。

## 驗證紀錄

2026-10-31，原生 Maker，Refresh 後 build 無 Error（沿用兩項既有 Warning：`IsPCPlatform`、`BattleViewAvatar`）；各輪 runtime 無 Error／Warning。

| 檢查 | 證據 |
|---|---|
| 本機契約 | `node --test tests/*.test.cjs`：40/40（先前 33，新增 7 項 #50 契約） |
| UIBuilder strict lint | FormationGroup 205 entities、MatchGroup 13 entities；FormationGroup 維持既有三項 Warning（兩項 L004、一項 L016），MatchGroup 無 |
| 正式流程 | `editor_save_flow_runtime_probe.lua` PASS（S1–S10）：初始反灰、本機編輯無伺服器往返、`*` 與精確還原、0.29／0.30／敵方半場／鏡射牆／六人上限／移動排除自身、切組三種選擇、儲存並切換只改當組且不啟用、設為出戰、空組與無效內容、返回三種選擇、乾淨返回不詢問 |
| 明確失敗 | `editor_save_failure_runtime_probe.lua`（FAIL）：伺服器 `code=1000001`，client `FAILED`，內容與 `*` 保留、停留原組、提供「重試讀取」、無自動重送；重置後手動重試儲存成功並清除 `*` |
| 逾時未確認 | （SILENT）：5 秒後 `code=1000004`，client `UNCONFIRMED`；儲存、返回、切組都被擋，提供「確認結果」；重置、確認後可再儲存 |
| 延遲回覆 | （LATE 9 秒）：「儲存並返回」5 秒逾時被中止，第 9 秒晚到成功，不跳轉，`*` 依內容比較消失 |
| 殘影與卡片 | `editor_preview_cards_runtime_probe.lua` PASS：卡框只在選中卡顯示、模板卡框素材未被覆寫、移入提示不改選取、重建後舊卡銷毀且選取與框依 MonsterId、殘影合法 `1,1,1,0.55`／不合法 `1,0.25,0.25,0.55` 且不計入人數、右鍵取消殘影不移除、取消移動保留原站位、無殘影時右鍵移除 |

| 原生畫面 | Maker play 截圖（1920×1080 參考畫布）：組別按鈕 `第 1 組 *`、摘要列 `第 1 組 * / 已保存 2/6`、狀態列「有未儲存變更 *」、「出戰」徽章；儲存按鈕為醒目金色而「設為出戰」反灰；選中怪物卡為亮金框加勾選、其餘為暗框；確認視窗顯示標題、說明與三個 Cardgame 按鈕，置中、不裁切、未被其他群組遮擋。加粗前的特效框填色確實蓋住文字，已修正 |

探針使用唯一的隔離儲存鍵（`_FormationService.StorageKey`），故障注入以 `_FormationStorage:ConfigureMakerSaveResponse` 設定並在結束時重置為 `''`，未覆寫既有存檔。分段執行失敗路徑時，派送的是只含該模式分支的探針文字，檔案本身保留全部分支。

## 退役與更新的探針

退役（驗證的行為已不存在）：`formation_flow`、`formation_failure`、`formation_delayed`、`formation_validation`、`formation_empty_return`、`formation_slots_runtime`／`_delayed`／`_failure`／`_save_failure`／`_relogin`、`formation_relogin`、`lobby_draft`、`lobby_pending`、`lobby_load_failure`、`editor_flow`、`editor_failure`、`editor_native_input`、`centered_formation`、`centered_transfer_validation`、`formation_handoff_late_leave`。其涵蓋的情境由上表的新探針取代；Issue 29、48、49 文件中對這些探針的記載屬歷史紀錄。

退役後不再有 runtime 探針覆蓋的情境（伺服器程式仍在）：登入後帶著「未確認的寫入」重新讀取、`formation_handoff_late_leave` 的交接晚離開競態、讀取逾時（`lobby_load_failure`）。「逾時後晚到的成功」改由新的 LATE 探針覆蓋，其餘請在 #52 的往返驗收補測。

已更新但本輪未重跑（需要雙玩家配對環境，歸 #52 的完整往返驗收）：`formation_handoff_fixture`／`_runtime`／`_failure`、`matched_battle_queue`、`matched_view_setup`（夾具改用新的 `SaveForUser`，並以「交接不含未儲存內容」「還原後伺服器不保留草稿」取代原斷言）。`editor_authoring`（移除 EditorMatch）與 `editor_intel`（讀取 `Draft`）已更新，本輪未重跑。

## 人工驗收邊界

`maker_mouse_input` 不能移動作業系統游標，也不會點擊引擎管理的 UI，且不發出右鍵 `KeyDownEvent`。因此以下沒有實測，請用實體 PC 滑鼠確認：

- 殘影跟隨游標、移動時即時換色、離開世界進入 UI 時隱藏、回到世界後恢復（殘影的顏色與規則以直接指定世界座標的 `ShowGhost` 驗證；跟隨游標的那一行呼叫與它相同）。
- 右鍵取消與移除在實體滑鼠上的行為、距離 0.29／0.30／0.49／0.50／0.51 的實際點擊、UI 點擊不穿透到世界。
- **確認視窗首次開啟的繪製延遲（未解決）**：每次 Play 後第一次開啟確認視窗，曾有一次截圖只看到標題、說明與三個選項的文字，底板與按鈕外框稍後（約數秒內）才出現；重新開啟時立即正常。節點屬性（啟用、圖像、顏色、尺寸）在延遲期間都正確，判斷是從未啟用過的 UI 子樹在第一次啟用時才建立繪製。已排除排序問題：`OverrideSorting` 在 runtime 唯讀，`OrderInLayer` 只在 World UI 模式可寫（寫入會被 `LWA-3047` 拒絕），因此未加任何排序程式。可能的處理是讓 `ExitConfirm` 在編輯模式預設啟用並於 `OnBeginPlay` 隱藏（與 `Editor` 相同），但這會讓確認視窗在 Maker 編輯畫面蓋住整備介面，需由你決定。請在實體 PC 上確認首次開啟的外觀。
- 組別特效框的實際醒目程度：以 8px 不切片邊條與低透明度填色實作並在畫面確認文字可讀，但邊條的金色在截圖中偏淡，可由你在 Maker 內直接調整 `EditFrame` 各節點的顏色與粗細。
- 較小 PC 視窗與手機版面。
- 以 UIBuilder 修改卡框模板、Refresh 後確認兩種狀態沿用設定，再還原測試修改（本輪以「Render 不覆寫模板素材」與契約測試取代）。
- 超出可見數量的目錄（18 筆夾具）與原生滾輪的回歸（#49 的 guarded fixture 本輪未重跑）。
- 雙玩家配對、等待時鎖定編輯與完整對戰往返：歸 #52。
