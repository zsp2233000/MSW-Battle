# 奪城是一次文件寫入；失守城鎮用靜態房事件加動作時複查來清空

兵力降到零的那場戰果，與「該城換旗並回滿 100」是同一次寫入。`FactionWarAttack.Settle` 在 `Attempt` 裡算出 `remaining = 兵力 - 扣除量`，`<= 0` 時把該城寫成 `{ owner = 勝方城鎮目前的歸屬, strength = FullStrength(100) }`，其餘城鎮原樣複製，整份城鎮文件只寫一次（#107 當時是 `WriteTowns`；#108 起改為比較並寫入的 `SwapTowns`，見 ADR 0013）。儲存的兵力仍不可能是 0：`FactionWar.DecodeTowns` 依舊拒收 `< 1` 或 `> 100`，也依舊把兩座主城強制讀成 `RED/100`、`BLUE/100`，所以主城即使被誤寫也不會讀回易主。主城的「永不扣兵、永不易主」仍由 `Deduction` 回傳 0、`Settle` 以 `NO_CHANGE` 結束而不碰儲存來保證。

## 戰果要能被重複取得

`towns.settled` 由「比賽鍵字串清單」改為「每場一筆紀錄」：`{ k = 比賽鍵, w = 勝方城, l = 敗方城, s = 結算後敗方城兵力, o = 換旗後的歸屬（沒換旗為空字串） }`。`FactionWarAttack:EntryKey` 同時讀得懂舊的字串項目，舊文件不必遷移。重複送來的同一場戰果回 `DUPLICATE`，並帶出當初的 `s`、`o`，所以「寫入成功但回應遺失」之後的重試仍能知道這一場奪了城，後面的撤離與落點才不會漏掉。清單上限仍是 20 筆（`SettledHistory`），單筆約 110 位元組，整份文件預估約 2.4 KB，要低於一個儲存額度（4000 位元組）；`tests/faction_war_conquest_runtime_probe.lua` 寫滿 20 筆後會量並要求小於 4000。

`Settle` 回報 `complete(status, detail, outcome)`：`detail` 仍是敗方城的新兵力（奪城時為 100），新增的 `outcome` 是 `{ status, winner, loser, amount, strength, flipped, owner }`。`SAVED` 與 `DUPLICATE` 的結果也記在 `FactionWarAttack._T.outcomes[比賽鍵]`，供這個房間裡之後按「返回」的玩家查詢。#109 起，房間沒有記住這場戰果時（玩家斷線重連、比賽房已被回收），`FactionWarAttack:OutcomeFrom` 從這份 `towns.settled` 紀錄重建同樣的結果，`Attempt` 的 `DUPLICATE` 回應與 `LandingFor` 共用它（見 ADR 0014 決定六）。這個形狀是為 #108（同時爭城）預留的。#108 的實際做法（ADR 0013）：回傳值不變，只多了 `EXEMPT` 一種 `status`（`flipped = false`）；「出戰時的換旗次數」放在城鎮文件每座城的 `e` 與配對的 `homeEpoch` / `awayEpoch`，不放進這份逐場紀錄。

## 落點：依戰果與即時歸屬，在玩家按「返回」時決定

這取代 ADR 0010 的「有 `origin` 的票券回到出發城」。`MatchFlow:MoveHome` 對戰爭票券改問 `FactionWarAttack:LandingFor(userId, ticket)`，它回傳：奪下城鎮的那位玩家（`outcome.flipped` 且 `outcome.winner == 票券的 origin`）要去被奪下的城；其他人要回出發城；任何一個落點只要玩家的陣營此刻已不擁有，就改去自己陣營的主城。「此刻擁有」讀即時的城鎮文件，判斷由純規則 `FactionWar:Landing(faction, preferred, towns)` 做，不分真人戰或守衛戰。返回仍是玩家按結果畫面上的按鈕才發生，所以結果卡片與經驗值畫面不被打斷；「自動進城」指的是不必再走傳送門。按得比結算寫入還快時，`LandingFor` 先等 `_T.settling` 清掉（最多 5 秒）。讀不到陣營或城鎮文件時回到出發城，與先前行為相同，後面的複查會補正。

## 失守城鎮的清空：事件推送加上動作時複查，不輪詢

結算發生在比賽實例房，城鎮裡的人卻在靜態房，`_UserService` 與 `MatchFlow` 的紀錄都是房內的。有三個候選：

- 輪詢：每個靜態房定時讀城鎮文件比對歸屬。與 `MatchFlow` 一貫的「不做重複的儲存輪詢」（`AdvancePending`、`RoomBattleAdmission` 的註解）衝突，而且要為每個房間付固定額度。
- 只在玩家動作時檢查：現有的傳送門、NPC、排隊本來就即時讀歸屬，但待命的人不動就永遠不會被移走。
- 事件：換旗確認後，結算端用 `_RoomService:RequestSendEventToRoomAsync(TownFellEvent, StaticRoomKey)` 通知靜態房（`GMOnlinePlayers` 已用同一手法），靜態房的 `FactionWar:HandleTownFellEvent` 掃描 `CurrentMapName` 為該城的玩家。

