# M1 Issue #3 — 戰鬥資源填寫表

> 目的：收集「讓坦克加入固定自動戰鬥」所需的人類資產資訊。
> 
> 本表只建立資源契約，不會自動搜尋、生成、上傳或套用資產。`BattleGroup.ui` 保留在專案中，但 Issue #3 不依賴部署 UI。

## 填寫規則

- RUID 請貼 Maker 顯示的完整字串，不要自行加上前綴或改寫格式。
- `ModelId` 不是 RUID；若沿用目前模型，保留 `battleunit` 即可。
- 尚未提供的資源填 `TBD`，明確不需要的資源填 `N/A`。
- 動畫名稱使用固定語意：`stand`、`move`、`hit`、`die`、`attack`。

## Issue #3 必填資源

### 坦克

坦克沒有一般攻擊，因此不需要 `attack` 動畫。接觸傷害、冷卻與擊退規則由程式處理。

| 欄位          | 資產類型           | RUID／值                           | 狀態 | 備註                              |
| ------------- | ------------------ | ---------------------------------- | ---- | --------------------------------- |
| Tank ModelId  | Model ID           | `battleunit`                       | ✅    | 若使用其他模型，填入新的 Model ID |
| Tank `stand`  | AnimationClip RUID | `a95cfed2c8fe4d2cb64cbb62db051f92` | ✅    | 已接入待機                          |
| Tank `move`   | AnimationClip RUID | `8257566e41aa4234929e81c6c2dab2e4` | ✅    | 已接入直線移動                      |
| Tank `hit`    | AnimationClip RUID | `5ebbdaf503964f3e87de155d16650805` | ✅    | 已接入受擊與擊退期間呈現            |
| Tank `die`    | AnimationClip RUID | `dddbe2f162184ec89add7440da56eb75` | ✅    | 已接入死亡呈現                      |
| Tank hit SFX  | Sound RUID         | `6eb2ef8a783c4393bd7ee6a2c199bda7` | ✅    | 已接入坦克受到敵方攻擊時播放        |
| Tank die SFX  | Sound RUID         | `c49646f7299e4c6e81e953c96e20b294` | ✅    | 已接入坦克死亡時播放                |
| Tank `attack` | AnimationClip RUID | `N/A`                              | ⏸    | Issue #3 要求坦克沒有一般攻擊     |

### 固定敵方突擊單位

Issue #3 延續既有一對一自動戰鬥，若敵方突擊仍使用人類動畫，請填入下列資源。

| 欄位                        | 資產類型           | RUID／值     | 狀態 | 備註                                  |
| --------------------------- | ------------------ | ------------ | ---- | ------------------------------------- |
| Assault ModelId             | Model ID           | `battleunit` | ✅    | 可與坦克共用模型，或填入專用 Model ID |
| Assault `stand`             | AnimationClip RUID | `TBD`        | ⬜    | 待機                                  |
| Assault `move`              | AnimationClip RUID | `TBD`        | ⬜    | 直線移動                              |
| Assault `attack`            | AnimationClip RUID | `TBD`        | ⬜    | 一般攻擊                              |
| Assault `hit`               | AnimationClip RUID | `TBD`        | ⬜    | 受擊                                  |
| Assault `die`               | AnimationClip RUID | `TBD`        | ⬜    | 死亡                                  |
| Assault attack impact frame | Frame／秒數        | `TBD`        | ⬜    | 攻擊動畫中實際造成命中的時間點        |

## Issue #3 行為設定確認

這些不是 RUID，但會作為實作與驗收的固定輸入。

| 設定                             |     值 | 備註                                                                                                         |
| -------------------------------- | -----: | ------------------------------------------------------------------------------------------------------------ |
| Tank HP                          |  `500` | 集中設定                                                                                                     |
| Tank move speed                  |  `1.1` | RectTile 世界速度                                                                                            |
| Tank contact damage              |   `40` | 標準 Hit 流程                                                                                                |
| Tank per-target contact cooldown | `2.0s` | 每個重疊敵人獨立計時                                                                                         |
| Enemy knockback distance         |  `0.8` | 只擊退敵方，坦克不後退                                                                                       |
| Tank normal attack               |  `N/A` | 不進入或發出一般 attack 行為                                                                                 |
| Tank contact attack VFX/SFX      |  `N/A` | 坦克主動接觸攻擊不播放碰撞特效、攻擊音效、碰撞音效或該次接觸引發的受擊音效；坦克被攻擊與死亡仍播放各自的 SFX |

## 暫不屬於 Issue #3

下列資源先保留欄位，等後續呈現階段再填，不阻塞本票：

| 資源                 | 資產類型        | RUID／值 | 狀態 | 備註                            |
| -------------------- | --------------- | -------- | ---- | ------------------------------- |
| HP bar background    | Sprite RUID     | `TBD`    | ⏸    | 後續世界 HP 條                  |
| HP bar fill          | Sprite RUID     | `TBD`    | ⏸    | 後續世界 HP 條                  |
| DamageSkin           | DamageSkin RUID | `TBD`    | ⏸    | Issue #3 只要求傷害數字語意事件 |
| Shared hit effect    | Effect RUID     | `TBD`    | ⏸    | 坦克接觸不播放                  |
| Assault attack sound | Sound RUID      | `TBD`    | ⏸    | 後續視聽呈現階段                |
| Shared death sound   | Sound RUID      | `TBD`    | ⏸    | 後續視聽呈現階段                |
