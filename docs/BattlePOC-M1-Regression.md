# M1 客觀回歸與地圖檢查

日期：2026-10-08。驗收來源：[GitHub #10](https://github.com/zsp2233000/MSW-Battle/issues/10)。專案 CoreVersion 為 26.10；本次新增測試及紀錄，沿用現有玩法、模型、UI 與人類資產。

## 驗證方法

本機執行 `node --test tests/*.test.cjs`：**24 / 24 PASS**。涵蓋結構契約、CSV 精確還原、獨立數值 fixture，以及取消後遲來回覆不能誤認為 Maker Stop 的橋接協議。

Maker 使用 `Stop → Clear logs → Refresh → Build logs → Play → Execute script → Normal logs`。每個 probe 使用新的 Play，等到最終 PASS 才判定成功。部署及戰鬥使用正式公開命令與原生 Attack / Hit；受控場景由 `PrepareBattleForTest` 建立，手動時鐘由 probe 取得並釋放，不修改內部 roster、傷害 queue 或結果狀態。移動與完整整局使用真實 Maker frames。執行方式見 [tests/README.md](../tests/README.md)。

## #10 驗收對照

| 驗收項目 | 客觀證據 | 結果 |
|---|---|---|
| 怪物名稱與 ID、重複部署、同種類不同怪物 | `SixVsSixUI` 使用已連接的卡片 ButtonClickEvent 與正式部署 RPC；`VariantUI` 驗證改名原 ID 與另一個 TANK 各有獨立名稱卡片 | PASS |
| 零、第一、第六、第七隻；部署區、0.6 間距、移除與開戰後修改拒絕 | `DeploymentProbe` 公開命令邊界檢查；`SixVsSixUI` 另經已連接的開始按鈕拒絕零隻、逐一部署六隻及拒絕第七隻 | PASS；原資料還原後已複驗 |
| 最近存活目標、移動／死亡後重選、同距離保留目標 | `TargetCrowdingProbe` 完整 controlled roster 與真實移動／死亡 | PASS |
| 三筆初始 dataset 數值、同種類獨立數值、固定傷害 | `CatalogValidation` 核對正式三列；`CatalogVariant` 正式部署獨立 TANK 數值，原生命中 40 + 25 後敵方 HP 為 435、傷害 serial 為 2；`AttackExecutionProbe` 核對戰士 35、射手 30 | PASS |
| 坦克多目標接觸與各目標冷卻、擊退邊界、射手無投射物 | `TankProbe`、`ShooterProbe`、`AttackExecutionProbe`；位移採真實 Maker frames | PASS |
| Win、Lose、同批 Draw、一次 RESULT、唯一訊號、結果後停機 | `SixVsSixBatch` 測兩種同批命中順序；`TargetCrowdingProbe` 測自然結果；`SixVsSixFullBattle` 自然 12 單位單局後再觀察 1 秒 | PASS |
| 死亡立即退出存活計數／索敵、拒絕後續傷害 | `TargetCrowdingProbe` 的實際死亡重選；`AttackExecutionProbe` 保留存活 reserve，在 BATTLE 中送達遲來 HitEvent，核對 HP、serial、history 與存活數不變 | PASS |
| 完整死亡動畫結束後才隱藏 | `SixVsSixUI` 觀察原生 SpriteAnimPlayer 事件：本次 10 個死亡單位全部在播放開始時仍可見，完成播放後才隱藏；不填死亡秒數 | PASS |
| 缺少／重複 ID、改名、非法種類、無效數值、空白命中影格、共用 RUID、跨陣營共用 ID | `CatalogValidation`、`CatalogVariant`、`VariantUI`；戰士／射手空白影格預設 1，0 或超出 clip 範圍拒絕 | PASS |
| 部署 UI → 六對六 → 正確結果 UI | `SixVsSixUI` 由已連接卡片／開始按鈕事件啟動，自然 RESULT 在 45 秒內產生，只有匹配結果實體啟用且結果訊號只有一次 | PASS |
| 實際列舉、逐圖檢查、保留人類內容及可正常載入 | 實際全專案列舉只有 `map/map01.map`；MapBuilder 檢查全部 12 個 entity，Maker fresh Play 載入成功；詳見下表與 hash | PASS |
| 無未解 POC 建置／執行錯誤 | 每次 Refresh 的 build logs 為 83 筆 Info、0 Warning、0 Error；正常整局與其餘完成的 probes 沒有 Warning / Error，唯一刻意非法 profile 診斷如下說明 | PASS |

死亡後 HitEvent 案例先對已死亡目標呼叫公開 `StateComponent:DisconnectHitEvent()`，只解除原生 StateComponent 的自動 `ChangeState("HIT")` listener，保留 BattleUnit 的傷害 listener。這避免在人工送達遲來事件時要求原生 DEAD → HIT 轉移；另用 `ConnectEvent(HitEvent, ...)` 證明事件確實送達，而非把引擎拒絕派送當成傷害守衛通過。此隔離只存在於該 fresh Play，結束後重建原生 listener。

正式 CSV 的射手 `AttackIntervalSeconds` 目前為 **2.0**；舊 GDD 表格的 0.8 與目前人類資料不同。本票依正式 dataset 驗證，不調整平衡數值。

## Maker 最終 verdict

| Probe | Context | 最終訊號 |
|---|---|---|
| `deployment_runtime_probe.lua` | server_main | `[M1][DeploymentProbe] PASS`；原資料還原後 |
| `attack_execution_runtime_probe.lua` | server_main | `[M1][AttackExecutionProbe] PASS` |
| `tank_contact_runtime_probe.lua` | server_main | `[M1][TankProbe] PASS` |
| `shooter_runtime_probe.lua` | server_main | `[M1][ShooterProbe] PASS` |
| `targeting_crowding_runtime_probe.lua` | server_main | `[M1][TargetCrowdingProbe] PASS` |
| `six_vs_six_batch_outcome_probe.lua` | server_main | `[M1][SixVsSixBatch] PASS` |
| `six_vs_six_full_battle_probe.lua` | server_main | `[M1][SixVsSixFullBattle] PASS`；原資料還原後已複驗 |
| `six_vs_six_ui_runtime_probe.lua` | client | `[VRF][SixVsSixUI] PASS` |
| `monster_catalog_validation_runtime_probe.lua` | server_main | `[VRF][CatalogValidation] PASS` |
| `monster_catalog_variant_runtime_probe.lua` | server_main，暫存 CSV | `[VRF][CatalogVariant] PASS` |
| `monster_catalog_variant_ui_runtime_probe.lua` | client，暫存 CSV | `[VRF][VariantUI] PASS` |
| `monster_catalog_restored_runtime_probe.lua` | server_main，原 CSV | `[M1][CatalogRestoreProbe] PASS` |

`CatalogValidation` 的預期非法輸入由 `ParseRow` 回傳驗證訊息，本次 152 筆日誌沒有 Warning / Error。`AttackExecutionProbe` 刻意測非法 attack profile，預期恰好一筆 `[M1][BattleAttackComposition] unsupported attack profile` 診斷；其他錯誤不列為可接受。

## CSV 暫存與還原

`withTemporaryMonsterCsv` 已完成真實 Maker Stop、Refresh 與還原後 fresh Play catalog verifier 的交易。原始與還原檔皆 **1458 bytes**，逐位元相同，SHA-256 皆為：

```text
824644393d4c0294da8d80af4b6629d7d4d88f0d088eda8102edba0901202ec3
```

暫存同種類測試列採 HP 650、移速 0.7、傷害 25、攻擊間隔 1.3、距離 0.8、接觸冷卻 1.3；原 TANK 的 ID 與數值不變，只改顯示名稱。所有 RUID 與原 TANK 共用。測後原名 `Tank`、三個正式選項及零玩家部署皆已確認，暫存 ID 不存在。帶 request ID 的橋接交易最終 `[VRF][CatalogFixture] PASS`、退出碼 0；每筆 Stop、Refresh 與 restored verifier 皆在真實 Maker 操作完成後才回覆相同 ID。備份交易成功結束，暫存 row、backup 與 manifest 均未納入提交。

## 實際地圖清單與處置

以全專案 `rg --files -g '*.map' -g '!.agents/**'` 實際列舉，只有 `map/map01.map`。MapBuilder 讀取結果：`TileMapMode=1`（RectTile）、非 instance、12 entities、77 tiles、0 footholds。

| Entity | 處置理由 |
|---|---|
| `map01` | 保留 BattleSession、固定相機與部署輸入 |
| `Background` | 保留現有背景 |
| `M1_EnemyAssault`、`M1_EnemyAssault2` | 保留正式戰士配置 |
| `M1_EnemyShooter`、`M1_EnemyShooter2` | 保留正式射手配置 |
| `M1_EnemyTank`、`M1_EnemyTank2` | 保留正式坦克配置 |
| `MapleMapLayer` | 為原生 MapLayerComponent 容器；名稱不能作為範本殘留證據，保留 |
| `RectTileMap` | 保留人類地形與 77 tiles |
| `sprite-12960527`、`sprite-12960527_1` | 用途未確認的既有裝飾，保留 |

未發現可確認的範本殘留 Entity 或未使用範本地圖，因此沒有刪除內容，也沒有需要取得刪除確認的地圖。地圖測前／測後 SHA-256 相同：

```text
98aa3aba235d8d11e1d6bd093036e01ef656cc1d5a2b8a97286b83429fbab233
```

## 人工驗收邊界

本票記錄名稱／ID 綁定、玩法與數值、原生動畫完成、結果 UI 及日誌的客觀驗證。畫面美感、HP 條／傷害數字可讀性、特效與聲音品質、操作手感及整局體驗仍由人類在 Maker Play 判斷；M1 不因本票而標記整個里程碑完成。
