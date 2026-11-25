# 登入落點由國戰判斷一次：最後所在的城鎮加上已存的戰果紀錄，不輪詢、不補算戰鬥

> 後續重構：下文記錄 #109 當時的實作。現在 `FactionWarLanding:Judge` 共用每位玩家一個落點檢查槽：`LOGIN` 等票券復原後才判斷；`CHECK` 接手失城清掃及城鎮動作的複查，稍後處理時丟棄舊城鎮表；`RETURN` 用 `MatchTransfer` 跨房返回；`RESTORE` 在靜態房內傳送並顯示提示，無法確認落點就不移動。兩條戰後路徑共用戰果與即時歸屬判斷；戰果可從 `FactionWarTownDocument:OutcomeFrom` 重建。存檔、票券順序與兩種移動方式不變。

規格 #103 的「斷線重返」要求：排隊中離線立即取消；對戰中離線，戰鬥繼續，重連回到同一場；戰後重連顯示該場結果，落點先套用戰果、再檢查該城登入時的歸屬；重新登入的人回到原城（仍屬己方或已奪回），否則回己方主城。#107、#108 完成後，缺的是三件事：沒有人知道一位剛登入的玩家上次站在哪座城、結算後的戰果只存在比賽房的記憶體裡、比賽房內的重連根本不恢復票券。這份 ADR 記下 #109 的做法，詞彙依 CONTEXT.md（登入落點、戰果、奪城、換旗次數、過期戰果、守衛）。

## 決定一：「最後所在的城鎮」是玩家自己的一個小 key

玩家 profile 多一個 key `CountryWarTownV1`，內容只有城鎮 id。`FactionWar:Remember(profile, town)` 經 `FormationStorage:Write`（比較並寫入）寫它，best effort：先讀，內容相同就不寫；寫入失敗只記 `[VRF][FactionWar] town not remembered`，代價是那一次登入沒有落點，不影響任何對戰。同一個 profile 一次只跑一個寫入，寫入進行中又來了較新的城鎮，等這一次結束後再寫一次最新的。

寫入點只有兩處，都落在靜態房：

- `FactionWar:Move`：傳送門、進城、失城撤離、登入落點都經過它，所以靜態房內每一次換城都記下新城。
- `FactionWar:PlaceAtLogin` 對「已經站在城鎮裡」的玩家：對戰結束從比賽房落回城鎮的那一次沒有經過 `Move`（那是換房間，`MatchTransfer:MoveToTown`）。比賽房在最後一位玩家離開後會被回收，非同步的儲存寫入可能來不及完成，所以不在房間端寫，改在人到了靜態房、`UserEnterEvent` 之後記。

持有非終態票券的人，落點由票券決定（`origin`、戰果），不看這個 key。

**不選**：在 `UserLeaveEvent` 寫入（離開處理有時限，當機時也沒有保證）；從票券推回（沒有票券的人推不出）；用 `StartPoint` 把新登入直接放進城鎮（`Global/` 由 Maker 管，也無法依陣營分流）。

## 決定二：登入只判斷一次，而且等票券先說完話

`MatchFlow` 在每次 `UserEnterEvent` 的 0.5 秒計時器裡先 `Recover`，再 `PlaceAtLogin`；靜態房的 `UserReconnectEvent` 也是 `Recover` 之後 `PlaceAtLogin`。`Recover` 順便記下有沒有票券管著這位玩家（`_T.arrival`，是或否：沒有或已結束就是否；沒有任何地方讀「哪一種」票券，所以不存種類）。`MatchFlow:PlaceAtLogin` 用 `FactionWarAttack:WaitWhile` 等 `Recover` 跑完（最多 `FactionWar.LoginReadySeconds` 秒，逾時記一行 `[VRF]` 並視為有票券管著），再把「有票券管著」（票券紀錄、`_T.arrival`，或交接仍鎖住該 profile：`_FormationHandoff:IsLockedForUser`）交給 `FactionWar:PlaceAtLogin(userId, cause, owned)`；`FactionWar` 自己也再看一次 `IsLockedForUser`，因為票券紀錄可能還沒存進來（`Recover` 逾時、開啟失敗）而交接已經鎖住了。

`FactionWar:PlaceAtLogin` 一位玩家同時只跑一個（`_T.placing`）：同一次登入可能同時送來 `UserEnterEvent` 與 `UserReconnectEvent`，第二個發現第一個在跑就記一行 log 離開。它先輪詢到實體與地圖都存在（事件可能比實體早到），斷線中的玩家不判斷，然後：

