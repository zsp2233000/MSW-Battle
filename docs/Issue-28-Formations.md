# Issue #28 — 個人功能大廳與第一組編隊

進入世界後顯示個人功能大廳；「編隊整備」前往 `formationsim`。選擇正式兵種卡、點選站位加入單位；左側單位列可選取單位，再點格子移動，亦可移除。每格代表一個世界單位，以中央為相對原點。第一組可完整編輯；其餘四組保留穩定編號，留待後續開放。

「儲存第一組」和「設為出戰編隊」分開。後者只使用已確認保存的第一組，不包含草稿。大廳的「進入既有戰鬥 POC」仍可進入 `map01`；本票沒有 AI 試打、配對或戰場套用功能。

## 資料與故障契約

- 使用伺服器從 `senderUserId` 找到的玩家 `ProfileCode`，存入該玩家的 `UserDataStorage` / `BattleFormationsV1`。所有 Client RPC 以擁有者為目標，不廣播或同步私人資料；客戶端不能傳入其他玩家身分。
- JSON schema 1 包含 `revision`、`activeSlot`（0 表示未選）及字串鍵 `1`–`5` 的五個欄位；每欄包含穩定 `id`、保存 `revision` 和 `units`。單位只保存 `monsterId`、`x`、`y`。能力值及外來欄位不會進入保存內容。
- 正式 `MonsterCatalog.IsLoaded` 只在整張資料表驗證成功後成立。草稿驗證接受 0–6 個單位，保存要求 1–6；同兵種可重複。相對範圍 X=-3..3、Y=-2..2，最小距離 0.6。未知 ID、稀疏／非陣列、超量、非數字、NaN、無限值及非法站位整批拒絕。
- 同次登入的草稿放在世界生命週期 `FormationService` 中，切換地圖不重建；離開登入不自動保存草稿。重新登入只讀取成功保存內容。沒有自動儲存 timer。
- UI 分辨未保存、儲存中、保存成功及儲存失敗；載入中、首次使用、讀取失敗另有提示。找不到 key（含 Maker 的成功但 nil）是首次使用；其他讀取錯誤、無效 JSON 或 schema 不相容不會寫入空資料。
- 每筆寫入保留獨立內容與草稿版本快照，只有原生持久儲存成功回覆才更新確認內容。寫入途中仍可編輯；舊成功只確認舊版本，目前草稿仍顯示未保存。重複／過期儲存命令不會排入較晚的盲寫。
- 每個 profile 有世界內寫入序列鎖及跨 instance 的 shared-memory creation guard。所有寫入都須取得 guard；新增 key 前在 guard 內重讀，既有 key 使用原生 `UpdateAsync(expectedRaw, newRaw)`。讀到別人已建立的 key 時拒絕舊的新增請求，要求重新讀取。
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

本地契約：`node --test tests/*.test.cjs`。Maker 探針皆經正式 RPC／已連接 ButtonClickEvent 操作，觀察 `FormationLobby.Snapshot`，不改寫 session 私有欄位。

| 探針 | Context／程序 | 證據 |
|---|---|---|
| `formation_flow_runtime_probe.lua` | client；新 Play，等待載入；大廳 → 模擬地圖，放置、重複兵種、移動、保存、獨立出戰選擇、再編輯、跨圖 | `[VRF][FormationFlow] PASS` |
| `formation_relogin_runtime_probe.lua` | flow 後 Stop → Play；client；確認兩個保存單位，草稿第三個單位不恢復 | `[VRF][FormationRelogin] PASS` |
| `formation_failure_runtime_probe.lua` | server 先 `ConfigureMakerFaults(1,1,1)`；client 探針；讀取失敗、重試、寫入失敗、重新讀取對帳及重試保存 | `[VRF][FormationFailure] PASS` |
| `formation_delayed_runtime_probe.lua` | server 先 `ConfigureMakerFaults(0,0,2)`；client；保存中再編輯、拒絕重複保存、舊回覆不清除新草稿、再保存新版本 | `[VRF][FormationDelay] PASS` |
| `formation_validation_runtime_probe.lua` | client；未知 ID、非法座標、數字字串、重疊、超量、稀疏陣列及過期命令 | 執行結果待最終紀錄 |
| `formation_storage_runtime_probe.lua` | server_main；正式 catalog 的非有限值／能力白名單／空欄位序列化；原生持久儲存的延遲首次建立與過期 CAS；只刪除此探針建立的獨立測試 key | 執行結果待最終紀錄 |

`ConfigureMakerFaults` 僅 ServerOnly 且有 `Environment:IsMakerPlay()` gate，發布環境不能啟用。測試後重設 `(0,0,0)`。失敗注入只替換儲存邊界回覆，不替換正式 UI、草稿驗證或保存狀態機。原生儲存另以 storage probe 檢驗，不將注入測試當成原生失敗證據。

本票同時重新執行既有部署與自然六對六戰鬥探針；最終結果與本地測試數待最終紀錄。實際滑鼠視覺可讀性、第二名真實客戶端及發布環境多 instance 屬後續人工驗證邊界。
