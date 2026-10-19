# #30 跨 WorldInstance 集合測試

本次交付受控測試程式與操作說明。**尚未取得公開發布環境的跨 WorldInstance 成功證據，#30 不應關閉。** 測試世界、leaderboard 與兩個真實帳號尚未備妥。Maker 的模擬玩家不等於另一個 WorldInstance。

## 程式入口與設定

`RootDesk/MyDesk/Matchmaking/MatchProbe.mlua` 是各 Room 的協調 Logic；`MatchProbeInput` 提供 PC 快捷鍵與地圖切換時的一次狀態更新。所有 RPC 都從 `senderUserId` 取得玩家身分，不接受對手、能力值、房間 key 或目的 instance 參數。狀態透過既有 toast 與 `[VRF][MatchProbe]` 日誌顯示。

僅在專用公開測試世界設定下列伺服器屬性，之後 Refresh、儲存並發布：

| 屬性 | 設定 |
| --- | --- |
| `Enabled` | 預設 `false`；測試世界才改為 `true` |
| `TestProfileA` / `TestProfileB` | 兩個不同的真實 ProfileCode，必須都是受控測試帳號 |
| `LeaderboardId` | 此測試世界內的測試 leaderboard ID，事先由管理者建立並設定配對所需初始分數 |
| `QueueName` | 預設 `issue30-controlled-v1`，兩名玩家使用相同值 |
| `SaveDelaySeconds` | 預設 0；可用 5、30、120 秒測試成功後延後傳送，程式上限 120 秒 |
| `TransferLifetimeSeconds` | 預設 900，為應用程式的入場期限，**不是原生排隊／結果有效期限** |

此探針沒有建立或刪除 leaderboard、更新勝負分數，也不會替帳號捏造有效出戰編隊。兩名玩家須先透過現有整備流程儲存有效編隊並設為出戰。準備一份與出戰內容不同的未保存編隊草稿，以便驗證往返保留；不要將草稿保存後再聲稱驗證未保存內容。

| 快捷鍵 | 公開命令 | 行為 |
| --- | --- | --- |
| F6 | `RequestQueue()` | 驗證已讀取、有效的出戰編隊且沒有未完成保存，固定本局編隊並呼叫原生配對 |
| F7 | `RequestCancel()` | 封存前撤銷本地成功回覆、呼叫原生取消、保存取消墓碑 |
| F8 | `RequestStatus()` | 顯示狀態、等候秒數、WorldInstanceId、RoomKey；重試可恢復的入場與還原步驟 |
| F9 | `RequestReturn()` | 從對局房回到**目前目的 WorldInstance 的整備區**；尚未入房時中止交接並還原 |

F9 不保證返回原始來源 WorldInstance。返回同一目的 instance 的整備區是本次最小返回路徑；來源 instance 可能已滿或退休，若後續需要回原來源，須另加保留與失敗策略。

## 交接與隔離

1. `RequestMatchingAndWait` 的 extras 僅含伺服器產生的 attempt GUID 與來源 WorldInstanceId。
2. `GetMatchUserInfosAndWait` 的 Home/Away 結果決定參與者及兩個 attempt 組成的唯一 match key。兩個來源 ID 是否相異會記錄為 `differentSources`。
3. 成功回覆後先等待既有保存結束。`SealTransfer` 將當下五組草稿、確認保存內容、編輯組及原始保存 bytes 封存，同時鎖定後續編輯／保存／切換出戰，避免傳送前的最後修改遺失。本局編隊始終使用 F6 時固定的內容。保存失敗狀態和草稿一起保留，不會被假裝成保存成功。
4. 使用每個 ProfileCode 的獨立 UserDataStorage key `Issue30TransferV1` 攜帶交接；沒有使用或宣稱 `WarpMatchUser` 能接受 warpData。採用既有 `FormationStorage` guard／compare 寫入。原生 storage 容量和這個探針的限制不同：探針拒絕超過 16,000 UTF-8 bytes 的 capsule；日誌僅記錄 bytes 數。原生 Matchmaking extras 容量仍待發布環境量測。
5. **雙方 capsule 都確認為可交接後**，Home 端才呼叫一次 `WarpMatchUser`。若 Home 的第一次 F8 早於對方封存，雙方再按 F8。沒有計時器反覆讀 storage。
6. 確認雙方已集合到同一 WorldInstance 後，才建立唯一 `matchprobe` InstanceRoom 並各自移入。第二人可能需要再按 F8；重複狀態更新沿用同一房間，建房失敗可重試。WorldInstance 與 InstanceRoom 的識別會分別輸出，不能只看地圖名稱判定集合。
7. 房內不啟動戰鬥。F8 解碼固定編隊與草稿，輸出 `ARRIVED ... users=2 ... distinctDraft=true`；編隊草稿完整還原到編輯服務的時點是返回整備區。F9 保存 RETURNING 後透過 `MoveUserToStaticRoom` 返回；F8 完成還原及墓碑清理。舊讀取 callback 透過 loadEpoch 作廢。