- 已經站在城鎮裡（保留的實體重連、從比賽房落回來）：記下這座城；沒有票券管著時走和其他城鎮動作同一個 `Enforce` 檢查，所以己方仍擁有（或已奪回）就留下，否則回主城。
- 剛登入、站在遊戲大廳、沒有票券管著：讀陣營、最後城鎮、城鎮表，目的地是 `Landing(陣營, 最後城鎮, 城鎮表)`：仍屬己方（失守後奪回也算）就回該城，否則回己方主城，`Move` 過去並顯示城鎮提示。
- 沒有陣營、沒有最後城鎮（新玩家、探針裡留在大廳的真人）：什麼都不做。資料讀不到：也什麼都不做並記 `[VRF]`，不猜城鎮。
- 從大廳對戰回來的人（大廳票券）一律留在大廳。Maker 裡 `UserEnterEvent.EnterType` 永遠是 `Normal`，分不出「房間移動」與「新登入」，所以用票券區分。

不加屬性開關：只有「有陣營又有最後城鎮」的玩家受影響。副作用是開發用的真人 profile 一旦進過城鎮，之後每次 Play 都會被放進該城；探針要求真人留在大廳時，該 profile 不要有最後城鎮（見 tests/README.md）。

## 決定三：失城清掃不動斷線中的玩家

`SweepFallen` 跳過 `MatchFlow:IsOffline(userId)` 為真的人，並記 `sweep skipped offline`。引擎會把斷線的實體保留一段時間；若在失城當下就把他移走，之後城鎮在他回來前被奪回，就違反「曾失守但已奪回就回原城」。他們在登入或重連時由 `PlaceAtLogin` 依當下的城鎮表判斷。

## 決定四：「戰鬥繼續」靠引擎保留房間，不補算；最後一位玩家真的離開，房間就沒了

Maker 實測兩種離線：

- **實體被保留**（`Depart` 加上合成的 `UserReconnectEvent`，等同引擎保留的斷線實體）：房間照常存在，戰鬥自己打到結果，`result published once` 與結算各執行一次，離線玩家的經驗也照算。
- **真的離開**（`KickUser`，實體消失）：只要房間裡還有別的玩家，房間照常存活（真人對真人，另一方還在）。但**最後一位玩家離開後，引擎約 1 秒內回收房間**（`BattleCleanup`、`MatchCleanup`，`InstanceRooms` 清空），戰鬥沒有結果、沒有結算、沒有經驗。守衛戰只有一位真人，所以他真的離開就是這個情形。這個局面等於該局中止、不扣兵力（ADR 0003），重新登入時 `Recover` 關閉過期票券，玩家回到出發的城鎮。

所以不寫「離線時無頭快轉到結果」：那要在離開處理裡跑很長的迴圈，離開處理有時限，而且房間在最後一人離開後 1 秒就被回收，來不及。規格「已開戰的真人與守衛戰都繼續」因此只在「實體被保留」或「房間裡還有別人」時成立；網路斷線時引擎保留實體多久、之後才送出 Leave，已發布世界沒有驗證過，這決定守衛戰的單人斷線能撐多久，留給 #110。

> 更正：本 ADR 初稿與探索筆記曾寫「只有一位真人的守衛戰，真人被踢出後比賽房仍存活 60 秒以上」。那次踢人是從 `server_main` 送出，只移除了靜態房對玩家的視圖，玩家其實還在比賽房裡。

## 決定五：重連回同一場

- **實體還在**（`UserReconnectEvent` 發生在比賽房）：以前這個處理器在比賽房直接 return，而 `Depart` 又丟掉了該玩家的票券紀錄，狀態會變成 `ENTRY_FAILED`、返回鈕回大廳。現在 `Recover`（`IN_ROOM` 且房間鍵相同就回報 `ARRIVED`）加 `PublishState`，並呼叫 `BattleSession:RearmExperienceReceipt`：怪物經驗收據每個實體只發一次，重連的 client 沒有舊收據，所以清掉那個實體的標記，下一次更新重發。這不是重新結算：不呼叫 `MonsterLevelStorage:Settle`，也沒有任何兵力或經驗被改。不重新入場：保留的實體本來就在房間裡。
- **實體已消失**（真的離開後重新登入）：票券仍是 `IN_ROOM`。房間裡還有別的玩家時房間還在（決定四），靜態房的 `Recover` 先 `Rejoin`：`TransferAdapter:FindRoom(matchKey)`（`_RoomService.InstanceRooms:TryGetValue`，且 `IsValid()`）找得到比賽房，就用和入場相同的 `MoveToMatch` 送回去，由房間自己的協調者接手（`UserEnterEvent` → `Recover` → `ARRIVED`）。靜態房讀不到別的房間的戰鬥階段，所以不判斷「戰鬥是否已到結果」：已到結果的房間也進去，玩家看到結果與經驗收據，按返回時依該房間自己的戰果落點。找不到房間就和以前一樣：關閉票券（`STALE_ROOM_RECOVERY`），再走決定六的落點。`Admit` 在移動期間標記 `_T.moving`，`Rejoin` 看到就不與它搶。只限同一個 world instance 的房間；別的 instance 的房間在這裡看不到，留給 #110。
- 房間查詢放在轉接 adapter（`MatchTransfer:FindRoom`），`MatchFaults:ConfigureRooms(true)` 可以在 Maker 裡讓所有房間「看起來已被回收」，不必等引擎回收就能走「房間已消失」那條路徑。

