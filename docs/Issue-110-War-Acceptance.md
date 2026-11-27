# #110 國戰發布環境雙帳號驗收（AC4）

status: not run

這份文件是 #110 第四項驗收（兩個真實帳號在**已發布世界**走完互選鄰城、原生配對、跨實例入場、戰果與返回）的執行手冊與結果表。Maker 探針（`tests/README.md` 的 "War integration (#110)"）已涵蓋 #110 前三項，但 Maker 無法做這一項：它需要發布世界、兩個真人帳號、原生配對服務與兩個 WorldInstance。

**目前沒有任何一列跑過。** 「實測」欄一律留空，由執行者在發布環境實際操作後填入；沒有實測就不要寫結果，也不要用 Maker 的結果代替。

為什麼獨立成一份文件，而不是併入 [Issue-30-Matchmaking.md](Issue-30-Matchmaking.md) 的「發布驗收表」：那張表是配對機制本身的實驗清單（一列一個實驗、只有狀態欄）；國戰驗收是一趟有順序的操作，每一步要有預期值、實測值與證據，還包含 #109 留下的保留期量測，所以用逐步表。配對機制的兩列（同來源、不同來源）仍以 Issue-30 為準，本表的 S5 提供它們需要的證據。

## 執行前提

1. **兩個真實帳號**，以下稱 A 與 B（紀錄時只用別名 A/B）。A 在本趟選 A 方、B 選 B 方。各自有一組有效、已啟用的出戰編隊（建議 A 三隻坦克、B 一隻坦克，戰果較可預期；也可用相同編隊，接受任一方獲勝）。
2. **已發布的世界**，且發布的版本包含 #110 的合併結果。記下發布版本與 CoreVersion、日期、對應的 git commit。`MatchFlow` 的 `LeaderboardId` 在發布環境必填（沒填會回報 `MATCHMAKING_NOT_CONFIGURED`），`QueueName` 在各 instance 一致（預設 `battle-centered-v2`），見 Issue-30「公開發布環境」一節。
3. **Maker 與發布環境的存檔互不相通**：Maker 裡的城鎮文件 `CountryWarV1`、玩家陣營與最後城鎮都不在發布環境；發布環境的城鎮文件從初始盤面開始（四城皆 100，左營 A 方、鼓山 B 方），除非先前有人玩過。開始前先記下盤面（每座城的兵力與歸屬，從城鎮 HUD 讀）。
4. **兩個 WorldInstance**：跨實例入場需要 A 與 B 在不同的 WorldInstance。平台決定玩家落在哪個 instance，這份文件不假設能指定。每個帳號登入後記下自己的 WorldInstanceId（發布日誌檢視器若有 instance 欄就讀它；每個房間開機時程式印一行 `[VRF][MatchFlow] world instance=`（後面接該房間所屬的 WorldInstanceId 與 RoomKey），沒有 instance 欄時就讀這一行；兩邊都看不到時，S5 的 instance 欄填「未能取得」，這是未決事項）。兩人落在同一 instance 時先完成同來源的列，再重新進出到不同 instance 重做 S3 到 S6。
5. **乾淨的票券**：兩個帳號登入後狀態都是 IDLE（上一次留下的票券會在登入時關閉，記 `STALE_ROOM_RECOVERY`）。
6. **鼓山只剩 20 才會換旗**：發布環境沒有改寫城鎮文件的工具（GM 面板只改玩家存檔；`FactionWar:WriteTowns` 只能由腳本呼叫）。S9 的換旗要不就用兩個帳號連打真人戰（四場勝利把鼓山壓到 20：100 → 80 → 60 → 40 → 20，第五場勝利換旗；S6、S7 已經算兩場，所以 S9 之前再打兩場，S9 本身是第五場），要不就由負責人另外提供一次性的發布腳本；在這個決定之前 S9 維持 not run。S8 的守衛勝利會再扣 10，先記下實際兵力，再依每場扣 20（真人戰）或 10（守衛戰）算剩下的場數。
7. **日誌**：能讀兩個 instance 與比賽房的發布日誌（`[VRF]` 行與時間）。留下證據時遮蔽 ProfileCode、UserId 與編隊內容，保留帳號別名 A/B、WorldInstanceId / RoomKey、代碼、時間、版本與 bytes。

## 如何填表

「實測」欄填實際觀察到的值（數字、狀態、地圖名稱），「要記錄的證據」欄填對應的日誌行、時間與截圖檔名；實測與預期不同時照寫，並把「狀態」改成 `fail`；無法執行時改成 `blocked` 並寫原因。狀態只有 `not run`、`pass`、`fail`、`blocked` 四種。

