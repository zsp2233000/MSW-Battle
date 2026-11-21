# 國戰進攻排隊沿用同一條配對流程，只把「出發城／目標城」放進票券

城鎮 NPC 的「進攻」不另開配對系統。`MatchFlow.QueueForWar(userId, origin, target)` 與大廳的 `QueueForUser` 共用 `QueueTicket`，差別只在票券多了兩個字串 `origin`（排隊時所在的城）與 `target`（要進攻的敵城）。這兩個欄位寫進 `FormationHandoff` 的票券中繼資料、`MatchFlow` 發布給客戶端的快照，以及排隊請求，因此重新登入、重試與取消沿用既有的票券規則，不需要第二份狀態。

誰和誰配對由 adapter 決定。`MatchQueueLocal.Poll` 對戰爭票券只配對「各自站在對方目標城」的兩張票（`Pairs`）；兩個同城玩家、目標不對稱的玩家、以及大廳票券與戰爭票券都不會互相配對。流程本身只在 `MatchFlow.Belongs` 核對配對結果與票券記錄的城鎮相符，性質和它核對嘗試編號一樣，是對 adapter 回覆的防呆，不含環境分支（ADR 0006 的限制仍成立），所以過期通知不能把票券接到別的城的對手。

配對成立後，兩城寫在 `match.homeOrigin / awayOrigin`，隨交接資料進入戰場房間。`MatchedBattle` 在戰果只發布一次時呼叫 `FactionWarAttack:Settle(matchKey, homeTown, awayTown, homeResult, kind)`（#108 起多兩個選填參數 `complete` 與配對時蓋的 `snapshot`）；以全域儲存裡的 `settled` 清單去重，所以重複接收戰果不會重複扣兵力。真人戰勝利扣目標城 20 兵力（守衛戰勝利扣 10，見 ADR 0011，`Settle` 因此多一個 `kind` 參數），對主城、平手與同陣營城鎮不扣。（#107 起兵力降到零就換旗並回滿 100，見 ADR 0012；本段原本寫的「兵力不會降到零」已不成立。）

戰後返回改走 `MatchTransfer:MoveToTown`：有 `origin` 的票券回到出發城，其餘仍回大廳。（#107 起戰爭票券的落點改依戰果與即時歸屬：奪城者進新城、出發城已易主者回己方主城，見 ADR 0012；`MoveToTown` 這條 adapter 邊界不變。）離城鎖定也用同一份票券：`FactionWarAttack:IsEngaged` 讀 `MatchFlow:StateForUser` 與 `FormationHandoff:IsLockedForUser`，傳送門與 NPC 都以它判斷。

## 已知缺口（發布環境）

原生配對只會把同一個 `queueName` 的玩家配在一起，無法表達「A 城對 B 城」這種有方向的互選。`MatchQueueNative` 因此用「無序城鎮對」命名佇列（`<佇列名>:war:<城>:<城>`），並在 `Lookup` 擋掉同一出發城的兩人與目標不對稱的配對。代價是：同一城的兩名玩家若搶先被原生服務配在一起，會被判為無效配對（`QUEUE_RESULT_INVALID`）而非繼續等待對岸的玩家。本機 adapter 不受影響，也已用探針驗證互選。這一段只做了純規則檢查，沒有在發布環境或兩個真實帳號下驗證；需要在整合驗收（#110）時用兩個真實帳號確認，必要時改為由 adapter 先自行分隊再向原生服務註冊。

兵力結算原本是對全域儲存的讀取—修改—寫入，只用 `settled` 清單去重，沒有比較並寫入，兩場同時結算同一座城時可能互相覆蓋。（#108 已補上：結算改以「讀到的位元組」做比較並寫入，輸家重新讀取後依新文件決定，並以配對時的換旗次數讓過期戰果免扣兵，見 ADR 0013。）
