# 配對流程只有一份，本機與原生配對是同一條 seam 後的兩個 adapter

`MatchFlow` 擁有「排隊、取消、等對手、交接、入場、返回」整條流程；怎麼找到對手、怎麼取消、配對結果長什麼樣，由 `MatchQueueLocal`（Maker 的行程內 FIFO）與 `MatchQueueNative`（原生 `MatchmakingService`）各自負責，流程本身不再判斷 `Environment:IsMakerPlay()`。房間移動是另一條獨立的 seam（`MatchTransfer`），因為它在 Maker 與發布環境用的是同一個原生服務，只有測試需要讓它失敗。

故障注入不放在流程裡。`MatchFaults` 是包住當下 adapter 的測試用 adapter：預設完全轉送，只在探針用 `ConfigureCancel`／`ConfigureTransfer`／`ConfigureWithdraw` 啟動後才失敗，且只在 Maker 可啟動。不要為了測試某條失敗路徑，在 `MatchFlow` 或正式 adapter 裡加旗標。

票券記錄寫入它的 adapter（`ticket.data.adapter`，只會是 `local` 或 `native`）。重新登入或重啟 Maker 後，流程把「這張儲存的票券還有沒有人負責」交給 adapter 的 `Reclaim` 判斷（`HELD`、`RENEW`、`FAIL`、`CANCEL`、`RETURN` 或 `nil` 繼續），不自己比對環境與字串。

新增第三種配對來源，只要實作 `MatchQueueLocal` 已有的十一個方法，並讓 `tests/match_queue_contract.test.cjs` 的 port 清單涵蓋它；不改 `MatchFlow`。

這個決定不改變 ADR 0003 的交接內容，也沒有驗證發布環境：原生 adapter 的行為搬動後只以純規則探針與 Maker 內的流程探針驗證，兩個真實帳號與跨 WorldInstance 的配對仍須另外驗收。
