# 編輯器養成 UI 交接

## 接手位置

使用者要求刪除舊交接、建立新交接並隨程式一併提交推送，因此本文件存於專案內，覆蓋 handoff 技能預設存 OS 暫存目錄的指引。尚未指定下一項實作；先依使用者的新指示繼續，不自動展開其他議題。

- 分支：`docs/monster-level-design`；遠端：`origin`。
- 本輪提交主旨：`fix: unify editor progression visuals and prevent clipping`。變更細節讀該提交的 diff。
- 既有 #66 實作：`fbf08f518984bb334ae9b8b06dc0967b963be8ab`。
- 規格：[Issue #66](https://github.com/zsp2233000/MSW-Battle/issues/66)。語彙及養成規則參考 `CONTEXT.md`、`docs/adr/0005-monster-level-per-player-exp-on-death.md`；既有驗證操作及存檔歷史限制參考 `tests/README.md`。

## 使用者確認的範圍

等級改用 `skill/40001.img/skill/400011011` 的數字圖片，經驗值改成 Card Package 底框搭配青綠色進度條。使用者明確限定「只改編輯器內的 UI」：卡片、tooltip、下方情報區均已套用；戰鬥頭上名稱標籤維持原樣。詳細資訊保留精確經驗數字與 MAX。

程式入口為 `RootDesk/MyDesk/Formations/FormationCatalogCards.mlua`；樣板在 `ui/FormationGroup.ui`。沒有修改養成計算或存檔流程。

## 這輪診斷留下的注意事項

- 技能數字的原生 pivot 位於圖片外，`PreserveSpriteType.AspectOnly` 會讓圖片偏出圖框。使用 None，依 Maker 原生 Sprite 的實際寬高設定圖框；搜尋 API 的尺寸與原生修邊尺寸不同，不可直接當成相同比例。
- 原本的框線／比例斷言沒有發現實際繪製問題。新增 stretch 子節點可能保留預設尺寸；本次進度條改為明確尺寸，並在卡片寬度改變時重算。後續要檢查 Track/Fill 是否真正位於條框內，不能只驗證比例。
- 種類文字的實際需求高度約 23.7 UI 像素，20 像素會被截掉；已恢復足夠高度，經驗數字也確認實際文字高度。
- 曾把大方塊誤判成填色素材載入問題，後來以實際尺寸重現並修正。不要沿用此誤判；最終 Play 的 runtime/build 均無 Error。
- UIBuilder 重新序列化會將大量 `1.0` 等數字寫成 `1`，因此文字 diff 很大。透過 builder 比較確認，原有實體僅修改卡片的 Identity、MonsterName、PortraitViewport；其餘是新增養成顯示節點。

## 最終驗證與現況

- `node --test "tests/*.test.cjs"`：60/60 通過；這是既有測試，沒有新增測試檔。
- Maker 客戶端 probe 通過三處 UI 的 1～30 級素材、原生比例、空條／60%／MAX、三種卡片尺寸（149×216、181×263、213×309）、子節點邊界、文字高度、hover／選取、讀取中／失敗隱藏。另有實際截圖複查。
- 最後證據：`[VRF][EditorProgress] PASS native art=1..30 all=card/intel/tooltip zero/60%/MAX bounds/resize/hover/click/unavailable`，以及 `CLEANUP PASS client display restored; no storage writes`。最終 runtime/build 無 Error；build 有一項既有 IsPCPlatform deprecated warning。
- 本輪 probe 只替換客戶端顯示資料，已還原；沒有寫入存檔。probe 是透過 Maker 執行的臨時程式，未保存為 repo 測試，下一代理須重新建立相應斷言；可參考既有 `tests/editor_card_resize_runtime_probe.lua` 的操作入口，但不可把它當作已涵蓋本輪所有新增檢查。
- 最後 Maker 停在 `formationsim` 編輯模式；下次操作前重新確認世界、地圖及模式。
- 未測手機、未驗證實體滑鼠 hover、未重跑雙人配對返回與存檔錯誤注入。未留言或關閉 GitHub Issue。

## 截圖與既有遺留事項

最新確認存在並看過的畫面：`%USERPROFILE%/AppData/LocalLow/nexon/MapleStory Worlds/McpScreenshots/maker_play_20261110_235258_399.png`。圖中卡片等級 5／30／1 與 60%／滿條／空條是客戶端顯示測試資料，已清理；截圖未納入 Git。此檔名是 Maker 的時間記錄，不另作時區推論。

舊交接記錄的 `docs/evidence/issue66/` 報告與四張截圖當時缺失；本輪沒有恢復或追查，不能宣稱可開啟。底部操作提示截斷、tooltip 可能覆蓋情報區是既有觀察，本輪未修。

後續若重跑存檔或雙人測試，先讀 `tests/README.md` 的隔離鍵與清理規則。早期測試曾碰到本機原鍵，雖已撤回測試經驗，不能宣稱其原始位元組完全未變；本輪沒有操作正式世界資料。

## Suggested skills

- 基礎：`msw-general`、`msw-ui-system`，及 `AGENTS.md` 指定的 Foundation references；依環境技能機制載入缺失內容。
- UI 修改：`msw-ui-kit`、`msw-sprite-ruid`，UIBuilder core/UI protocol、component API、runtime patterns；既有 `.ui` 一律透過 UIBuilder 讀寫。
- 腳本／驗證：`msw-scripting` 及 `references/verify-checklist.md`；若涉及存檔，再載入 `references/datastorage.md`。
- 資源查詢：`msw-search`；不得直接呼叫被專案禁止的資源搜尋工具。
- 診斷：`diagnosing-bugs`。程式修改：`ponytail:ponytail`，維持 full 模式與最小完整變更。
- 更新交接：`handoff`；使用者要求提交文件時，沿用本次專案內存放方式。

使用者偏好直接完成已授權工作，避免重複確認。GitHub 議題操作使用 `gh`；PowerShell 中 `& 'git' ...` 可避開先前遇到的 RTK 改寫問題。