## 決定六：戰後重連，戰果從已存的紀錄重建

`FactionWarAttack:OutcomeFrom(towns, matchKey)` 是 `towns.settled` 的唯一讀取者（純函式，`{ k, w, l, s, o }` 還原成勝方城、敗方城、結算後兵力、新歸屬與是否奪城），`Attempt` 的重複回應與落點共用。落點由 `FactionWarAttack:ResolveLanding(userId, ticket)` 決定，回傳一個表 `{ destination, outcome, reliable }`；`LandingFor` 只是它的薄包裝，回傳 `destination`，給 `MoveHome` 這種當場就移動的返回。`ResolveLanding` 先用本房記住的戰果，沒有（重連、房間已被回收）就從剛讀到的城鎮表重建。找不到紀錄就是沒有奪城，和房內平手、守衛戰落敗、過期戰果的意義相同；紀錄被擠出 20 筆之後、或結算最後 `FAILED`，同樣讀成沒有奪城（已知缺口）。次序仍是規格的「先戰果、再歸屬」：奪城者的偏好城是被奪下的城，再交給 `Landing` 看登入當下是否仍屬己方。

`RestoreReturning` 完成（票券已關閉）後，靜態房呼叫 `MatchFlow:LandAfterRestore`：以同一個落點規則（`ResolveLanding`）再判一次，已經站在該城（正常返回）就不動；落點讀不到時（退回出發城鎮，`reliable` 為否）也不動人，只記一行 `[VRF]`，因為那座出發城鎮不是目的地，把一位本來就站對的奪城者搬回去違反上述規則；否則 `FactionWar:Move`（靜態房內的傳送，不是又一次換房間）並送出城鎮提示。「大廳或城鎮由誰決定」仍只有 `MoveHome`：`LandAfterRestore` 只處理城鎮票券，大廳票券不碰。

**顯示結果**：房間或實體還在時，玩家看到的是一般結果畫面；沒有房間時，城鎮提示由 `NoticeText` 用同一份 `ResolveLanding` 的 outcome（本房記住的戰果，或剛讀到的紀錄）組出一行，不再讀第二次城鎮表（「上一場戰果：奪下鼓山。」「…兵力降至 80。」；沒有紀錄只說「上一場對戰已結束。」）。紀錄只有勝方城與敗方城，沒有「這位玩家贏或輸」，所以提示不下勝負結論。不新增逐玩家的結果儲存：勝負與經驗收據目前沒有持久化的路徑（票券狀態機沒有 `IN_ROOM` 到 `IN_ROOM` 的轉換），為了這行字新增寫入不划算。

所有新路徑對兵力、奪城、經驗都是唯讀：重送的結果只能以同一個比賽鍵呼叫 `Settle`（得到 `DUPLICATE`），重連的程式碼從不呼叫 `MonsterLevelStorage:Settle`。

## 決定七：排隊中離線

`Depart` 的行為不變：取消等待中的票券、清掉守衛計時，`GuardFire` 對離線玩家另有一道防線，所以離線之後不會有守衛戰；重新登入後要重新選擇進攻目標，守衛的 10 秒從新的選擇重新計算（新票券重新啟動時鐘）。補上的三處：

- 離線當下取消失敗的戰爭票券（`ticket.departFailed`，原生佇列的註冊還在）：重連時再取消一次，不接續。否則它會變成沒有守衛後備、也沒被取消的純真人佇列。大廳票券維持原本的接續行為。
- `Depart` 最後一行 log 在預約尚未填入 `ticket.data` 時不再出錯。
- `[VRF][MatchDisconnect]` 多印 `reason=`（`UserLeaveReason`，或 `Disconnect`）。

## 已知缺口

- 已發布世界保留離線實體與比賽房的時間沒有驗證；單人的守衛戰在玩家真的離開時中止（決定四），能撐多久取決於這個時間；跨 world instance 回到原比賽房也做不到（#110）。
- 最後城鎮寫入失敗，該玩家下次登入留在大廳；城鎮表讀不到時也一樣。
- 房間被回收後，勝負與怪物經驗收據不再顯示，只剩一行城鎮提示。
- `settled` 只留 20 筆（ADR 0012）：更晚才重新登入、且之後又有 20 場以上結算的玩家，戰果讀成沒有奪城。
- 在城鎮的玩家進編輯器（會到大廳地圖）後離線，下次登入仍回那座城。
