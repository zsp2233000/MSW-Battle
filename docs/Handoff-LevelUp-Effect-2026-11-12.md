# 結算怪物卡升級特效交接

日期：2026-11-12（Asia/Taipei）

## 使用者目標與目前狀態

使用者指定 `personalityLevelUP` 系列，要求把含「LEVEL UP」文字的升級特效放在結算畫面的怪物卡。功能已實作，下一輪主要是人工確認呈現、必要時調整位置與節奏，以及補齊素材。

本文件依使用者要求存入專案；此要求優先於 handoff 技能預設的 OS 暫存目錄。推送沿用現有 `docs/monster-level-design` 分支。

## 接手入口

- [專案規則](../AGENTS.md)：遵循 Foundation 載入、UIBuilder 與 Maker MCP 驗證規則。
- [領域用語](../CONTEXT.md)、[養成決策](adr/0005-monster-level-per-player-exp-on-death.md)。
- 基礎結算功能：提交 `8900d61`（#68）；凍結本局等級：提交 `415521b`（#67）。不要重做既有經驗結算或保存流程。
- [BattleUIController.mlua](../RootDesk/MyDesk/Combat/BattleUIController.mlua)：`LevelUpFrames`、`PlayCardLevelUp`、`UpdateCardLevelUps`，以及經驗卡、存活卡建立與清理方法。實際 RUID、影格尺寸、pivot 與播放條件均以程式為準，不在此複製。
- [BattleGroup.ui](../ui/BattleGroup.ui)：透過 UIBuilder 查看 `BattleResultPanel/CardTemplate/LevelUpEffect`。
- [測試說明](../tests/README.md)、[結算卡測試](../tests/battle_result_cards.test.cjs)、[存活卡 fixture](../tests/result_cards_fixture.lua)、[存活卡探針](../tests/result_cards_runtime_probe.lua)。

## 本次觀察與限制

- 確認升級後播放一次，結束後顯示確認的能力變化；未升級、同級、待處理或失敗的結算不播放。清理經驗卡時取消計時器。
- 目前使用已確認的連續影格 3–8；尚未取得其餘影格或完整原生 animationclip。程式已有 `shortcut:` 註記。
- Maker 回報的實際 Sprite 尺寸與搜尋 API 的縮圖尺寸不同；程式已採用 Maker 實測尺寸與 pivot，後續不要直接改回搜尋結果的寬高。
- Maker 的 `Clone` 會啟用原本停用的子物件。因此經驗卡與存活卡複製後都明確隱藏特效，再由升級條件啟動；不能只依賴範本的 `enable=false`。
- 交接前發現目前 HEAD 的 UI 缺少特效節點，已用 UIBuilder 補回；未變更其他卡片版面。
- `MonsterData.csv` 在本輪之前已有使用者修改，本次提交排除該檔案並保留於工作目錄；不要擅自還原或納入後續提交。

## 已取得的驗證證據

本聊天的 Maker 執行記錄包含以下終端 PASS；升級探針是透過 `maker_execute_script` 執行的一次性 client 探針，未保存為專案檔案，不能把派送成功視為測試通過：

- `[VRF][CardLevelUpProbe] RESOURCES_PASS`：六張原生 Sprite、尺寸與 pivot。
- `FRAME_PASS`、`TIMER_PASS`、`PASS`：確認升級條件、六幀順序、原生尺寸、淡出、能力文字恢復、相同 receipt 不重播、關閉時清理、PENDING/FAILED 不播放。
- `[VRF][ResultCardsFixture] PASS`、`[VRF][ResultCardsProbe] PASS result=WIN count=6`、`[VRF][CardLevelUpProbe] SURVIVOR_PASS`：六張存活卡仍正常顯示，特效保持隱藏。
- 該次最終 normal logs 沒有 Error/Warning；build 無 Error，保留既有 `IsPCPlatform` 棄用警告。Maker 已停止 Play。
- 本機相關測試 3/3 通過：`node --test tests/battle_result_cards.test.cjs tests/monster_level_storage_contract.test.cjs`。
- UI 節點補回後另檢查預設隱藏、Sprite 不攔截點擊、CanvasGroup 不攔截點擊；尚未針對補回後的工作樹重跑 Maker。

本輪未人工檢視短暫特效的畫面，未重跑完整配對、多人與發布環境流程。測試使用暫時的 client 結算資料與既有 POC fixture，沒有寫入玩家養成資料。

## 建議接續工作

1. 先確認 git 狀態，保留使用者未提交變更。
2. 用 UIBuilder 查看卡片與特效層，在 Maker 重新 Refresh、檢查 build、Play；重現確認升級的結算，人工確認文字大小、位置、是否遮擋怪物名稱，以及 1.5 秒節奏。
3. 若需要完整系列，從現有 `LevelUpFrames` 的 RUID 追查其餘影格；不得猜測 RUID，也不要把先前找到的純光柱當作文字特效。
4. 若變更程式或版面，依 verify-checklist 再驗證升級與未升級卡、重播防護、關閉清理、存活卡回歸；按實際結果報告限制。

## Suggested skills

- 必載：`msw-general`、`msw-ui-system`，以及 AGENTS.md 指定的 Foundation references。
- 動畫程式與驗證：`msw-scripting`，特別是 `references/verify-checklist.md`。
- 素材查找：`msw-search` 的 resource search/detail references；指派 ImageRUID 時使用 `msw-sprite-ruid`。
- 地圖測試：目前 `template` 與 `matchprobe` 為 RectTile（1）；需要相關工作時讀 `platform-rect.md`。
- 實作風格：`ponytail` full，保持最小完整修改。只有要延續規劃階段時才另載 `msw-planning`。
