# M1 Issue #3 — 戰鬥資源填寫表

> 目的：收集「讓坦克加入固定自動戰鬥」所需的人類資產資訊。
> 
> 本表只建立資源契約，不會自動搜尋、生成、上傳或套用資產。`BattleGroup.ui` 保留在專案中，但 Issue #3 不依賴部署 UI。

## 填寫規則

- RUID 請貼 Maker 顯示的完整字串，不要自行加上前綴或改寫格式。
- `ModelId` 不是 RUID；若沿用目前模型，保留 `battleunit` 即可。
- 尚未提供的資源填 `TBD`，明確不需要的資源填 `N/A`。
- 動畫名稱使用固定語意：`stand`、`move`、`attack`、`onhit`、`die`。
- `hit` 表示攻擊命中對方時的特效／音效資源；`hit` 的特效 RUID 由攻擊者提供，但特效播放在被擊中的目標身上；`onhit` 表示單位自己被擊中時播放的動畫／音效。

## Issue #3 必填資源

### 坦克（戰士）

坦克沒有一般攻擊，因此不需要 `attack` 動畫。接觸傷害、冷卻與擊退規則由程式處理。

| 欄位              | 資產類型           | RUID／值                           | 狀態 | 備註                                 |
| ----------------- | ------------------ | ---------------------------------- | ---- | ------------------------------------ |
| Tank ModelId      | Model ID           | `battleunit`                       | ✅    | 若使用其他模型，填入新的 Model ID    |
| Tank `stand`      | AnimationClip RUID | `a95cfed2c8fe4d2cb64cbb62db051f92` | ✅    | 已接入待機                           |
| Tank `move`       | AnimationClip RUID | `8257566e41aa4234929e81c6c2dab2e4` | ✅    | 已接入直線移動                       |
| Tank `onhit`      | AnimationClip RUID | `5ebbdaf503964f3e87de155d16650805` | ✅    | 已接入被擊中與擊退期間呈現           |
| Tank `die`        | AnimationClip RUID | `dddbe2f162184ec89add7440da56eb75` | ✅    | 已接入死亡呈現                       |
| Tank `hit` effect | Effect RUID        | `TBD`                              | ⬜    | 坦克接觸攻擊命中對方時，顯示在被擊中的目標身上 |
| Tank attack SFX   | Sound RUID         | `TBD`                              | ⬜    | 坦克接觸攻擊命中對方時播放           |
| Tank onhit SFX    | Sound RUID         | `6eb2ef8a783c4393bd7ee6a2c199bda7` | ✅    | 已接入坦克被敵方攻擊時播放           |
| Tank die SFX      | Sound RUID         | `c49646f7299e4c6e81e953c96e20b294` | ✅    | 已接入坦克死亡時播放                 |
| Tank `attack`     | AnimationClip RUID | `N/A`                              | ⏸    | Issue #3 要求坦克沒有一般攻擊        |

### 固定敵方突擊單位（戰士）

Issue #3 延續既有一對一自動戰鬥，若敵方突擊仍使用人類動畫，請填入下列資源。

| 欄位                        | 資產類型           | RUID／值                           | 狀態 | 備註                                  |
| --------------------------- | ------------------ | ---------------------------------- | ---- | ------------------------------------- |
| Assault ModelId             | Model ID           | `battleunit`                       | ✅    | 可與坦克共用模型，或填入專用 Model ID |
| Assault `stand`             | AnimationClip RUID | `f87189ab1adb43468d22cc771ccb81d5` | ⬜    | 待機                                  |
| Assault `move`              | AnimationClip RUID | `73ca81cca01e4a5dbb143d742995c0f8` | ⬜    | 直線移動                              |
| Assault `attack`            | AnimationClip RUID | `a3058290424040bf9736df9fa71ad35c` | ⬜    | 一般攻擊                              |
| Assault `onhit`             | AnimationClip RUID | `9a8d4f661f3944a4a8d2b97eaa6c4191` | ⬜    | 被擊中                                |
| Assault `die`               | AnimationClip RUID | `18a17c37dd4f4b11b5a41452d4d5e7ef` | ⬜    | 死亡                                  |
| Assault `hit` effect        | Effect RUID        | `a848d7b003434dd09cb6eb9d91c54fce` | ⬜    | 攻擊命中對方時，顯示在被擊中的目標身上 |
| Assault attack impact frame | Frame／秒數        | `3`                                | ⬜    | 攻擊動畫中實際造成命中的時間點        |
| Assault attack SFX          | Sound RUID         | `3d5f172ea5cf43c4ab3ad6228b7666cd` | ⬜    | 戰士攻擊時播放                        |
| Assault onhit SFX           | Sound RUID         | `2b511b5a593949748ccff01e35db54c5` | ✅    | 已接入坦克被敵方攻擊時播放            |
| Assault die SFX             | Sound RUID         | `c11a5fe2a6d64731885daee991380e51` | ⬜    | 戰士死亡時播放                        |