決定：事件為主、動作時複查為輔。掃描時讀一次即時文件，對每位玩家讀其陣營，`Landing(faction, 所在城, towns)` 不等於所在城的人（也就是陣營已不擁有這座城）要走：先 `MatchFlow:Vacate(userId)` 確認釋放：沒有票券直接放行；仍在等對手的票券（`QUEUED`、`RENEWING`、`QUEUE_ERROR`，以及已取消只待關閉的 `CANCELLED`，由 `IsWaiting` 判斷）走既有的 `CancelForUser` 取消；已配對的票券（`SAVING` 起，也就是配對成立之後）不取消，與規格「配對成立後直到戰果結算才能主動換城」一致。這比玩家自己的取消鈕更嚴：`FormationHandoff:CanCancel` 仍讓 `SAVING` 通過（ADR 0011 已接受的缺口，玩家鈕的行為不變），所以失城清掃不用它判斷。票券處在暫時狀態（預約尚未填入 `data`、有取消或守衛認領正在進行、取消尚未被 adapter 確認）時，`Vacate` 最多再試 `VacateAttempts`（6）次、每次隔 `VacateRetrySeconds`（0.5 秒），用盡才放棄；已配對的票券不重試，因為那不是暫時的。確認釋放後再 `FactionWar:Move` 到主城並顯示「某城已失守，已撤回主城。」。票券已配對、或重試用盡仍取消不掉，就不移動：那場戰鬥照打，落點由上面的規則在返回時決定。同一套 `Enforce` 也掛在 `RequestTownStatus`（進入城鎮與排隊回到 IDLE 時）、傳送門被拒絕、以及 NPC 的 `NOT_OWNED`，所以漏掉通知、跨實例、或配對結束後落在一座已失守的城的玩家，會在下一個城鎮動作被送走。

因為歸屬只看戰果寫入後的即時文件，掃描對重複通知是冪等的；`DUPLICATE` 回來時 `Finish` 會再通知一次，補救第一次通知的遺失。

#109 起，掃描跳過斷線中的玩家（`MatchFlow:IsOffline`）：引擎保留的離線實體若在失城當下被移走，之後城鎮在他回來前被奪回，就違反「曾失守但已奪回就回原城」。他們回來時由登入落點判斷（ADR 0014 決定二、三）。

### 同一位玩家的檢查：後到的請求不丟棄，移動前重讀城鎮表

`Enforce` 對一位玩家一次只跑一個檢查，但後到的請求不再被丟掉。HUD、NPC 或傳送門的檢查手上可能是換旗**之前**讀的城鎮表；失城事件的掃描若因為「已有檢查在跑」被丟棄，待命不動的玩家就留在失守的城裡（規格：在失城待命的玩家回己方主城）。現在檢查槽是一筆 `{ started, again }`：檢查進行中又有請求時只標記 `again`，目前的檢查結束後 `Recheck` **重新讀城鎮表**再 `Enforce` 一次（用剛讀到的表，不用那個請求帶來的表）。整段檢查包在 `pcall` 裡，槽一定會清掉；槽另有租期（`EnforceLeaseSeconds`，30 秒），回呼一直沒回來時下一個請求接手舊檢查，舊回呼之後即使回來也什麼都不做；玩家離開時槽也一併清除。

`Evict` 用傳進來的城鎮表只判斷「需不需要移動」。真要移動時，在 `Vacate`（會讓出執行權）之後**重新讀一次**城鎮表，依這份表決定落點，並再確認玩家仍在該城，才 `Move`。所以失而復得（換旗後又被奪回）的城不會把己方玩家送走（規格：曾失守但已奪回就回原城）；重讀不到就不移動，留給下一個城鎮動作的複查。

## 已知缺口

- `RequestSendEventToRoomAsync` 只到同一個 world instance 的靜態房。發布環境有多個 world instance 時，別的實例裡待命不動的玩家要等下一個城鎮動作（進城、過門、找 NPC）才會被移走；排隊中的人由票券自己的流程處理。要不要補一個很輕的歸屬比對計時器，留給 #110 的雙帳號驗收決定。
- 城鎮 HUD 的兵力仍只在進入城鎮與排隊回到 IDLE 時重讀，不是即時推送。
- 重複的城鎮事件與動作時複查可能同時對一位玩家觸發；上面的檢查槽讓同一位玩家一次只跑一個檢查，後到的請求排在後面再查一次。
- 一張已被保留（`SAVING` 起）的票券若封存失敗而退回等待狀態，玩家會留在失守的城裡，直到下一個城鎮動作的複查；`Vacate` 重試用盡、或 `Evict` 重讀城鎮表失敗時也是如此（都已記 `[VRF]`）。
- 斷線中的玩家不被失城清掃移動（#109）：他們留在原地，直到重連或重新登入時由登入落點判斷，不再要求下一個城鎮動作。

## 留給 #108（已由 ADR 0013 處理）

原本留下三件事，#108 的處理方式：兩場以上同時結算同一座城，只有造成換旗的那一場完成奪城（文件改為以讀到的位元組做比較並寫入，輸家重新讀取）；配對成立後出戰城曾換旗的場次是過期戰果、不扣兵（配對時蓋下兩城的換旗次數，結算時任一不同即為 `EXEMPT`）；勝方城鎮在比賽期間易主時新歸屬取勝方城鎮目前歸屬的錯誤，有蓋章的場次在計算新歸屬之前就已排除。落點的即時判斷（`Landing`）不變，每次返回都重新讀取即時城鎮表。
