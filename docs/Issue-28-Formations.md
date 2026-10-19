# Issue #28 — 個人功能大廳與第一組編隊

進入世界後顯示個人功能大廳；「編隊整備」前往 `formationsim`。選擇兵種後，直接左鍵點地圖放置；點單位選取，再點空地移動，右鍵或「移除選取」可移除。「單位清單」可展開六個單位的座標。位置使用連續世界座標，不吸附固定格子。模擬地圖沿用 map01 的地形與相機，後續地圖依照 [地圖與編隊規範](Map-Formation-Standard.md) 製作。第一組可完整編輯；其餘四組保留穩定編號，留待後續開放。

「儲存第一組」和「設為出戰編隊」分開。後者只使用已確認保存的第一組，不包含草稿。大廳的「進入既有戰鬥 POC」仍可進入 `map01`；本票沒有 AI 試打、配對或戰場套用功能。

## 資料與故障契約

- 使用伺服器從 `senderUserId` 找到的玩家 `ProfileCode`，存入該玩家的 `UserDataStorage` / `BattleFormationsV1`。所有 Client RPC 以擁有者為目標，不廣播或同步私人資料；客戶端不能傳入其他玩家身分。
- JSON schema 1 包含 `revision`、`activeSlot`（0 表示未選）及字串鍵 `1`–`5` 的五個欄位；每欄包含穩定 `id`、保存 `revision` 和 `units`。單位只保存 `monsterId`、`x`、`y`。能力值及外來欄位不會進入保存內容。
- 正式 `MonsterCatalog.IsLoaded` 只在整張資料表驗證成功後成立。草稿驗證接受 0–6 個單位，保存要求 1–6；同兵種可重複。範圍由 map01 真實地形推導，目前世界邊界 X=[-15,14)、Y=[-5,3)，最小距離 0.3；伺服器另外檢查落點地塊存在且不可碰撞。保存保留小數，不做格子吸附。未知 ID、稀疏／非陣列、超量、非數字、NaN、無限值及非法站位整批拒絕。
- 舊保存內容若落在牆上，仍可載入並逐一搬離或移除；未修正前不能重新保存或設為出戰，不自動改寫保存內容。
- 同次登入的草稿放在世界生命週期 `FormationService` 中，切換地圖不重建；離開登入不自動保存草稿。重新登入只讀取成功保存內容。沒有自動儲存 timer。
- UI 分辨未保存、儲存中、保存成功及儲存失敗；載入中、首次使用、讀取失敗另有提示。找不到 key（含 Maker 的成功但 nil）是首次使用；其他讀取錯誤、無效 JSON 或 schema 不相容不會寫入空資料。
- 每筆寫入保留獨立內容與草稿版本快照，只有原生持久儲存成功回覆才更新確認內容。寫入途中仍可編輯；舊成功只確認舊版本，目前草稿仍顯示未保存。重複／過期儲存命令不會排入較晚的盲寫。
- 每個 profile 有世界內寫入序列鎖及跨 instance 的 shared-memory guard。以 CreateVariable 首次建立，或以 ETag CAS 從 free 取得所有權；釋放亦以持有的 ETag CAS 回到 free，不刪除或搶占其他寫入者的鎖。新增 key 前在 guard 內重讀，既有 key 使用原生 `UpdateAsync(expectedRaw, newRaw)`。讀到別人已建立的 key 時拒絕舊的新增請求，要求重新讀取。
- guard 清理失敗會保留原所有權 ETag，於下一次讀取／寫入重試；即使前次清理逾時後其實成功，過期 ETag 也不能解鎖新的持有者。
- 無條件首次寫入若結果不確定，保留 guard，避免後續寫入被延遲的首次寫入覆蓋；擁有該 guard 的 instance 重新讀到該次寫入的完整相同內容後才可釋放。guard 不以時間到期或搶占解除。若儲存服務持續無法確認首次寫入結果，保存會維持失敗且保留草稿；不能把此狀態顯示成成功。
- 明確寫入失敗保留原版本及草稿；先重新讀取對帳，再重試保存。MSW 的 JSONEncode 不支援空 Lua table，序列化明確輸出未使用欄位的空陣列 `[]`。

