# Issue #29 — 五組預存編隊與獨立出戰選擇

遊戲大廳及模擬地圖均提供固定的第一至第五組按鈕。每組標示目前編輯、出戰、空欄位或已保存數量與版本；另標示有草稿、保存失敗及等待儲存／出戰確認。切換只改變目前編輯組，所有組別的草稿在同次登入及跨圖操作中保留。切換組別會清除單位選取並刷新地圖預覽。

「儲存目前組」只更新該組已保存內容與版本。「設為出戰編隊」只使用目前組已確認保存且站位有效的版本，並在持久寫入成功回覆後更新出戰選擇。未保存的新編輯不會被此操作一併保存；其他組可留空，只要一組有效已保存編隊即可設為出戰。本票沒有加入配對或戰場套用。

## 資料與版本

沿用 #28 的 `UserDataStorage`／`BattleFormationsV1`、schema 1、五組字串鍵及 CAS 寫入防護，舊的第一組保存資料可以直接讀取。伺服器仍從 RPC 的 `senderUserId` 決定玩家身分；私人觀察只傳給擁有者。

每組獨立保存草稿、草稿版本、已確認草稿版本與保存狀態。公開 Snapshot 的 `editSlot` 指定目前組；`draft`／`draftVersion`／`savedDraftVersion`／`saveState` 描述該組，`slots` 描述全部五組的草稿及有效性狀態。`saved` 僅含持久確認內容，`pendingSlot`／`pendingKind` 描述目前提交。

編輯及保存 RPC 明確帶入組別和草稿版本，啟用 RPC 帶入組別和已保存版本。過期或其他組的命令不能套用到當前組。整份保存文件仍按 profile 序列寫入；寫入中可切換及編輯其他組，但不接受另一筆平行保存。延遲回覆捕捉原組別與版本，只確認那次提交，不切換編輯組、不將其他草稿標成已保存。

失敗保留原出戰選擇、保存內容及所有草稿，訊息包含操作組別與儲存錯誤代碼。因逾時可能已提交，先透過「重試讀取」對帳再重試；對帳保留本次登入的五組草稿。重新登入則只還原五組已保存內容與出戰選擇。

## 驗證紀錄（2026-10-19）

Maker `map01` 根 UUID 與工作區一致；三張地圖均為 RectTile（1）。Refresh 後 build 為 78 筆 Info、零 Error／Warning；最終 runtime 無 Error／Warning。UIBuilder lint clean。

所有新探針透過已連接 ButtonClickEvent、正式地圖輸入與公開 RPC 操作，觀察 `FormationLobby.Snapshot`；不改寫服務 session。故障僅使用既有 ServerOnly、Maker 限定的 `ConfigureMakerFaults` 儲存邊界，測試後重設 `(0,0,0)`。

| 探針 | 程序與證據 |
|---|---|
| `formation_slots_runtime_probe.lua` | client；五組分別保存 1–5 個單位、三種正式兵種、小數站位、空第五組拒絕啟用、第一組保持出戰、草稿切換／跨圖保留、過期跨組命令拒絕；`[VRF][FormationSlots] PASS` |
| `formation_slots_delayed_runtime_probe.lua` | 上一探針後，server 設 `(0,0,2)`，client 執行；第二組保存中編輯第三組、延遲確認不改組、獨立啟用第二組、再保存第三組；`[VRF][FormationSlotsDelay] PASS` |
| `formation_slots_failure_runtime_probe.lua` | server 設 `(0,1,2)`；client；第四組啟用失敗時切到第五組編輯，保留第二組出戰、錯誤代碼提示、對帳保留草稿、重試啟用第四組；`[VRF][FormationSlotsFailure] PASS` |
| `formation_slots_relogin_runtime_probe.lua` | 前三探針後 Stop → Play；client；五組兵種、數量及確認站位還原，第四組仍出戰，第五組未保存站位不還原；`[VRF][FormationSlotsRelogin] PASS` |
| `formation_slots_save_failure_runtime_probe.lua` | 編輯圖、各組已保存，server 設 `(0,1,2)`；client；第五組保存失敗時切到第一組，失敗標在第五組，對帳後第五組草稿仍可接續；`[VRF][FormationSlotsSaveFailure] PASS` |
| 既有 `formation_delayed_runtime_probe.lua` | 第一組編輯圖，server 設 `(0,0,2)`；保存中同組再編輯，舊回覆不能確認新草稿；`[VRF][FormationDelay] PASS` |
| 既有 `formation_validation_runtime_probe.lua` | 第一組編輯圖；未知 ID、非法座標、重疊、超量、稀疏陣列及過期版本均被拒絕；`[VRF][FormationValidation] PASS` |

本地編隊契約為 **5/5 通過**，完整 `node --test tests/*.test.cjs` 為 **25/28 通過**。三項既有失敗與 #28 相同：相機契約要求已移除的 `CameraZoomPercent`，部署斷言要求舊間距 0.6（目前 0.3），Tank HP 斷言要求 500（目前 300）。這些測試及對應戰鬥設定／資料均未在本票修改。

Standards 與 Spec 兩路審查均無發現。Maker Stop／Play 是本機新登入工作階段驗證；發布環境真實重新登入、多客戶端及跨 instance 的服務逾時仍屬既有發布驗證邊界。