## 驗收步驟

| # | 步驟 | 預期值 | 實測 | 要記錄的證據 | 狀態 |
| --- | --- | --- | --- | --- | --- |
| S1 | A 登入、在遊戲大廳選 A 方、按進入前線；B 登入、選 B 方、進入前線 | A 落在左營、B 落在鼓山（起始盤面）；HUD 兩城兵力 100；兩人的陣營與最後城鎮都存下來 | | A/B 別名；`[VRF][FactionWar] front=zuoying faction=RED`、`[VRF][FactionWar] front=gushan faction=BLUE`、`[VRF][FactionWar] town remembered profile=`；各自的 WorldInstanceId | not run |
| S2 | A 在左營、B 在鼓山各自找城鎮 NPC 對話，看進攻選項 | A 的清單只有「鼓山」一項，B 的清單只有「左營」一項（起始盤面上，與各自所在城相連的敵城各只有一座；敵方主城與兩人所在的城都不相鄰，所以清單裡沒有主城，也沒有不相連的城鎮）；兩人都沒有排隊，所以選項狀態是 READY，進攻按鈕可以按 | | 兩張對話截圖（遮蔽名稱）；選項清單文字 | not run |
| S3 | A 選進攻鼓山、B 選進攻左營，兩人相隔不到 5 秒按下（在 10 秒守衛倒數之前） | 兩人都進入排隊並看到倒數；雙方配成同一場真人戰：原生佇列名稱為 `<QueueName>:war:gushan:zuoying`（兩城依字母排序）；兩邊各有 `SEALED`；**任何一方都沒有** `[VRF][Guard] ticket claimed by the` | | `[VRF][Guard] clock started target=`（兩帳號各一行及時間）；`[VRF][MatchFlow] SEALED`（含 `differentSources`）；佇列名稱不在程式日誌裡，若平台配對面板顯示就抄下，否則寫「未顯示」 | not run |
| S4 | （選用）用 GM 面板把 B 的陣營改成 A 方，讓 A 與 B 同在左營且都進攻鼓山，再還原 B 的陣營 | 同城兩人可能被原生服務放進同一佇列，但不會成局：配對結果被判無效（`QUEUE_RESULT_INVALID`），兩人都回到沒有排隊的狀態（ADR 0010 已知缺口：他們不會繼續等對岸玩家）；沒有房間被建立 | | `[VRF][MatchFlow] QUEUE_RESULT_INVALID` 與時間；GM 操作紀錄的修改前後（遮蔽）；兩人的狀態；是否建立過房間 | not run |
| S5 | 對 S3 的配對，記錄兩個帳號是否同一 WorldInstance，並看入場 | 同 instance 時：同一 match key、同一房間；不同 instance 時：`differentSources=true`，雙方各收一次就緒通知，Home 端只發出一次原生 `WarpMatchUser`（一次性 `warpIssued`），雙方進入同一個 RoomKey；房內 2 人 | | A/B 的 WorldInstanceId、房間所在的 WorldInstanceId、RoomKey；`[VRF][MatchTransfer] match=` 的 `entry=`；`[VRF][MatchedBattle] admission started=` 的 `started=true failed=false`；`[VRF][MatchedBattle] stamp home=`；同 instance 與不同 instance 各做一次 | not run |
| S6 | 讓戰鬥打完（不要中途斷線），兩人都在結果畫面按返回 | 結果只發布一次；落敗方城鎮兵力扣 20 且只扣一次（鼓山 100 → 80，或若 A 落敗則左營 100 → 80）；兩人的怪物等級存檔各含此 match key 一次，經驗值是各自 profile 自己陣亡的單位賺到的（沒有單位陣亡就是 0，0 也是有效結果）；A 回左營、B 回鼓山；返回後都不再鎖定；再次進城 HUD 顯示新的兵力 | | `[VRF][MatchedBattle] result published once match=`；`[VRF][FactionWarAttack] settle match=` 的 `status=SAVED loser= amount=20 flipped=false`；`[VRF][FactionWar] swap code=`（成功應為 0）；`[VRF][FactionWarAttack] landing user=` 兩行的 `destination=`；兩帳號的怪物等級存檔（GM 面板，遮蔽）是否各含此 match key 一次 | not run |
| S7 | 再打一場（同樣兩人互選），中途不要斷線，打完後比對兩個帳號各自看到的兵力 | 兩人看到同一個兵力（城鎮 HUD 只在進入城鎮與排隊回到 IDLE 時重讀，所以需重新進城或取消一次排隊後讀取）；兩場都由 A 勝時累計後鼓山 60（否則左營或鼓山依落敗方各扣 20） | | 兩人 HUD 截圖與時間；`[VRF][FactionWarAttack] settle match=` 第二筆 | not run |
| S8 | A 單獨排隊進攻鼓山，B 不排隊，讓 10 秒守衛倒數走完 | 滿 10 秒左右（8 到 14 秒內）守衛認領，只開一場守衛戰；A 勝時扣鼓山 10 兵力，輸或平手兩城都不變；守衛本身沒有 profile、沒有經驗值；只有 A 的怪物等級存檔含該 match key 一次，經驗值是 A 自己陣亡的單位賺到的（沒有單位陣亡就是 0，0 也是有效結果） | | `[VRF][Guard] ticket claimed by the`（接 gushan guard，與排隊時間差）；`[VRF][FactionWarAttack] settle match=`（match key 以 guard- 開頭，`amount=10`）；只有 A 的怪物等級存檔含該 match key | not run |
| S9 | 鼓山降到 20 後，A（A 方）贏第五場真人戰（前提 6：S6、S7 已經算兩場） | 鼓山改為 A 方並回滿 100（換旗次數 +1）；A 返回左營（出發城）並看到「上一場戰果：奪下鼓山。」；B 回鹽埕並看到鼓山失守提示；`[VRF][FactionWar] fall town=gushan owner=RED sent=` 為真 | | `[VRF][FactionWarAttack] settle match=` 的 `status=SAVED ... flipped=true owner=RED`；`[VRF][FactionWar] fall town=gushan owner=RED sent=`；`[VRF][FactionWar] sweep town=gushan`；`[VRF][FactionWar] evicted`；兩人落點；盤面前後對照 | not run |
| S10 | （需要第三個帳號 C，B 方，在**另一個** WorldInstance 的鼓山待命）在 S9 發生時觀察 C | 通知只送到發出事件的 instance 的靜態房（ADR 0012 已知缺口）：C 不會立刻被移走，直到下一個城鎮動作（進城、過門、找 NPC）才被送回鹽埕。記錄這段延遲，供負責人決定要不要補歸屬比對計時器 | | C 的 WorldInstanceId；`[VRF][FactionWar] fall town=gushan owner=RED sent=`（`RequestSendEventToRoomAsync` 的結果）；C 被移走的時間與觸發動作 | not run |
| S11 | 10 秒邊界的交錯：A 排隊，B 在 A 排隊後約 9 到 11 秒才排隊（反覆多次，每次記下兩邊的實際間隔） | 每張票券最多成立一場、不會同時在兩個房間。若原生 `Cancel` 在守衛認領的瞬間回 `AlreadyMatched`（ADR 0011 已知缺口），守衛可能認領一張已配到真人的票券，對岸玩家在比賽房等 30 秒（`MatchedBattle.AdmissionTimeoutSeconds`），之後依 ADR 0017 以缺席方的本局編隊照樣開戰；沒有人進房時入場失敗（`[VRF][MatchedBattle] admission started=false failed=true`）。記錄每次是真人戰、守衛戰或卡住 | | 兩帳號的 `[VRF][Guard] clock started`（毫秒時間）；`[VRF][MatchCancel] native code=`（認領時原生回的代碼）；`[VRF][Guard] a human match stands`、`[VRF][Guard] human result deferred`、`[VRF][Guard] ticket claimed by the`；入場逾時時的 `[VRF][MatchedBattle] admission started=false failed=true`；各次的結果 | not run |
| S12 | 兩場戰鬥同時結算同一座城（需要兩對帳號，即至少四個真人）：兩對各自互選左營與鼓山同時打，讓兩場結果幾乎同時抵達 | 只有實際造成兵力變化的結算完成；另一場在比較並寫入失敗後重新讀取再決定（`CONFLICT`），兵力不被互相覆蓋；原生 `UpdateAsync` 比對失敗回的代碼要抄下（程式假設原生回 `1000002`，`FormationStorage` 把它轉成 `2000000` 再回給呼叫端，`swap code=` 印的是轉換後的值，已發布世界實際回什麼要抄下來確認；`FactionWar:SwapTowns` 把 `2000000` 或 `1000007`（另一個首次建立進行中）判成 CONFLICT，其他非 0 判成 FAILED，出現其他值要特別標出） | | `[VRF][FactionWar] swap code=`（所有值，尤其非 0 的）；`[VRF][FactionWarAttack] settle conflict match=`；`[VRF][FactionWarAttack] settle match=` 的最終狀態；兩邊的結果 | not run |
| S13 | #109 量測一：網路斷線後引擎保留實體多久、才送出 Leave。在一場**守衛戰**中（A 單獨排隊，讓守衛認領，只有 A 一人在房內），打到一半把 A 的網路切斷（不要關閉應用程式：那是正常離開，不是斷線） | 記錄兩個時間：`reason=Disconnect` 的那一行，與房間被回收的那一行（A 是房內唯一的人，Leave 後約 1 秒內引擎回收房間）；兩者相減約等於保留期。同時記下 Leave 時的 `UserLeaveReason` | | `[VRF][MatchDisconnect] match=<key> combatPreserved=true online=false reason=Disconnect` 與時間；`[VRF][BattleCleanup] match=<key>` 與 `[VRF][MatchCleanup] room=` 的時間；保留秒數；`UserLeaveReason`（沒有票券的 Leave 也會印 `[VRF][MatchDisconnect] user=`，含 `reason=`；平台日誌看不到時就寫「未取得」） | not run |
| S14 | #109 量測二：守衛戰中單人斷線，在保留期內重連 | 回到同一場；戰鬥照常打完且只結算一次（`result published once` 一次、`settle` 一次）；重連的 client 再收到一次經驗收據；返回後依戰果落點 | | `[VRF][MatchDisconnect] match room reconnect recovers ticket`；`[VRF][BattleSession] experience receipt re-armed user=`；`[VRF][ResultExperience] sent profile=` 兩次；`[VRF][MatchedBattle] result published once match=` 一次；`[VRF][FactionWarAttack] settle match=` 一次；落點 | not run |
| S15 | #109 量測三：守衛戰中單人斷線，超過保留期才回來（或保留期過後才重新登入） | 房間已被回收、該局中止、不扣兵力、沒有經驗值；重新登入時 `Recover` 找不到房間，關閉過期票券，A 回到出發的城鎮；盤面與兩邊的經驗存檔都沒有這場的 match key | | `[VRF][BattleCleanup] match=`；`[VRF][MatchFlow] rejoin match= ... room=none`；`STALE_ROOM_RECOVERY`；沒有 `settle match=<key>`；落點；盤面前後對照 | not run |
| S16 | 真人戰中一方（A）斷線並在保留期內重連、另一方（B）一直在房內 | A 接回同一場；戰鬥、結算與經驗與沒有斷線時相同，各只一次。若 A 的實體已被送出 Leave 才重新登入且落在另一個 WorldInstance，靜態房看不到原比賽房（`InstanceRooms` 只含本 instance，ADR 0014 已知缺口）：`rejoin ... room=none`，A 依 `STALE_ROOM_RECOVERY` 與已存的戰果落點，戰鬥與結算仍由留在房內的 B 完成 | | `[VRF][MatchFlow] rejoin match=`（`moved=true` 或 `room=none`）；A 重新登入時的 WorldInstanceId 與房間的 WorldInstanceId；`result published once` 一次；兩人經驗各一次 | not run |
| S17 | 排隊第 8 秒登出（正常關閉應用程式），第 12 秒重新登入 | 離線時票券被取消並清掉守衛計時，第 10 秒沒有守衛戰；重新登入後狀態是 IDLE，要重新選進攻目標，10 秒從新的選擇重新計算。記錄原生 `Cancel` 在離開之後回的代碼；若取消沒有確認，重連時再取消一次而不接續 | | `[VRF][MatchCancel] native code=`；`[VRF][MatchFlow] leave cancel=true tombstone=true`（或 `war ticket whose leave cleanup failed is cancelled again, not resumed`）；`[VRF][MatchDisconnect] ... reason=`（`UserLeaveReason`）；第 10 秒沒有 `[VRF][Guard] ticket claimed by the`；重新排隊後新的 `[VRF][Guard] clock started` | not run |
| S18 | 登入落點。前提：鼓山 B 方、兵力 10（四場真人戰勝把鼓山壓到 20 之後，再讓 A 贏一場 S8 的守衛戰），A 站在左營、B 站在鼓山，兩人都是 IDLE。(1) A 在左營正常登出再登入；(2) B 站在鼓山正常關閉應用程式（登出）；(3) 只有 A 排隊進攻鼓山，守衛倒數走完，A 贏這場守衛戰（鼓山 10 → 0，換旗）；(4) 返回後 A 在左營（出發城）；(5) B 再登入。S9 與 S18 各是一次換旗，各走自己的盤面路徑（S9 在鼓山 20 時由 A 贏真人戰，S18 在鼓山 10 時由 A 贏守衛戰），不要在同一個盤面上各做一次 | (1) A 回到左營，每次登入只判斷一次；(2)(3) B 登出時實體已被移除，清掃看不到 B，所以不會有 `sweep skipped offline`（那一行只在 B 的實體還被保留時才出現，也就是網路切斷而不是登出，見最後的選用做法）；鼓山改為 A 方並回滿 100（換旗次數 +1），守衛只認領一次，A 返回左營並看到「上一場戰果：奪下鼓山。」；(5) B 被放到鹽埕（主城），顯示「鼓山已失守，已撤回主城。」，每次登入只判斷一次。選用，另做一次：(2) 改成切斷 B 的網路並在保留期內重連，這時清掃當下 B 的實體還在，會有 `sweep skipped offline`，B 重連時依 `UserReconnectEvent` 判斷，同樣被送到鹽埕 | | `[VRF][FactionWar] login placed user= ... destination=yancheng moved=true`（B）；`[VRF][FactionWar] login judged user=`（A 重新登入時站在左營，不需要移動）；`[VRF][Guard] ticket claimed by the`、`[VRF][FactionWarAttack] settle match=`（guard- 開頭，`flipped=true owner=RED`）、`[VRF][FactionWar] fall town=gushan owner=RED sent=`、`[VRF][FactionWar] sweep town=gushan present=`（B 不在內）；只有選用的網路切斷做法才會有 `[VRF][FactionWar] sweep skipped offline user=`；兩人的最後城鎮 | not run |
| S19 | 排隊中登出後，在另一個 WorldInstance 重新登入（S17 的跨實例版本）：A 進攻鼓山排隊（B 不排隊），第 8 秒正常登出；12 秒後重新登入，要落在和原本不同的 WorldInstance（平台決定落點，落在同一個就再登出登入，直到換成另一個，或記「未能換 instance」） | 離線當下取消成功（`leave cancel=true tombstone=true`）：持久票券已是 CANCELLED，新 instance 裡的 A 是 IDLE、沒有守衛倒數，要重新選進攻目標。離線當下取消沒有確認（`cancel=false` 或 `tombstone=false`）：持久票券仍是 QUEUED，而 `departFailed` 只存在原 instance 的記憶體裡，新 instance 看不到它，所以走一般的 `Recover`，不會「再取消一次」；原生佇列是否仍持有 A、這張票券後來有沒有被配對或被守衛認領，都照實記錄（這是已知缺口，不是預期行為） | | `[VRF][MatchFlow] world instance=`（兩個 instance 各一行，用來認出 A 前後在哪個 instance）；原 instance 的 `[VRF][MatchFlow] leave cancel=` 與 `[VRF][MatchCancel] native code=`；新 instance 登入時 `Recover` 的結果（`[VRF][MatchFlow] stale local queue cancelled=true`，或 `QUEUE_OWNER_LOST`，或票券狀態）；有沒有 `[VRF][Guard] ticket claimed by the`；A 的狀態 | not run |

