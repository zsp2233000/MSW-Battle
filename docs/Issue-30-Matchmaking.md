# #30 統一配對與入場

## 操作方式

大廳與對局畫面右下角提供一顆可見按鈕；陣容編輯區會移到右上方並避開平台選單，避免遮住編輯操作：

1. 在整備區儲存一組有效編隊並設為出戰。
2. 按「開始配對」，按鈕切換為「取消配對」，持續顯示已等候秒數。排隊期間仍可編輯草稿。
3. 找到對手後等待既有保存結束，固定本局編隊並封存最新草稿，雙方自動進入同一隔離對局房間。
4. 房內顯示玩家人數，按鈕切換為「返回大廳」。返回後自動還原預存編隊與未保存草稿，再次提供「開始配對」。

**不再使用 F6／F7／F8／F9，也不需要手動按狀態鍵推進入場。** 狀態持續顯示在面板；原生日誌保留診斷資訊。

目前範圍是配對、隔離入場與返回，沒有在 `matchprobe` 房內啟動戰鬥核心。

## Maker 測試同 WorldInstance 配對

1. Refresh 後開始 Play。
2. 用 Maker Play 視窗的「新增虛擬玩家」開第二個客戶端；也可在 Maker Command Console 執行 `add_virtual_player`，不要指定 user_id，讓 Maker 配發身分。
3. 兩個視窗各自建立並保存有效出戰編隊，然後各按一次「開始配對」。
4. 第一人應留在排隊狀態，第二人入列後雙方自動進入同一房間。
5. 雙方應看到「玩家 2 / 2」與「返回大廳」，返回後仍可編輯原來草稿、再次配對。
6. 另測只有一人排隊後取消，等待時間停止，之後可重新加入；連按按鈕不應重複入列或建立房間。

Maker 使用伺服器 FIFO 佇列，參與者是真正連線的玩家／Maker 虛擬玩家；它沒有偽造原生配對 callback，也沒有使用真人世界的 leaderboard。虛擬玩家同樣必須有有效出戰編隊，不會自動複製其他玩家能力或繞過資格。兩個客戶端都能透過相同的可見按鈕操作。

Maker Play 重開後，本機 FIFO 會消失：舊的 `QUEUED`／`SAVING` 票據會自動取消並解除編隊鎖定；已封存的本機對局資料會在大廳還原草稿並清除票據。只有玩家位於票據指定的對局房間時，按鈕才會顯示「已進入對局房間」及房內人數。

## 公開發布環境：同／跨 WorldInstance 使用同一服務

公開發布環境使用原生 MatchmakingService；原本同一個 instance 或不同 instance 的玩家皆使用同一個「開始配對」入口與 queueName。測試需準備此世界的測試 leaderboard 與初始分數。

設定 `RootDesk/MyDesk/Matchmaking/MatchProbe.mlua`：

| 屬性 | 行為 |
| --- | --- |
| Enabled | 預設 true；false 可關閉配對 |
| LeaderboardId | 公開發布環境必填；Maker 本機配對不需要 |
| QueueName | 預設 issue30-controlled-v1，須在各 instance 一致 |
| TestProfileA / TestProfileB | 預設空白。皆空白時允許符合編隊資格的玩家；填入時限制發布測試帳號 |
| SaveDelaySeconds | 預設 0，可在受控測試中以 5／30／120 秒觀察成功後延遲封存的原生限制 |
| TransferLifetimeSeconds | 預設 900，是應用程式的入場期限，不能當成原生排隊或結果期限 |

跨 instance 的實際發布驗收仍需要兩個真實帳號；目前未準備發布測試世界與帳號，**尚不能宣稱跨 instance 驗收成功或關閉 #30**。

## 共用的交接流程

- 加入佇列時以 FormationService.ExportTransfer 驗證已保存且啟用的有效出戰編隊，固定本局編隊。
- 配對成立後，SealTransfer 等待既有保存完成，原子封存五組草稿、保存版本、編輯組及確認保存 bytes，並鎖定後續編輯，避免最後修改遺失。
- 使用每個 ProfileCode 專屬的 UserDataStorage key `Issue30TransferV1` 交接。探針的 capsule 上限為 16,000 UTF-8 bytes；這是應用限制，不能當成原生 extras 容量證據。
- 發布環境由 GetMatchUserInfosAndWait 驗證 Home／Away。伺服器 attempt GUID 與來源 WorldInstanceId 放在 native extras，參與者與目的房間都由伺服器驗證。
- 雙方 capsule 確認保存後，MatchTransferReadyEvent 喚醒來源協調器。接收端仍重新驗證原生配對與持久票據；事件內容本身不構成入場授權。
- Home 端持久化一次性 warpIssued 後呼叫 WarpMatchUser。同 instance 已集合的玩家可直接建立房間；跨 instance 先集合，再建立同一 match key 的 InstanceRoom。
- 到達事件自動推進剩餘入場與返回還原，沒有每幀或持續計時器輪詢 DataStorage。
- 就緒通知若傳送失敗，最多重試三次；繁忙期間收到的就緒提示會保留並在當次處理完成後推進。失敗後面板提供可見的重試入場操作。
- 返回時若目錄或先前保存尚未就緒，以快取 capsule 最多重試十次，之後提供「重試返回」。一旦還原成功，清理票據的重試不會再次匯入舊草稿，也不會覆蓋返回後的新編輯。
- 返回到**目的 WorldInstance 的整備區**，不保證返回原始來源 instance。還原後刪除 capsule 的編隊／草稿 payload，保留終止墓碑防止舊回覆重用。
- 玩家移到另一個 Room 後，來源 Room 不再向已離開的玩家送 UI RPC；目的 Room 重新發佈其狀態。
- 引擎回收空 InstanceRoom，RoomEnd 清掉失效本地 handle。

