# #37 中央原點戰場與新版編隊

## 範圍與前置證據

#36 已結案，Maker 雙方視角技術驗證與使用者驗收見 [Issue-36-Battle-View.md](Issue-36-Battle-View.md)。本票才切換正式地形與資料；#35 明確取代原「保留舊地形」限制，使用者另於本次實作明確授權程式重建地塊陣列並在 Maker 驗證。未執行全世界 DataStorage reset。

`map01`、`formationsim`、`matchprobe` 共用 30×16 內場、實際中心 (0,0)、外牆及上方展示區；完整座標、相機及版本規則見 [Map-Formation-Standard.md](Map-Formation-Standard.md)。`battleviewprototype` 保留為 #36 隔離場景。

## 資料切換

新版只讀寫 `BattleFormationsV2`，文件 schema=2；交接使用 `BattleTransferV2`、coordinateSchema=2；配對 queueName=`battle-centered-v2`。不讀取或搬移 V1，舊五欄位與啟用組不會復活；舊交接亦不能匯入。首次沒有 V2 鍵才出現五空欄位及 activeSlot=0，仍須保存並啟用有效編隊才可配對。新版一般登入、重試、取消排隊及戰後返回皆不重置內容。讀取錯誤維持 ERROR，禁止以空白內容覆寫。

編隊驗證共用原點、左側 x<0 與原落點／鏡射落點的原生可行走檢查。(-15,y) 因鏡射到被排除的 x=15 而拒絕；(-14.99,-8) 與 (-0.01,7.99) 可接受。不吸附或取整；例如 Vector3(-4.35,0.65,0) 在引擎內為 (-4.3499999046325684,0.6499999761581421)，保存與收到的座標完全一致。

整備面板可用左上方按鈕收合，保留目前兵種與選取，再點完整左半場布陣；展開後保存／啟用。回大廳仍使用整備面板內的「返回大廳」。

## 重跑程序

先確認 Maker 開啟本工作區（本次 get_current_map 為 battleviewprototype，UUID 與檔案一致）。Stop → Refresh → build logs → Play，再將探針完整內容送到對應 `maker_execute_script`，並讀 normal logs 的最終 PASS。

| 步驟 | 執行介面與預期 |
|---|---|
| 靜態地圖／編隊 | `node --test tests/formation_contract.test.cjs`；三張地形／相機一致、480 內場、對稱外牆、容器原位、純視覺預覽 |
| 原生地形 | `centered_terrain_runtime_probe.lua`，server_main；每個中心經 ToWorldPosition／ToCellPosition 檢查原點、範圍、鏡射及外牆 |
| 空白→保存 | 新 V2 帳號執行 `centered_formation_runtime_probe.lua`，client；公開 RPC 拒絕非法值、原始小數預覽／保存、獨立啟用與重入保留 |
| 重登 | 上一步後 Stop／Play，再執行同探針；必須先有 RELOGIN_PASS，再有完整 PASS。此步須在下方配對 fixture 改寫測試編隊前執行 |
| 交接／缺地塊 | `centered_transfer_validation_runtime_probe.lua`，server_main；已載入帳號、拒絕舊 schema／交接、缺失原落點／鏡射落點及鏡射牆壁；測試結束恢復原生地塊 |
| 讀取失敗 | server_main 呼叫 FormationStorage.ConfigureMakerFaults(1,0,0)，client 呼叫 FormationService.RequestRetryLoad；觀察 ERROR 且保存內容／出戰組不變，再 RetryLoad 恢復 READY |
| 完整下半場點選 | client 用 ButtonClickEvent 進整備、選兵、點 ReturnLobby 收合；maker_mouse_input 在 1920×1080 的 (624,252) 左鍵，觀察新增原生世界 (-7,-6)；再展開面板、檢查草稿保留 |
| 同 instance 配對 | Maker Command Console `add_virtual_player`，等待兩名玩家；執行 `matched_battle_queue_runtime_probe.lua`，server_main。兩位均由正式保存／啟用命令準備；取消／重排隊後，排隊固定六單位，再保存一單位作為未來對局內容 |
| 正式戰場 | 新 server_instance_local-* 執行 `centered_terrain_runtime_probe.lua`，證明 matchprobe 原生地形；再執行 `matched_battle_room_runtime_probe.lua`，觀察正式 6v1 自然 WIN／LOSE、終局穩定、返回大廳及全部保存／草稿保留 |
| 相機 | client 原生 ScreenToWorldPosition(0,0)／(ScreenWidth,ScreenHeight)：(-20,-11.25)..(20,11.25)，Anchor=(0,0,0)、CameraOffset=(0,0)、ZoomRatio=32、blendTime=0 |
| 移動與碰撞 | `unit_motion_physics_runtime_probe.lua`，server_main；使用新外牆作為臨時牆 fixture，測三兵種追擊、原生命中、擊退、碰牆、暫停、重新配置與死亡；結束 Reset 臨時地塊 |
| POC | `map01` 正式 TryDeployMonster 放六單位、TryStartBattle，觀察自然結果與一秒後終局不變；既有 `six_vs_six_full_battle_probe.lua` 亦可作為固定位置版本 |

