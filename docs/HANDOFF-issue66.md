# #66 交接

## 接手位置

本文件依使用者要求存於專案內，覆蓋 handoff skill 預設存 OS 暫存目錄的指引。使用者尚未指定下一個實作任務；先回報現況，依新指示繼續。

- 分支：`docs/monster-level-design`。
- 實作提交：`fbf08f518984bb334ae9b8b06dc0967b963be8ab`，`feat: show personal monster progression in formation editor (#66)`。
- 建立本文件前，`git status --short` 為空。
- 規格：[Issue #66](https://github.com/zsp2233000/MSW-Battle/issues/66)，父議題 [#63](https://github.com/zsp2233000/MSW-Battle/issues/63)。不要將父議題其他票的工作視為已授權。
- 語彙、決策與驗證操作分別參考 `CONTEXT.md`、`docs/adr/0005-monster-level-per-player-exp-on-death.md`、`tests/README.md`；變更內容直接讀提交，不在此重複。

## 已完成與驗證狀態

#66 實作已提交；大廳服務提供個人等級快照，既有卡片文字欄位呈現等級、經驗與換算能力。UI 已在本階段顯示，沒有另行設計新版面。大廳隊伍預覽不顯示等級；戰鬥結果經驗 UI 不是本票範圍。

實作輪 Node 測試 60/60 通過，Maker 的高等級／MAX、新玩家、讀取失敗與重試、損毀資料保留、配對返回重讀均取得 PASS。規格與標準兩軸審查經覆核後無剩餘問題。完整驗證步驟、時間與限制見 `tests/README.md`。兩位審查代理的初稿曾誤判 Lua 短路求值、epoch 防護與經驗分母，已撤回；不要直接沿用初稿結論。

使用者另指定 `gpt-6-luna`、`xhigh` 重跑功能測試並提供截圖。該代理完成單人 Maker 測試、四張真實截圖與繁中報告；未重跑雙人配對返回、Node 全套或實體滑鼠 hover。當時清理成功、原鍵重讀 READY，最後 Maker 停在 `formationlobby` 編輯模式。下一次使用 Maker 仍須重新確認當前狀態。

## 證據檔案目前缺失

上一輪原本產出以下未提交工件，且主代理讀過報告並看過第一張圖：

- `docs/evidence/issue66/report.md`
- `docs/evidence/issue66/01-seeded-editor.png`
- `docs/evidence/issue66/02-seeded-tooltip-max.png`
- `docs/evidence/issue66/03-new-player-lv1.png`
- `docs/evidence/issue66/04-corrupt-load-error.png`

**交接時重新檢查：報告 `Test-Path` 為 False，該目錄沒有列出檔案，`git ls-files` 也沒有這些工件。** 消失原因未確認；不要宣稱上述路徑目前能開啟，也不要擅自還原可能由使用者移除的內容。如下一輪需要交付證據，先確認檔案是否移位；必要時重新測試、截圖與出報告。

原始 Maker 截圖曾留在本機 LocalLow 的 Nexon／MapleStory Worlds `McpScreenshots` 目錄，可在需要恢復證據時查找；仍須核實時間與內容，不能將舊圖當成新測試證據。截圖時間記錄為 2026-11-10 Maker 顯示 15:18:03、15:19:20、15:24:08、15:26:21；時區未獨立核實。

## 畫面觀察與未處理工作

- 報告發現編輯器底部操作提示遭截斷，末尾「移除。」未完整顯示；本輪沒有修 UI。是否修正需依後續使用者指示。
- MAX tooltip 會覆蓋部分下方情報區，但可關閉、不攔截點擊，未列為功能失敗。
- 截圖中卡片等級、經驗、生命與傷害可讀；不能因此推論所有解析度與裝置均通過。
- 未推送提交、未留言或關閉 GitHub Issue；後續寫入遠端需有相應授權。

## 測試存檔的注意事項

實作輪第一次雙人測試太晚設定新戰鬥房間的隔離等級鍵，曾將一場測試經驗寫入本機原鍵。已用該場結算前紀錄與 native CAS 撤回等級／經驗，移除測試對局 ID，讀回確認，並清理隔離鍵。原鍵是否原先存在及 JSON 原始位元組未事前備份，可能留下明確儲存的 Lv1 紀錄；不要宣稱原始檔案位元組完全未變。詳情已有 `tests/README.md`。

單人測試沿用 `tests/editor_levels_fixture.lua` 與現有 editor probes；每輪須確認 CLEANUP PASS、原鍵重讀 READY，再停止 Play。雙人測試必須在每個新 instance 結算前設定編隊與等級兩個隔離鍵；不要在未完成隔離前啟動自然戰鬥。本輪沒有操作正式世界資料。

## Suggested skills

- 所有 MSW 工作：先載入 `msw-general`、`msw-ui-system`，依根目錄 `AGENTS.md` 載入缺失 Foundation references；環境未提供 Skill 工具時，以可用檔案讀取方式載入實際 `SKILL.md`。
- 重跑 probes／修改程式：`msw-scripting` 與 `references/verify-checklist.md`；涉及存檔另讀 `references/datastorage.md`。
- 修提示裁切：`msw-ui-system` 的 component API、layout 與 UI builder protocol。既有 `.ui` 透過 UIBuilder 讀寫。
- 新增程式變更：`ponytail:ponytail` 保持最小完整修改；完整票券實作用使用者提供的 `mattpocock-skills:implement`，完成後用 `mattpocock-skills:code-review`。
- 更新交接或代理文件：`mattpocock-skills:writing-for-agents`；更新此文件可用 `mattpocock-skills:handoff`。

## 工具與協作

遵循根目錄 `AGENTS.md` 與它引用的 RTK 規則。此環境 shell hook 曾將裸 `git`／`rg` 改寫成無法執行的 RTK；PowerShell `& 'git' ...`、`& 'rg' ...` 可正常使用。GitHub 讀取使用 `gh`，受網路沙箱限制時走正式 escalation。

使用者偏好直接完成已授權工作，避免重複確認。`ponytail full` 持續有效；最終回覆簡潔，交代未驗證項目與實際風險。使用者明確要求指定模型時才覆寫子代理模型。
