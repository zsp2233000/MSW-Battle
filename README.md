# MonsterData

[`MonsterData.csv`](RootDesk/MyDesk/Data/MonsterData.csv) 是怪物資料的可讀、可版本控制清單。每列描述一種可重用的怪物設定：穩定 ID、顯示名稱、模型、戰鬥數值，以及動畫、命中特效和音效 RUID。

## 執行時如何讀取

[`BattleSession`](RootDesk/MyDesk/Combat/BattleSession.mlua) 透過 `_DataService:GetTable("MonsterData")` 讀取名為 `MonsterData` 的伺服器 UserDataSet。資料載入時會檢查欄位、每列內容與固定敵軍引用；資料不合法時，戰鬥會停止並記錄 `CONFIG_ERROR`。

CSV 是方便編輯與檢視的檔案；執行時讀取的是 Maker 中的 UserDataSet，不是磁碟上的 CSV 路徑。修改 CSV 後，請同步匯入或更新 Maker 的 `MonsterData` UserDataSet，並確認欄位名稱和資料列一致。[`MonsterData.userdataset`](RootDesk/MyDesk/Data/MonsterData.userdataset) 是 UserDataSet 資源描述，不是資料列內容；請勿用它代替 CSV 編輯表格資料。

## 維護規則

- 保留標題列中的所有欄位名稱。即使某欄的值可空白，`BattleSession` 仍會要求該欄存在。
- 每列的欄位順序須與標題列一致；CSV 值含逗號時，請依 CSV 格式加上引號。
- `MonsterId` 必須非空且唯一，並視為穩定鍵。改名請改 `MonsterName`；若更改固定敵軍使用的 ID，也要同步調整 `BattleSession` 的敵軍 ID 設定。
- 目前固定敵軍各使用兩列：`monster_tank`（`TANK`）、`monster_warrior`（`ASSAULT`）、`monster_shooter`（`SHOOTER`）。更換 ID 時，記得更新相應的 `EnemyMonsterId1`～`EnemyMonsterId6`。
- `MonsterType` 只接受 `TANK`、`ASSAULT`、`SHOOTER`。固定敵軍的六個 ID 也會依位置要求相符的種類。
- `ModelId` 必須是專案內可生成的 Model ID；`MonsterName` 與 `ModelId` 不可空白。
- 數值欄位都必須提供有效數字，以下另列可用範圍。空白不會自動沿用其他列或程式預設值。
- `StandAnimationRUID`、`MoveAnimationRUID`、`AttackAnimationRUID`、`HurtAnimationRUID`、`DieAnimationRUID` 目前都必須非空。載入器會確認資源類型、載入攻擊與受擊動畫，並驗證影格與播放時間。
- `AttackEffectRUID`、`HitEffectRUID`、`AttackSoundRUID`、`HurtSoundRUID`、`DieSoundRUID` 可以留空。CSV 中用空欄表示，不必填 `TBD`。這五欄的空值會正規化為空字串。
- `AttackEffectRUID` 留空時不顯示出手特效；填值時必須為 AnimationClip，與攻擊動畫一起播放，不等待 `AttackDamageFrame`。
- `HitEffectRUID` 留空時不顯示命中特效。任一音效欄留空時，只略過該音效。
- 非空動畫與音效 RUID 必須符合資源類型；無法載入攻擊或受擊動畫時，沿用 `CONFIG_ERROR` 流程。

## 欄位說明