配對／POC／移動探針不要同時在同一 context 執行；maker_execute_script 新呼叫會取代該 context 尚在執行的腳本。對局探針執行返回後，instance context 會被回收，之後再向該 key 派送不構成測試。

## 2026-10-23 Maker 證據

實際執行 Refresh、build logs、Play、normal logs、原生滑鼠輸入與以下公開介面探針。開發前先重現舊程式接受 x=0：`[VRF][Issue37Red] EXPECTED_FAIL ... centre must be rejected`。新版正向證據：

```text
[VRF][CenteredFormation] EMPTY_V2_PASS
[VRF][CenteredFormation] RELOGIN_PASS
[VRF][CenteredFormation] PASS boundary rejection; exact preview/save/activation; reentry preserves V2
[VRF][CenteredTerrain] PASS map=map01 walkable=480 bounds=-15,15,-8,8 centre=0,0
[VRF][CenteredTerrain] PASS map=formationsim walkable=480 bounds=-15,15,-8,8 centre=0,0
[VRF][CenteredTerrain] PASS map=matchprobe walkable=480 bounds=-15,15,-8,8 centre=0,0
[VRF][CenteredLoadFailure] PASS error preserved V2; retry restored saved active selection
[VRF][CenteredTransfer] PASS old coordinate handoffs rejected
[VRF][CenteredTerrainValidation] PASS missing original, missing mirror, mirrored wall rejected; native tiles restored
[VRF][CenteredInput] PASS collapsed toolbar; native mouse lower-field placement; expanded controls and draft retained
[VRF][CenteredCamera] PASS origin=0,0 zoom=32 cuts=0 visible=(-20.000, -11.250)..(20.000, 11.250)
[VRF][MatchedBattle] initialized home=6 away=1 started=true
[VRF][MatchedRoom] PASS immutable 6v1; natural WIN/LOSE; stable terminal; return dispatched
[VRF][MatchedPreservation] PASS five saved slots, active selection, draft contents and editor selection
[VRF][CenteredPOC] PASS official 6v6; natural=LOSE stable terminal
[VRF][UnitMotionPhysics] PASS
[VRF][CenteredEmptyQueue] PASS five empty slots; no active roster; queue rejected
[VRF][CenteredFinal] PASS after return V2 retained
```

初次小數測試直接比較 Vector3 與 double 常值而失敗，改為比對收到的座標，並核對上述引擎原始浮點值。初次移動回歸的舊牆壁 fixture 位於新內場，已改用真正外牆與原生 tileName，避免 tileset 索引差異。一次臨時 client 探針在對局 room 的整備觀察尚未恢復時讀取 saved，產生 MakerScript-only nil 錯誤；改為等待回程及 snapshot 恢復後取得 CenteredFinal PASS。這些初次失敗不列為產品通過證據。

本次 Maker build errors=0。完整 Node suite 為 25/28；與 [#30 已記錄基線](Issue-30-Matchmaking.md) 相同的三項既存失敗：舊 CameraZoomPercent 原始碼斷言、DeploymentMinDistance=0.6 舊斷言、fixture HP 500/300 舊期望。本次地圖／編隊 contract 5/5 通過；未為消除既存失敗改寫其期望。

## Standards

獨立代理審查本次暫存變更與 AGENTS、領域文件、ADR 及 MSW 規範，未發現可行動的新違規。審查基準為 f092107；排除工作開始前既有的 battleviewprototype.map 與兩份 .ui 未提交變更。

## Spec

另一獨立代理對照 #37／#35，追查整備、保存、啟用、交接、鏡射、相機與配對呼叫端，未發現可行動的新缺漏或範圍外實作。兩軸各 0 項發現；代理未重跑 runtime，實際 Maker 證據由本次實作流程取得。

## 驗收邊界

本次同一實際客戶端加 Maker 虛擬玩家的同 instance 配對證據，不能替代 #31 的發布環境跨 WorldInstance 驗收。各自我方左側的正式呈現、血條與雙方角色整合屬 #38；本票只證明新版地形、編隊資料與共同伺服器對局相容。行動裝置適配仍在範圍外。