成功與取消的應用程式邊界為 `SAVING → COMMITTING`。在該邊界以前 F7 可阻止舊成功 callback 傳送；封存開始後 F7 回覆 `COMMITTED_USE_RETURN_OR_STATUS`。有未完成封存寫入時 F9 會拒絕並等待寫入結束。封存失敗先 F8 重新讀取權威狀態，再 F9 中止。原生 warp 已送出後，無法用應用程式取消保證撤銷原生的非同步傳送；此競態必須發布實驗確認，不能宣稱已解決。

`warpIssued` 在送出原生 warp 前持久化，避免重複傳送；模糊失敗不自動重送。若送出後玩家沒有移動，先保留原生 code、雙方來源及狀態，使用 F8/F9 恢復。若原生結果已過期、storage 回覆模糊或服務仍在傳送，停止該次實驗，由管理者確認雙方狀態後再清理測試 key，不能盲目重排。探針不宣稱提供斷線重連原對局保證。

取消或返回完成後，持久票據僅保留 attempt／終止狀態等墓碑，移除編隊與草稿 payload，拒絕舊通知。原生取消 code 與墓碑寫入成功分別記錄。這條路徑未建立 teleport reservation 或動態訂閱；事件使用引擎管理的 handler。InstanceRoom 在玩家離開後由引擎回收，RoomEnd 清除失效本地 handle；回收時機須觀察 context／room 清單，不能以返回成功替代清理證據。

## 發布環境實驗與證據

依下表逐項記錄，未執行者保留「待驗證」，不要填入推測結果。測試期間使用 Creator 可取得的發布日誌；若日誌不可取得，錄下雙方 F8 狀態。紀錄帳號 A/B 別名，遮蔽 ProfileCode、UserId、草稿與 capsule 原文。

| 實驗 | 必要紀錄 | 目前結果 |
| --- | --- | --- |
| 不同來源的真實配對 | A/B 原始 WorldInstanceId 不同，原生 request/callback/warp code，兩次 ARRIVED 的同一 match key、目的 instance、room key，房內 users=2 | 待驗證 |
| 固定編隊與不同未保存草稿往返 | 出發前保存／草稿版本，ARRIVED distinctDraft=true，返回後逐單位／五組版本比對，編輯草稿仍為未保存 | 待驗證 |
| 交接大小 | capsule bytes；原生 extras 允許大小另外測試，不以 16KB 應用上限代替 | 待驗證 |
| 讀取時機與生命週期 | 封存確認、warp、首次到達、房內解碼、返回還原、終止墓碑移除 payload 的順序 | 待驗證 |
| 排隊／結果期限 | 逐次延長等待並記錄原生 MatchingExpired／RequestNotFound 等實際 code 與秒數；過期後需 F7 清理再排 | 待驗證 |
| 成功後延後保存／傳送 | SaveDelaySeconds=5/30/120，各次 request、callback、seal、warp code 與時間 | 待驗證 |
| 取消競態 | 配對前、成功回覆前、SAVING 中、COMMITTING 後各自 F7；確認取消成功後舊回覆不傳送 | 待驗證 |
| 重複操作／失敗 | 連按 F6/F8/F9，雙方晚到，容量不足、房間建立失敗、原生 warp 不成功、storage 寫入失敗 | 待驗證 |
| 返回與清理 | 雙方返回、編隊還原、cleanup=true、InstanceRoom 被回收、再配對使用新 match key | 待驗證 |