| 欄位                      | 用途與驗證                                                                 |
| ------------------------- | -------------------------------------------------------------------------- |
| `MonsterId`               | 穩定、唯一的識別鍵；固定敵軍設定會引用它。                                 |
| `MonsterName`             | 顯示名稱；可修改，不影響以 `MonsterId` 查找。                              |
| `MonsterType`             | `TANK`、`ASSAULT` 或 `SHOOTER`，決定戰鬥行為與攻擊器。                     |
| `ModelId`                 | 生成時使用的專案 Model ID；不可空白。                                      |
| `MaxHp`                   | 最大生命值；正整數。                                                       |
| `MaxHpGrowthRate`         | 每級最大生命成長率；Lv1 基礎值的比例，有限數字且大於或等於 0。初始三隻怪物皆為 `0.035`。 |
| `MoveSpeed`               | 移動速度；大於 0。                                                         |
| `AttackDamageMin`         | 傷害區間下限；正整數，每個命中目標各自等機率抽取整數，包含上下限。                       |
| `AttackDamageMax`         | 傷害區間上限；正整數，不可小於下限。                       |
| `AttackDamageGrowthRate`  | 每級傷害成長率；上下限共用，有限數字且大於或等於 0。初始三隻怪物皆為 `0.035`。 |
| `AttackIntervalSeconds`   | 攻擊間隔秒數；大於 0。                                                     |
| `AttackRange`             | 從身體中心往前延伸的水平射程，必須大於 0；與目標受擊碰撞框重疊即在範圍內。 |
| `AttackRangeY`            | 前方攻擊矩形從身體中心往上、往下各延伸的距離，必須大於 0。               |
| `AttackDamageFrame`       | 所有種類結算命中的影格；必填正整數，從 1 開始，不可超過攻擊動畫影格數。 |
| `RetargetIntervalSeconds` | 重新尋找目標的間隔秒數；大於 0。                                           |
| `HitStopDurationSeconds`  | 受擊停頓秒數；大於或等於 0。                                               |
| `KnockbackDistance`       | 坦克命中擊退距離；坦克必須大於 0，其他種類可填 `0`。                       |
| `StandAnimationRUID`      | 待機動畫 RUID；必填，也用於怪物選項肖像。                                  |
| `MoveAnimationRUID`       | 移動動畫 RUID；目前坦克展示會使用。必填。                                  |
| `AttackAnimationRUID`     | 攻擊動畫 RUID；所有種類必填。                                        |
| `HurtAnimationRUID`        | 受擊動畫 RUID；目前坦克展示會使用。必填。                                  |
| `DieAnimationRUID`        | 死亡動畫 RUID；目前坦克展示會使用。必填。                                  |
| `AttackEffectRUID`       | 出手時附著在攻擊者身上的特效 RUID；可空白。每次出手播放一次，揮空仍播放，依顯示實體同步朝向。 |
| `HitEffectRUID`           | 命中特效 RUID；可空白，空白時不顯示特效。                            |
| `AttackSoundRUID`         | 攻擊音效 RUID；可空白，空白時不播放攻擊音效。                              |
| `HurtSoundRUID`          | 受擊音效 RUID；可空白，空白時不播放受擊音效。                              |
| `DieSoundRUID`            | 死亡音效 RUID；可空白，空白時不播放死亡音效。                              |

## 數值規則摘要

- 所有種類：`MaxHp`、`AttackDamageMin`、`AttackDamageMax` 為正整數，且 Max ≥ Min；`MoveSpeed`、`AttackIntervalSeconds`、`AttackRange`、`AttackRangeY`、`RetargetIntervalSeconds` 必須大於 0；`HitStopDurationSeconds` 不可小於 0。
- 所有種類：`AttackDamageFrame` 必須介於 1 與攻擊 clip 影格數之間。
- 怪物等級為 Lv1–30，只有最大生命與傷害區間隨等級成長，各自套用 `floor(基礎值 × (1 + 成長率 × (等級 − 1)))`。成長率可為 0；不改變移動速度、攻擊間隔或攻擊範圍。
- `TANK`：`KnockbackDistance` 必須大於 0，其他種類可填 0。坦克的每次範圍攻擊共用一個攻擊間隔，每個目標各自抽取傷害。

三種怪物的走位、出手與命中共用前方矩形判定。水平範圍外直線接近，水平已重疊時只上下對齊；進入範圍後站定，出手朝向維持到攻擊動畫結束。命中影格不重新轉向。戰士與射手只打出手時鎖定的目標；坦克打命中影格時範圍內的所有敵方存活單位，每個目標一次，走路不造成傷害。坦克命中一律擊退（含攻擊中的目標），不造成受擊停頓；被擊退者繼續攻擊並從新位置判定命中。

坦克正式攻擊動畫為 `34dfeaf570954ce49503dc8100c2ddee`；命中影格為第 8 格，攻擊間隔為 5 秒，依專案負責人最新資料設定。

## 新增或修改資料列

1. 在 CSV 中新增或修改一列，保留原有標題與欄位順序。
2. 確認 `MonsterId` 唯一、`MonsterType` 合法、`ModelId` 可生成，且必要數值和動畫 RUID 已填妥。
3. 沒有要使用的命中特效或音效時，將對應的可選 RUID 儲存格留空；不要刪除欄位標題。
4. 將更新後的列同步至 Maker 的 `MonsterData` UserDataSet。只修改 CSV 不會改變執行時已匯入的 UserDataSet。
5. 若新怪物要加入固定敵軍，更新 `BattleSession` 對應的敵軍 ID，並確保 ID 的 `MonsterType` 符合該位置要求。
6. 在 Maker 刷新後檢查建置／執行紀錄中的 `CONFIG_ERROR`。發布前也要確認每個非空 RUID 都指向可用且類型相符的資源。

新增列會納入 `BattleSession` 的怪物資料查找與選項資料；固定敵軍名單則由 `BattleSession` 的 ID 設定決定，不會因新增資料列自動改變。