## 套件採用評估與衝突處理

查核官方 MSWPackages README 與 PlayerData 範例原始碼，沒有整包匯入。

| 候選 | 採用範圍 | 必要補強／排除原因 |
|---|---|---|
| [PlayerData](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/README.md)、[PlayerDBManager](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/MyDesk/PlayerDataPackage/Sample/PlayerDBManager.mlua)、[PlayerData source](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/MyDesk/PlayerDataPackage/Sample/PlayerData.mlua) | 重用伺服器 ProfileCode → UserDataStorage、分離資料／儲存責任及載入完成 gate 的模式；本遊戲實作 FormationSchema／FormationStorage／FormationService | 範例組裝資料時清除 dirty，且沒有完整保存確認／版本保護。本票改為回覆確認、獨立寫入版本、CAS、跨 instance 首次寫入 guard。未匯入貨幣／封鎖／管理工具、F3–F6 熱鍵與範例彈窗，避免干擾現有 UI 與玩家生命週期。 |
| [CardGame UI](https://github.com/MSW-Git/MSWPackages/blob/main/ui-resource-cardgame-package/README.md) | 使用工作區已匯入的 `UIR_CardGame_Sample_LobbyModule` 作為入口結構參考，重用 CardButton 的 `9505617fb63c447c8ff9c15c18d88064` 按鈕資源；配合既有 BattleGroup 的面板資源 `6e8e561a4582462eaad762cb11d1f835` | 原 Sample 含商店／頻道／卡片等不屬本票的入口，沒有保存邏輯。由 UIBuilder 建立獨立 FormationGroup，不複製 sample UUID、腳本或未實作入口。 |
| [UI Component](https://github.com/MSW-Git/MSWPackages/blob/main/ui-component-package/README.md) | 評估後本票不匯入 | 原生 Button、ScrollLayoutGroup 與文字狀態足夠。Spinner 只表達等待，不提供持久儲存確認；不引入額外模型、識別與腳本依賴。 |

新增 UI／地圖的實體 UUID 均由 builder 重新產生；保留原有匯入套件與 BattleGroup。使用 `Formation*` 名稱與專用 storage key，未複製 PlayerData 的現有識別。兵種縮圖來自正式 catalog 的既有註冊 RUID，以 `thumbnail://` 顯示。UIBuilder lint 無錯誤／警告。

跨 instance guard 的依據為官方 [World Instance Communication](https://maplestoryworlds-creators.nexon.com/en/docs?postId=999) shared variables；其範圍不同於單一 room。Maker 原生 probe 已確認首次 CreateVariable 成功、再次建立回傳 AlreadyExists。正式發布後的雙 instance 斷線／重登與儲存服務逾時仍需在發布環境追加驗證；Maker 單一 instance 不能取代此證據。

## 驗證

本地契約：`node --test tests/*.test.cjs`。Maker 探針經正式 RPC／已連接 ButtonClickEvent／地圖輸入方法操作，觀察 `FormationLobby.Snapshot`，不改寫 session 私有欄位。

| 探針 | Context／程序 | 證據 |
|---|---|---|
| `formation_flow_runtime_probe.lua` | client；新 Play，等待載入；大廳 → 模擬地圖，放置、重複兵種、移動、保存、獨立出戰選擇、再編輯、跨圖 | `[VRF][FormationFlow] PASS` |
| `formation_relogin_runtime_probe.lua` | flow 後 Stop → Play；client；確認兩個保存單位，草稿第三個單位不恢復 | `[VRF][FormationRelogin] PASS` |
| `formation_failure_runtime_probe.lua` | server 先 `ConfigureMakerFaults(1,1,1)`；client 探針；讀取失敗、重試、寫入失敗、重新讀取對帳及重試保存 | `[VRF][FormationFailure] PASS` |
| `formation_delayed_runtime_probe.lua` | server 先 `ConfigureMakerFaults(0,0,2)`；client；保存中再編輯、拒絕重複保存、舊回覆不清除新草稿、再保存新版本 | `[VRF][FormationDelay] PASS` |
| `formation_validation_runtime_probe.lua` | client；未知 ID、非法座標、數字字串、重疊、超量、稀疏陣列及過期命令 | `[VRF][FormationValidation] PASS` |
| `formation_terrain_runtime_probe.lua` | server_main；29×8 世界邊界、小數落點、牆壁、舊保存逐一修復與完整保存驗證 | `[VRF][FormationTerrain] PASS` |
| `formation_storage_runtime_probe.lua` | server_main；正式 catalog 的非有限值／能力白名單／空欄位序列化；原生持久儲存的延遲首次建立與過期 CAS；釋放失敗後恢復；只刪除此探針建立的獨立測試 key | `[VRF][FormationStorage] PASS` |
| `formation_poc_regression_runtime_probe.lua` | server_main；先由大廳的正式入口進入 map01，再依當前 authored bounds 檢查部署／重複兵種／移除／容量 | `[VRF][FormationPOC] PASS` |
| 既有 `six_vs_six_full_battle_probe.lua` | 延續上列乾淨部署狀態；原探針不修改；自然十二單位交戰、唯一合法 RESULT，結算後一秒無攻擊／損血／移動 | `[M1][SixVsSixFullBattle] PASS` |

`ConfigureMakerFaults` 僅 ServerOnly 且有 `Environment:IsMakerPlay()` gate，發布環境不能啟用。測試後重設 `(0,0,0)`。失敗注入只替換儲存邊界回覆，不替換正式 UI、草稿驗證或保存狀態機。原生儲存另以 storage probe 檢驗，不將注入測試當成原生失敗證據。

2026-10-19 地圖放置修訂紀錄：Maker build 有 79 筆 Info、零 Error／Warning。地圖 flow、terrain、validation、relogin、failure、delay、storage 與既有部署 POC 的 runtime 探針均 PASS。保存與重新登入還原的第一單位為 (-5.25,-0.35)，證明小數及舊格子外座標不會被吸附。離開模擬圖會清理預覽，返回會重建；伺服器無法找到客戶端預覽實體。UI lint 零 Error／Warning。Standards 與 Spec 審查均無剩餘問題。

實際 `maker_mouse_input` 已驗證：螢幕 (900,650) 經相機轉換為世界 (-2.071249961853,-0.65296268463135)，新增單位的草稿與預覽版本同步增加；點擊工具列覆蓋區域不改變草稿。截圖用於確認滑鼠落點及工具列未遮住主要地形。原生右鍵 `KeyDownEvent` 無法由 Maker 滑鼠模擬器產生，需以實際 PC 滑鼠追加驗證；同一移除處理方法已經 flow 驗證，也提供工具列移除按鈕。原始自然 6v6 證據來自先前 #28 驗證，本次另重跑部署 POC；最後停止 Play 回到編輯模式。

本地 `node --test tests/*.test.cjs` 為 **25/28 通過**；編隊契約 **5/5 通過**。三項既有失敗與本票無關，對應檔案與修訂前 HEAD 完全一致：

- `battle_session_contract.test.cjs` 的相機契約仍要求舊 `CameraZoomPercent`／`CameraOffset` 腳本欄位；當前 `BattleFixedCamera` 改為使用 Maker 保存的 CameraAnchor 設定。
- 同檔的部署來源斷言仍要求 `DeploymentMinDistance = 0.6`；當前值為 0.3，且部署範圍由 Arena 設定。舊 `deployment_runtime_probe.lua` 也硬編舊範圍，因此改以新增的 public-boundary 部署回歸探針檢查當前 authored bounds，未改動戰鬥程式或舊測試。
- `monster_catalog_variant_fixture.test.cjs` 仍要求正式 Tank HP 500；當前正式資料是 300。

這些 baseline 斷言保留待另票更新；未為讓測試通過而改動既有相機、部署設定或平衡資料。第二名真實客戶端及發布環境多 instance 屬後續人工驗證邊界。
