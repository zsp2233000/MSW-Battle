# 地圖與編隊規範

`map/map01.map`、`map/formationsim.map` 與 `map/matchprobe.map` 共用地形與 BattleCameraAnchor。2026-10-23 使用者確認沿用後續修訂的 209 個地塊、目前相機與 x=0.5 鏡射；取代 #35／#37 原先的 30×16、世界原點及 x<0 規格。290 為筆誤，不重畫目前地圖。ADR 0001 的 RectTile／Kinematicbody 決策繼續適用。

| 項目 | 基準 |
|---|---|
| TileMapMode | 1 / RectTile，無重力 |
| 地形總數 | 209 個地塊：153 個可行走、56 個外牆 |
| 可行走戰鬥內場 | 17 × 9，共 153 個地塊 |
| 內場格點 | X=-8..8，Y=-4..4 |
| GridSize | 1 × 1 世界單位 |
| 水平鏡射軸 | 世界 x=0.5；世界座標反射 (x,y)→(1-x,y) |
| 原生內場世界邊界 | X=[-8,9)、Y=[-4,5)，以 Maker 原生轉換驗證 |
| 外牆 | 格點 X=-9／9、Y=-5／5，共 56 塊 |
| 玩家展示 | 客戶端視覺 Y=4.2；水平位置由 CharacterPosition.x 及其鏡射決定，與戰鬥碰撞分離 |
| 原生格點轉換 | IsOddGridPosition=false；世界位置以 ToWorldPosition／ToCellPosition 驗證；水平鏡射格點 (-x,y) |
| 地塊容器 | Transform 保持 (0,0,1000)，未平移、縮放地塊容器 |
| 地塊素材 | 原有 tileset 的可行走地塊 93、牆壁 47（檔案索引） |
| 相機 | Anchor=(0,0,0)，CameraOffset=(0.5,0)，ZoomRatio=60；ScreenOffset=(0.5,0.5)、Damping=(0,0)、Cut、blendTime=0 |

地塊格線是地形資料，並非布陣槽位。保存 `monsterId`、`x`、`y` 的原始連續世界座標，不取整、吸附、縮放或重排。MSW Vector3 本身具有浮點精度差異；保存值須與收到的座標相同。每組仍為 1–6 個單位、共用 MonsterCatalog、同兵種可重複，最小間距 0.3。

伺服器僅接受單位中心 x<0.5，且 (x,y) 與 (1-x,y) 都存在原生可行走地塊。x=0、0.25、0.49 的可行走落點可接受；x=0.5、右側、非有限值、外牆、缺失地塊及鏡射後非法均拒絕。FormationMapLayout 是 POC 部署、草稿、保存與配對入場的共用邊界；Bounds 的 X=[-15,15)、Y=[-8,8) 是額外安全外框，不代表這些範圍內都有地塊。對手與反向觀看者共用 MirrorX=1-x，不平移或翻轉伺服器物理地圖。

模擬地圖預覽為客戶端純視覺實體，採用正式 catalog 待機動畫，不掛戰鬥、碰撞或 AI。左鍵選取／放置／移動；右鍵或工具列移除。選兵後可用左上方「收起整備面板」露出完整左半場，再以同一按鈕展開保存／啟用；收合保留兵種、單位選取與草稿。工具列覆蓋區不接受地圖放置。

資料以 `BattleFormationsV2`／schema=2、`BattleTransferV2`／coordinateSchema=2 及 queueName=`battle-centered-v2` 隔離。舊 V1 鍵不讀取、不遷移，舊五組內容及啟用選擇不再有效；舊 schema 或交接不能匯入新版。這是一次性的命名空間切換，非每次登入或回程清空。首次缺少新版鍵才從五空欄位、activeSlot=0 開始；逾時、讀取錯誤及損毀資料維持 ERROR，禁止覆寫。新版保存確認、啟用、固定本局編隊與同次登入草稿往返語意不變。

新增戰場透過 MapBuilder 從 map01 複製，保留地形、相機與 GridSize；改動可行走區時須重新驗證原生位置與鏡射落點，不能只比較外框大小。#36 的隔離原型已在 #38 正式整合時移除，保留歷史文件與證據。

[#37 紀錄](Issue-37-Centered-Battlefield.md) 中的 636 地塊、Zoom 32 與舊取景數值屬當時版本，不作為目前地圖的驗收證據。現行地形與相機由 `formation_contract.test.cjs` 驗證，原生鏡射由 `centered_terrain_runtime_probe.lua` 驗證，POC／編隊邊界一致性由 `formation_poc_regression_runtime_probe.lua` 驗證。行動裝置適配與發布環境跨 WorldInstance 驗收仍不在本次驗證內。

2026-10-23 本次修正後：Maker Refresh 與 build 零 Error；Play 中取得 map01／formationsim 各 209 地塊、153 可行走、原生世界邊界 (-8,9,-4,5) 及鏡射 PASS。FormationTerrain 的空草稿／空出戰拒絕、權威欄位清理與無效站位測試 PASS；FormationPOC 的 x=0／0.25／0.49 接受、x=0.5／0.51 拒絕與正式部署／移除測試 PASS，無保存玩家資料。相關 Node 契約 6/6，全套 26/29；剩餘三項相機欄位、間距與坦克 HP 的舊期望在 main 也不符合既有程式。本次未重跑完整保存／跨 instance 流程。