## 結果判定

#110 第四項視為完成，需要：S1、S2、S3、S5、S6 各有實測且與預期相符（含同 instance 與不同 instance 各一次的 S5），S9 的換旗有實測，S13 到 S15 三項保留期量測各有數字或「未取得」的明確說明。S4、S7、S8、S10、S11、S12、S16、S17、S18、S19 的結果照實記錄；與預期不符的列要開成新的問題，不在這份文件裡改預期值。

## 未決事項（需要負責人決定）

- **WorldInstanceId 的日誌**：`_WorldInstanceService.WorldInstanceId` 是原生唯讀屬性（程式本來就拿它當票券的來源），所以 `MatchFlow` 在每個房間開機時印一行 `[VRF][MatchFlow] world instance=`（後面接 WorldInstanceId 與 RoomKey），S5、S16、S19 靠它認 instance。這一行還沒有在 Maker 或發布環境跑過；要由負責人確認發布日誌檢視器看得到它，看不到時 instance 欄仍填「未能取得」。
- **沒有票券的 Leave**：現在也印一行 `[VRF][MatchDisconnect] user=`（接 `no ticket reason=`，原因是 `UserLeaveReason`，網路斷線則是 `Disconnect`），S13 可以直接讀 Leave 的原因與時間；保留期仍要用 `Disconnect` 與 Leave（或房間回收）兩行的時間差來算，平台沒有直接給保留秒數。這一行同樣還沒有在 Maker 或發布環境跑過。
- **改寫發布環境城鎮文件**：沒有現成工具（S9 前提 6）。
- **S10、S12 需要的帳號數**：兩個帳號做不到，需要第三個或第四個真人帳號。
- **S11 的時間精度**：兩個真人用手按，很難落在 10 秒邊界的 100 毫秒內；若要穩定重現，需要由腳本在兩個帳號各自排隊，這也是程式改動。