## Issue #4 必填資源

### 射手

射手使用直線移動與 hitscan 攻擊，不建立投射物 Entity。請填入戰士與射手實際使用的動畫資源 RUID；若沿用同一組資源可重複填寫相同 RUID。

| 欄位                        | 資產類型           | RUID／值     | 狀態 | 備註                                          |
| --------------------------- | ------------------ | ------------ | ---- | --------------------------------------------- |
| Shooter ModelId             | Model ID           | `battleunit` | ✅    | 可與坦克（戰士）共用模型，或填入專用 Model ID |
| Shooter `stand`             | AnimationClip RUID | `8c2ec5bf58894061a19479ed7545637b`        | ⬜    | 待機                                          |
| Shooter `move`              | AnimationClip RUID | `5004df97436a49458160b2c48e9f3748`        | ⬜    | 直線移動                                      |
| Shooter `attack`            | AnimationClip RUID | `db9d6c0a6d0b42b6a4032d0cc46a2526`        | ⬜    | 遠距攻擊                                      |
| Shooter `onhit`             | AnimationClip RUID | `8fed6100596948f5aa8075509117a58f`        | ⬜    | 被擊中                                        |
| Shooter `die`               | AnimationClip RUID | `38832c224bdd4fdb8419a011dbc47b67`        | ⬜    | 死亡                                          |
| Shooter `hit` effect        | Effect RUID        | `1f2bdb3b15a145ea8f3db3fbfb61296b`        | ⬜    | hitscan 命中對方時，顯示在被擊中的目標身上      |
| Shooter attack impact frame | Frame／秒數        | `9`        | ⬜    | 攻擊動畫中實際觸發 hitscan 命中的時間點       |
| Shooter attack SFX          | Sound RUID         | `ef19be8747764615ba48d1f0c8dc6f5d`        | ⬜    | 射手開始攻擊時播放                            |
| Shooter onhit SFX           | Sound RUID         | `c29a8a3c724d45b8b5fe7a51a7877e24`        | ⬜    | 射手被擊中時播放                              |
| Shooter die SFX             | Sound RUID         | `0348f6fd3f194e3b975e8aa9bcab112f`        | ⬜    | 射手死亡時播放                                |

## Issue #3 行為設定確認

這些不是 RUID，但會作為實作與驗收的固定輸入。

| 設定                             |     值 | 備註                                                                |
| -------------------------------- | -----: | ------------------------------------------------------------------- |
| Tank HP                          |  `500` | 集中設定                                                            |
| Tank move speed                  |  `1.1` | RectTile 世界速度                                                   |
| Tank contact damage              |   `40` | 標準 Attack→Hit 流程                                                |
| Tank per-target contact cooldown | `2.0s` | 每個重疊敵人獨立計時                                                |
| Enemy knockback distance         |  `0.8` | 只擊退敵方，坦克不後退                                              |
| OnHit stop duration              | `0.2s` | 受擊單位在 ON_HIT→HP 結算後原地停止；死亡與 RESULT 優先             |
| Tank normal attack               |  `N/A` | 不進入或發出一般 attack 行為                                        |
| Tank contact attack hit VFX/SFX  |  `TBD` | 對方被坦克接觸攻擊命中時的特效／音效；與坦克自身 onhit 資源分開填寫 |

## 暫不屬於 Issue #3

下列資源先保留欄位，等後續呈現階段再填，不阻塞本票：

| 資源                     | 資產類型        | RUID／值 | 狀態 | 備註                                   |
| ------------------------ | --------------- | -------- | ---- | -------------------------------------- |
| HP bar background        | Sprite RUID     | `TBD`    | ⏸    | 後續世界 HP 條                         |
| HP bar fill              | Sprite RUID     | `TBD`    | ⏸    | 後續世界 HP 條                         |
| DamageSkin               | DamageSkin RUID | `TBD`    | ⏸    | Issue #3 只要求傷害數字語意事件        |
| Shared attack-hit effect | Effect RUID     | `TBD`    | ⏸    | 可作為各兵種 `hit` 特效的共用 fallback |
| Assault attack sound     | Sound RUID      | `TBD`    | ⏸    | 後續視聽呈現階段                       |
| Shared death sound       | Sound RUID      | `TBD`    | ⏸    | 後續視聽呈現階段                       |
