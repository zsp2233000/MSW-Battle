# 奪城是一次文件寫入；失守城鎮用靜態房事件加動作時複查來清空

兵力降到零的那場戰果，與「該城換旗並回滿 100」是同一次寫入。`FactionWarAttack.Settle` 在 `Attempt` 裡算出 `remaining = 兵力 - 扣除量`，`<= 0` 時把該城寫成 `{ owner = 勝方城鎮目前的歸屬, strength = FullStrength(100) }`，其餘城鎮原樣複製，整份城鎮文件只 `WriteTowns` 一次。儲存的兵力仍不可能是 0：`FactionWar.DecodeTowns` 依舊拒收 `< 1` 或 `> 100`，也依舊把兩座主城強制讀成 `RED/100`、`BLUE/100`，所以主城即使被誤寫也不會讀回易主。主城的「永不扣兵、永不易主」仍由 `Deduction` 回傳 0、`Settle` 以 `NO_CHANGE` 結束而不碰儲存來保證。

## 戰果要能被重複取得

`towns.settled` 由「比賽鍵字串清單」改為「每場一筆紀錄」：`{ k = 比賽鍵, w = 勝方城, l = 敗方城, s = 結算後敗方城兵力, o = 換旗後的歸屬（沒換旗為空字串） }`。`FactionWarAttack:EntryKey` 同時讀得懂舊的字串項目，舊文件不必遷移。重複送來的同一場戰果回 `DUPLICATE`，並帶出當初的 `s`、`o`，所以「寫入成功但回應遺失」之後的重試仍能知道這一場奪了城，後面的撤離與落點才不會漏掉。清單上限仍是 20 筆（`SettledHistory`），單筆約 110 位元組，整份文件預估約 2.4 KB，要低於一個儲存額度（4000 位元組）；`tests/faction_war_conquest_runtime_probe.lua` 寫滿 20 筆後會量並要求小於 4000。

`Settle` 回報 `complete(status, detail, outcome)`：`detail` 仍是敗方城的新兵力（奪城時為 100），新增的 `outcome` 是 `{ status, winner, loser, amount, strength, flipped, owner }`。`SAVED` 與 `DUPLICATE` 的結果也記在 `FactionWarAttack._T.outcomes[比賽鍵]`，供這個房間裡之後按「返回」的玩家查詢。這個形狀是為 #108（同時爭城）預留的：它要在同一份紀錄上加「誰讓城換旗」的判斷與出戰時的換旗世代，不必再改回傳值。

## 落點：依戰果與即時歸屬，在玩家按「返回」時決定

這取代 ADR 0010 的「有 `origin` 的票券回到出發城」。`MatchFlow:MoveHome` 對戰爭票券改問 `FactionWarAttack:LandingFor(userId, ticket)`，它回傳：奪下城鎮的那位玩家（`outcome.flipped` 且 `outcome.winner == 票券的 origin`）要去被奪下的城；其他人要回出發城；任何一個落點只要玩家的陣營此刻已不擁有，就改去自己陣營的主城。「此刻擁有」讀即時的城鎮文件，判斷由純規則 `FactionWar:Landing(faction, preferred, towns)` 做，不分真人戰或守衛戰。返回仍是玩家按結果畫面上的按鈕才發生，所以結果卡片與經驗值畫面不被打斷；「自動進城」指的是不必再走傳送門。按得比結算寫入還快時，`LandingFor` 先等 `_T.settling` 清掉（最多 5 秒）。讀不到陣營或城鎮文件時回到出發城，與先前行為相同，後面的複查會補正。

## 失守城鎮的清空：事件推送加上動作時複查，不輪詢

結算發生在比賽實例房，城鎮裡的人卻在靜態房，`_UserService` 與 `MatchFlow` 的紀錄都是房內的。有三個候選：

- 輪詢：每個靜態房定時讀城鎮文件比對歸屬。與 `MatchFlow` 一貫的「不做重複的儲存輪詢」（`AdvancePending`、`RoomBattleAdmission` 的註解）衝突，而且要為每個房間付固定額度。
- 只在玩家動作時檢查：現有的傳送門、NPC、排隊本來就即時讀歸屬，但待命的人不動就永遠不會被移走。
- 事件：換旗確認後，結算端用 `_RoomService:RequestSendEventToRoomAsync(TownFellEvent, StaticRoomKey)` 通知靜態房（`GMOnlinePlayers` 已用同一手法），靜態房的 `FactionWar:HandleTownFellEvent` 掃描 `CurrentMapName` 為該城的玩家。

決定：事件為主、動作時複查為輔。掃描時讀一次即時文件，對每位玩家讀其陣營，`Landing(faction, 所在城, towns)` 不等於所在城的人（也就是陣營已不擁有這座城）要走：先 `MatchFlow:Vacate(userId)`（沒有票券直接放行；`FormationHandoff:CanCancel` 允許的等待中票券走既有的 `CancelForUser` 取消；已配對的票券不取消）確認釋放，再 `FactionWar:Move` 到主城並顯示「某城已失守，已撤回主城。」。取消失敗或票券已進入 `COMMITTING` 之後就不移動：那場戰鬥照打，落點由上面的規則在返回時決定。同一套 `Enforce` 也掛在 `RequestTownStatus`（進入城鎮與排隊回到 IDLE 時）、傳送門被拒絕、以及 NPC 的 `NOT_OWNED`，所以漏掉通知、跨實例、或配對結束後落在一座已失守的城的玩家，會在下一個城鎮動作被送走。

因為歸屬只看戰果寫入後的即時文件，掃描對重複通知是冪等的；`DUPLICATE` 回來時 `Finish` 會再通知一次，補救第一次通知的遺失。

## 已知缺口

- `RequestSendEventToRoomAsync` 只到同一個 world instance 的靜態房。發布環境有多個 world instance 時，別的實例裡待命不動的玩家要等下一個城鎮動作（進城、過門、找 NPC）才會被移走；排隊中的人由票券自己的流程處理。要不要補一個很輕的歸屬比對計時器，留給 #110 的雙帳號驗收決定。
- 城鎮 HUD 的兵力仍只在進入城鎮與排隊回到 IDLE 時重讀，不是即時推送。
- 重複的城鎮事件與動作時複查可能同時對一位玩家觸發；`FactionWar._T.evicting` 讓同一位玩家一次只跑一個檢查。

## 留給 #108

這份設計沒有做：兩場以上同時結算同一座城時「只有造成換旗的那一場完成奪城」（讀取—修改—寫入仍無比較並寫入，ADR 0010 的缺口不變）；配對成立後出戰城曾換旗就免扣兵的出戰世代；「勝方城鎮在比賽期間易主」時新歸屬取勝方城鎮目前的歸屬，這在雙方城鎮都換過旗的極端情形會得到錯誤陣營，#108 的世代判斷需要在 `Attempt` 先排除。落點的「留在自己陣營的出發城，否則去主城」已由 `Landing` 即時判斷涵蓋，#108 只需補上讀回結算結果時的版本判斷。