成功與取消的邊界是 SAVING → COMMITTING。封存前可以取消；封存寫入期間按鈕暫時停用。交接開始後可用可見的「取消入場」／「返回大廳」處理。原生 warp 一旦送出，能否撤銷其非同步移動仍需發布實驗，不能宣稱應用程式已能撤銷原生傳送。

原生服務回覆模糊、票據過期或傳送未完成時，不盲目重送 warp。應保留發布日誌並核對雙方狀態；斷線重返原對局不在本次保證內。

## 發布驗收表

| 實驗 | 必要證據 | 狀態 |
| --- | --- | --- |
| 同來源配對 | 兩名玩家相同來源 instance，真實原生配對結果，同一目的房間 | 待發布驗證 |
| 不同來源配對 | 兩個不同來源 instance，同一 match key、目的 instance、room key，實際房內 2 人 | 待發布驗證 |
| 未保存草稿往返 | 本局編隊不隨排隊後編輯而改變，返回後五組草稿與版本保留 | Maker 已檢查；發布待驗證 |
| 自動推進 | 雙方開始配對後，不需狀態鍵即完成集合、入場、返回還原 | Maker 已檢查；發布待驗證 |
| 原生期限與容量 | 排隊／結果期限、extras 容量、成功後延遲保存、讀取時機 | 待發布實驗 |
| 取消與重複操作 | 舊成功回覆不傳送已取消玩家，同一通知不建重複房間 | Maker 已檢查；發布待驗證 |
| 失敗與清理 | storage／建房／warp 失敗回覆，雙方返回後 payload 清理及房間回收 | Maker 往返已檢查；原生失敗待發布實驗 |

證據僅保留帳號 A/B 別名、WorldInstanceId／RoomKey、代碼、時間、版本及 bytes；遮蔽 ProfileCode、UserId、編隊與 capsule 原文。

## 執行紀錄與限制

初版已檢查編隊／草稿序列化、隔離房間與雙人返回；本次補上真正的 Maker FIFO 佇列與共用可見按鈕。測試透過原生 ButtonClickEvent 連線、QueueForUser 的相同伺服器入列路徑與原生 InstanceRoom API，沒有直接捏造成功通知。

2026-10-19 本次正向紀錄：

```text
[VRF][UnifiedMatch] visible=true initial=開始配對
[VRF][UnifiedMatch] queued=true cancelLabel=true
[VRF][UnifiedMatch] cancelled=true startLabel=true
[VRF][UnifiedMatch] arrivedState=IN_ROOM players=2 label=返回大廳
[VRF][MatchProbe] ARRIVED match=local-... users=2 ... distinctDraft=true
[VRF][MatchProbe] RETURNED restored=true cleanup=true
[VRF][MatchCleanup3] editDuringCleanup=true
[VRF][MatchCleanup3] newerDraftPreserved=true
[VRF][MatchLayout] lobby=true
[VRF][MatchLayout] editor=true
[VRF][MatchLayout] lobbyRestored=true
[VRF][MatchLayout] queued=true
[VRF][MatchLayout] cancelled=true
```

主玩家使用可見按鈕的 ButtonClickEvent 入列／取消／返回；第二名實際 Maker 虛擬玩家以公開 ServerOnly QueueForUser 進入相同佇列，編隊 fixture 由現有有效編隊經 ImportTransfer 準備。這沒有模擬原生跨 instance 成功通知。一般手動測試可在第二個客戶端自己整備並按同一顆按鈕。

返回失敗案例另外建立受控、伺服器產生的 RETURNING fixture，經相同 Recover／RestoreReturning 路徑執行，注入五次清理寫入失敗，在返回後編輯草稿，驗證清理完成後新內容仍存在。測試注入已復原為零。單次跨 Room 的 MakerScript 輪詢計時器曾因 context teardown 被引擎回收，該測試工具錯誤不作為產品成功證據；改以不跨 Room 的受控還原 fixture 完成上述檢查。

雙方正常返回後，Maker context 清單只剩 server_main 與 client，確認對局房間已回收。Standards／Spec 兩軸審查提出的單按鈕失敗復原、就緒通知遺失、重複還原覆寫草稿均已修正並複查。完整 Node suite 維持下列原始基線的 25/28。

新 instance map 需要經 Maker 開啟儲存以更新 entry Usage。已保存的 matchprobe.map 為 Usage=1、TileMapMode=1、IsInstanceMap=true，沿用 DefaultPlayer 的 Kinematicbody。

完整 Node suite 的原始基線 `4c5671ff2747031d4c98d6f37d125e5ba1efa7ac` 為 25/28，相同三項既存失敗涉及 CameraZoomPercent、DeploymentMinDistance=0.6 與怪物 fixture HP 500/300，不屬於配對改動。

若 WarpMatchUser 不符合發布實驗需求，可試驗以原生 Home/Away 為權威，封存 barrier 完成後透過 WarpUserToWorldInstanceAndWait 前往 Home 的來源 instance，再驗證票據並建立同一 InstanceRoom；滿員／退休 instance 與來源驗證仍需實驗。這個替代傳送方案尚未實作，不能當成已成功的路徑。
