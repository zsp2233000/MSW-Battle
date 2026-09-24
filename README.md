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
- `StandAnimationRUID`、`MoveAnimationRUID`、`AttackAnimationRUID`、`HitAnimationRUID`、`DieAnimationRUID` 目前都必須非空。填入有效的資源 RUID；載入器只檢查是否空白，不會確認 RUID 是否存在。
- `AttackAnimationRUID` 目前由載入器要求非空，但目前戰鬥呈現程式尚未讀取它；要改成可空或移除欄位時，需一併調整載入器與動畫流程。
- `HitEffectRUID`、`AttackSoundRUID`、`OnHitSoundRUID`、`DieSoundRUID` 可以留空。CSV 中用空欄表示，不必填 `TBD`。這四欄的空值會正規化為空字串。
- `HitEffectRUID` 留空時會沿用該怪物攻擊器的預設特效；若預設值是 `TBD` 或沒有可用特效，就不顯示命中特效。任一音效欄留空時，只略過該音效。
- 非空的 RUID 不會由載入器做存在性檢查。拼錯或已不存在的 RUID 可能通過資料載入，但相應動畫、特效或音效無法正常使用。

## 欄位說明

| 欄位 | 用途與驗證 |
|---|---|
| `MonsterId` | 穩定、唯一的識別鍵；固定敵軍設定會引用它。 |
| `MonsterName` | 顯示名稱；可修改，不影響以 `MonsterId` 查找。 |
| `MonsterType` | `TANK`、`ASSAULT` 或 `SHOOTER`，決定戰鬥行為與攻擊器。 |
| `ModelId` | 生成時使用的專案 Model ID；不可空白。 |
| `MaxHp` | 最大生命值；正整數。 |
| `MoveSpeed` | 移動速度；大於 0。 |
| `AttackDamage` | 攻擊傷害；正整數。坦克接觸傷害也使用此值。 |
| `AttackIntervalSeconds` | 攻擊間隔秒數；大於 0。 |
| `AttackRange` | 一般攻擊距離；大於 0。 |
| `AttackImpactFrame` | 戰士／射手結算命中的影格；正整數。坦克可留空或填 `0`，因坦克沒有一般攻擊。 |
| `RetargetIntervalSeconds` | 重新尋找目標的間隔秒數；大於 0。 |
| `HitStopDurationSeconds` | 受擊停頓秒數；大於或等於 0。 |
| `ContactDamage` | 坦克接觸傷害；整數。坦克必須大於 0，其他種類可填 `0`。 |
| `ContactCooldownSeconds` | 同一目標的接觸傷害冷卻秒數；坦克必須大於 0，其他種類可填 `0`。 |
| `ContactSizeX` | 坦克接觸範圍寬度；坦克必須大於 0，其他種類可填 `0`。 |
| `ContactSizeY` | 坦克接觸範圍高度；坦克必須大於 0，其他種類可填 `0`。 |
| `KnockbackDistance` | 坦克接觸擊退距離；坦克必須大於 0，其他種類可填 `0`。 |
| `StandAnimationRUID` | 待機動畫 RUID；必填，也用於怪物選項肖像。 |
| `MoveAnimationRUID` | 移動動畫 RUID；目前坦克展示會使用。必填。 |
| `AttackAnimationRUID` | 攻擊動畫 RUID；目前載入器要求非空。 |
| `HitAnimationRUID` | 受擊動畫 RUID；目前坦克展示會使用。必填。 |
| `DieAnimationRUID` | 死亡動畫 RUID；目前坦克展示會使用。必填。 |
| `HitEffectRUID` | 命中特效 RUID；可空白，空白時沿用攻擊器預設值。 |
| `AttackSoundRUID` | 攻擊音效 RUID；可空白，空白時不播放攻擊音效。 |
| `OnHitSoundRUID` | 受擊音效 RUID；可空白，空白時不播放受擊音效。 |
| `DieSoundRUID` | 死亡音效 RUID；可空白，空白時不播放死亡音效。 |

## 數值規則摘要

- 所有種類：`MaxHp`、`AttackDamage` 為正整數；`MoveSpeed`、`AttackIntervalSeconds`、`AttackRange`、`RetargetIntervalSeconds` 必須大於 0；`HitStopDurationSeconds` 不可小於 0。
- `TANK`：`ContactDamage`、`ContactCooldownSeconds`、`ContactSizeX`、`ContactSizeY`、`KnockbackDistance` 必須大於 0；`AttackImpactFrame` 可空白或為 `0`。
- `ASSAULT`、`SHOOTER`：`AttackImpactFrame` 必須是正整數；接觸傷害相關數值可填 `0`。

## 新增或修改資料列

1. 在 CSV 中新增或修改一列，保留原有標題與欄位順序。
2. 確認 `MonsterId` 唯一、`MonsterType` 合法、`ModelId` 可生成，且必要數值和動畫 RUID 已填妥。
3. 沒有要使用的命中特效或音效時，將對應的可選 RUID 儲存格留空；不要刪除欄位標題。
4. 將更新後的列同步至 Maker 的 `MonsterData` UserDataSet。只修改 CSV 不會改變執行時已匯入的 UserDataSet。
5. 若新怪物要加入固定敵軍，更新 `BattleSession` 對應的敵軍 ID，並確保 ID 的 `MonsterType` 符合該位置要求。
6. 在 Maker 刷新後檢查建置／執行紀錄中的 `CONFIG_ERROR`。發布前也要確認每個非空 RUID 都指向可用且類型相符的資源。

新增列會納入 `BattleSession` 的怪物資料查找與選項資料；固定敵軍名單則由 `BattleSession` 的 ID 設定決定，不會因新增資料列自動改變。
