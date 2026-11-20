# 守衛戰是寫進票券的配對，不是配對佇列的第三種對手

排隊滿 10 秒仍無真人時，玩家迎戰目標城的守衛。守衛沒有票券、沒有帳號、也不在任何佇列裡，所以不能讓 `MatchQueueLocal` / `MatchQueueNative` 配出這場戰鬥，也不新增 adapter 方法。

`MatchFlow` 在佇列被接受時為戰爭票券啟動一個 10 秒計時（`StartGuardClock`，每張票券只一次，重新送出佇列請求保留原時鐘）。計時到了，`GuardFire` 只處理仍在等待的票券：先設 `ticket.guarding`，再要求 adapter 確認這張票券已離開真人池（`CancelMatching`），確認後才合成一個配對 `{ key = "guard-<guid>", home = 玩家, away = "guard:<城>", guard = true, ... }`，並走既有的 `Matched` → `Seal` → `Commit` → `Admit` 路徑。`guarding` 期間才到達的真人結果會被延後（沿用取消流程的 `matchPending`），adapter 不確認離池就放棄守衛戰，真人配對照常成立。這是「同一次排隊最多開一場」的保證，不用另外的鎖。

配對寫進票券中繼資料（`Commit` 已經複製 `match` 的所有欄位），所以 `MatchFlow.Pairing` 先看票券裡的 `guard` 配對，沒有才問 adapter。復原、入場與戰場房間因此都不需要 adapter 知道守衛存在；重新登入或換房間後，TRANSFER 狀態的守衛票券會依同一份配對進同一個房間。守衛的名單在 `FactionWarGuard.Rosters`，`MatchedBattle` 以它當客場方，`BattleSession` 只允許 `guard:` 開頭的客場參與者不在房間內，也不替它結算怪物經驗。

結算沿用 `FactionWarAttack.Settle`，多一個 `kind`：守衛勝扣可爭奪城 10 兵力（真人勝 20），守衛敗、平手、對主城都不扣，兩城也不因守衛戰而互換兵力。

復原時 `MatchFlow.Recover` 對守衛票券不呼叫 adapter 的 `Reclaim`：ADR 0006 把「儲存的票券是否仍有效」交給 adapter 判斷，但 adapter 從沒持有過守衛配對，沒有意見可給，所以守衛票券直接依票券裡的配對與到期時間處理。這是對 ADR 0006 的一處明確例外。

認領流程的失敗路徑：adapter 無法確認撤出時，票券繼續等待並稍後重試；認領後真人結果已到達、或 adapter 仍持有同一次嘗試的配對，真人配對優先；認領失敗而票券仍在 QUEUED 時重新排程，不會卡住。

## 已知缺口

認領的瞬間（`CancelMatching` 等待 adapter 回覆時）玩家按取消會被丟棄，因為該票券暫時標為忙碌；視窗只有一次 adapter 往返，本機 adapter 是同步的。

`MatchQueueNative.Cancel` 把 `AlreadyMatched` 也視為已確認。發布環境中，若真人配對在計時到的同一瞬間成立，守衛仍可能認領這張票券，對岸玩家的票券就留在配對成功但無人入場的狀態，直到入場逾時。本機 adapter 的確認是同步的，這個視窗不存在，也已用探針驗證互選配對時沒有守衛介入。這需要在 #110 用兩個真實帳號確認；若發生，應改為 adapter 回報「已配到」而非「已確認」。

守衛兵力不為零，奪城、主城反攻後的歸屬與落點屬 #107；排隊途中離線與重連後的守衛票券細節屬 #109。