若 `WarpMatchUser` 的結果期限或集合行為不合需求，下一個具體候選是：保留原生 Home/Away 配對權威，以 Home extras 的來源 instance 為目的，雙方 durable capsule barrier 完成後，各自呼叫 `TeleportService.WarpUserToWorldInstanceAndWait(userId, homeSource, ticketReference)`，目的端再次核對原生 pair／attempt，最後建立同一 InstanceRoom。還需實驗滿員／退休 instance、結果過期與 warp record 的來源驗證；這是可試驗的替代方案，**尚無成功證據，也尚未實作**。

## Maker 實際檢查紀錄

2026-10-19，Maker `map01` root ID 與工作區一致；`matchprobe` 經 MapBuilder 複製既有 RectTile 地形，`TileMapMode=1`，沿用 DefaultPlayer 對應的 Kinematicbody。經 Maker 開啟並儲存後，地圖 entry `Usage=1` 且 `MapComponent.IsInstanceMap=true`。只改 component flag 時，原生建房曾回覆 LEA-3002；儲存後建房成功。不要將修正前的失敗當成原生跨 instance 能力結論。

已取得以下正向日誌：

```text
[VRF][MatchProbe] ready enabled=false room=__main__
[VRF][MatchProbeCheck] restore=true fixed=true drafts=true
[VRF][MatchProbeFinal] distinctDraft=true sealed=true restored=true fiveDrafts=true fixed=true
[VRF][MatchProbeLockFinal2] distinctEditAttempted=true
[VRF][MatchProbeLockFinal2] editingRejected=true restored=true
[VRF][MatchProbe] DISABLED_OR_NOT_PUBLISHED
[VRF][MatchProbeRoom] created=true
[VRF][MatchProbeRoom] moved=true
[VRF][MatchProbeRoom] clientMap=matchprobe lobbyHidden=true
[VRF][MatchProbeRoom] sameRoomUsers=1 ...
[VRF][MatchProbeRoom] returned=true
[VRF][MatchProbeRoomFinal] sameRoomUsers=2 ...
[VRF][MatchProbeRoomFinal] returned=2
[VRF][MatchProbeRoomFinal] returnedMap=formationlobby lobbyVisible=true
```

這些檢查使用原生 InstanceRoom API 與編隊服務公開交接方法，沒有偽造配對成功 callback。最後使用 Maker `add_virtual_player`（不傳自訂 user_id，由 Maker 分配）新增第二名虛擬玩家，原生 MoveUsers 將兩人送入同一 InstanceRoom；房內實際觀察 `sameRoomUsers=2`，MoveUsersToStaticRoom 回覆 `returned=2`，客戶端回到 formationlobby。返回後 context 清單剩 `server_main`、`client`，確認本次房間已回收。這仍是同一 WorldInstance 的兩名玩家，不能寫成真實跨 WorldInstance 驗收通過。

Maker 編譯日誌沒有 Error／Warning，執行上述最終檢查也未出現 Error／Warning。既有編隊契約測試 5/5 通過；完整 Node suite 為 25/28。將本次開始的提交 `4c5671ff2747031d4c98d6f37d125e5ba1efa7ac` 以 git archive 解到獨立暫存目錄重新執行，也得到相同 25/28；三項既存失敗分別為相機 CameraZoomPercent 欄位斷言、DeploymentMinDistance=0.6 斷言，以及怪物 fixture 預期 HP=500、實際300。沒有為了讓測試變綠而變更既有戰鬥參數。

Standards 與 Spec 兩軸審查提出的封存期間編輯、取消／提交競態、舊 Load 覆寫還原、取消後重新鎖定及失敗入房後卡住等問題均已修正並複查；最終無剩餘 P1/P2 審查發現。發布實驗仍是未完成驗收項。

## 供正式流程接續的介面

`FormationService.ExportTransfer(userId)` 驗證並固定有效出戰編隊；`SealTransfer(userId)` 在既有保存完成後原子鎖定並擷取最新草稿；`CaptureTransfer(userId)` 可攜帶保存失敗後保留的草稿；`ImportTransfer(userId, transfer)` 還原確認保存內容及五組草稿，作廢舊讀取 callback。這些方法皆為 ServerOnly。正式流程應自行持有有效的配對／交接權威；不能將 ImportTransfer 包成任意客戶端 payload RPC。
