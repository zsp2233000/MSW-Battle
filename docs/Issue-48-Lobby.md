# #48 Cardgame 大廳

本票沿用 [#44](https://github.com/zsp2233000/MSW-Battle/issues/44) 選定的 B「戰術沙盤」。正式大廳使用 Cardgame 按鈕的 SpriteSwap 狀態、Base_4 空心邊框與木紋；透明度只作用在背景，裝飾不接收點擊。原有玩家身分、五組選取、整備入口及 POC 入口保留。

預覽只取伺服器快照的已保存出戰組。選組、編輯出戰組草稿或其他組草稿都不會取代預覽；預覽以同一比例呈現相對站位。開始配對仍由 MatchProbeInput 的原有按鈕及請求處理，無有效出戰編隊時改為前往模擬地圖。載入失敗提供重試；資料未確認或保存待處理期間停用主要操作。已開始配對仍可取消。保存格式與服務權威不變。

## Maker 驗證

預覽使用 B 原型的直接圖像站位，不使用連線或獨立名單。依已保存編隊的範圍等比例縮放與置中，保持相對方向及距離比例；依最近單位的間距調整圖像尺寸。預覽只顯示短序號，避免完整名稱遮擋站位，名稱仍可於整備查看。

## 白底與密集預覽修正

Maker 在單位容器仍繼承 UISprite 模型時，會補回已從 UI 檔移除的預設不透明 renderer，形成白色矩形。先在 runtime 只將容器 alpha 改為 0，保留原縮圖，原生截圖即確認白底消失；正式修正透過 UIBuilder 明確輸出透明、不接收點擊的容器 renderer，不再依賴移除元件。

固定 20px／世界單位會讓緊密編隊擠在中央。現在利用既有預覽區自動取景，圖像上限為 56px，按最近單位的兩軸間距縮小以避免矩形相交；不移動單個怪物來避讓，保留真實相對站位。預覽下方標示「自動縮放」。

`lobby_preview_fit_runtime_probe.lua` 在使用者原有六人出戰編隊上，修改前量得 6 個不透明底圖、11 對圖像相交，修改後皆為 0，並通過區域邊界、站位方向與距離比例檢查。使用者已明確授權本次 Maker 截圖；1920×1080 參考尺寸的原生畫面確認白底消失、六隻怪物分開且序號清晰。未改寫出戰編隊或保存資料。

## 新增操作規格

- 大廳組別按鈕單擊選組；同一按鈕在 0.35 秒內的第二次點擊開啟該組整備。不同組的連續點擊及較慢的兩次單擊均只選組。
- 雙擊及「編隊整備」都等待伺服器回覆選組後才進入模擬地圖，不保存、不更換出戰組。讀取失敗或保存待處理期間仍停用。
- 離開大廳或五秒內未取得可用的選組確認時，取消本次進場意圖；玩家可再次點擊整備，不讓後來的快照觸發殘留進場。
- 「編隊整備」移至五組按鈕正下方中央；左側提供「單擊選組 · 雙擊整備」提示，POC 及狀態訊息保留在同區但不重疊。保留單擊整備入口，讓玩家不必依賴雙擊。

新增規格已同步至 GitHub #44 與 #48。本次 Maker 回歸取得 LobbyEditShortcuts、LobbyPreview、MatchedLobbyUI、LobbyDraft、LobbyPending、LobbyLoadFailure 六項 PASS；後兩項也檢查失敗／待處理時雙擊不得選組或進場。測試只修改登入內草稿，唯一保存請求在儲存邊界注入失敗，未改寫已保存編隊；故障設定已復原。

## 初版驗證與本次回歸

2026-10-29，原生 Maker，formationlobby，1920×1080。先 Refresh，確認 build 無 Error，再 Play；以下 probes 均在 client 執行。必須讀取最終 PASS，不能以派送成功代替結果。

- `lobby_preview_runtime_probe.lua`：出戰預覽的相對方向與比例、圖像直接佔位且無連線、五組正式選取、整備及 POC 往返。首次在修改前取得預期 FAIL，實作後 PASS。
- `lobby_edit_shortcuts_runtime_probe.lua`：單擊停留、同組雙擊進場、不同組快速點擊、慢速重複點擊、選組後立即點整備，以及出戰選擇不變；不寫入存檔。
- `lobby_draft_runtime_probe.lua`：使用有效出戰編隊，編輯其他組及清空出戰組草稿，確認已保存站位與出戰選擇不變，最後恢復草稿內容。Stop/Play 重設測試造成的草稿版本。
- `matched_battle_lobby_ui_runtime_probe.lua`：正式配對、等待時間及取消。返回地圖後先等按鈕實際可操作再派送事件。
- `lobby_load_failure_runtime_probe.lua`：先在 server_main 呼叫 `_FormationStorage:ConfigureMakerFaults(1, 0, 0)`；驗證失敗提示、停用、已保存內容及草稿保留，以及正式重試按鈕復原。最後設定 `(0, 0, 0)`。
- `lobby_pending_runtime_probe.lua`：在 draft probe 後，以 server_main 設定 `_FormationStorage:ConfigureMakerFaults(0, 1, 1)`，驗證待處理按鈕、原因及失敗保留資料。唯一寫入請求在儲存邊界被拒絕，不會寫入原有存檔。結束後重設故障並從 Retry 重讀。
- `lobby_empty_runtime_probe.lua`：server_main 暫時將 FormationService.StorageKey 設為新的唯一測試鍵，再執行 client probe。只讀取不存在的鍵，不寫入；驗證 NEW、空預覽、主按鈕前往整備及往返後仍未配對。最後恢復 `BattleFormationsV2`、重讀並 Stop/Play。

本輪不重設 Maker DataStorage，不改寫原有編隊存檔。故障與臨時讀取鍵都已復原。

初版六項 runtime probes 均取得最終 PASS；完整本機契約測試 32/32 通過。build 無 Error，保留原有兩項 Warning（IsPCPlatform 舊 API、BattleViewAvatar 動作選擇器）。本次 UIBuilder strict lint 無 Error／Warning；原先偏左清單及其 L016 已移除。

初版已執行 Standards／Spec 雙軸檢視。使用者之後明確要求恢復直接圖像站位，因此移除初版為了名稱避讓自行加入的連線清單；保留地圖切換、待處理與無效編隊的操作保護。

## 驗收邊界

Maker 事件 probes 驗證的是正式已綁定事件及服務結果。mouse_input 工具明示不能點擊引擎管理的 UI，因此不將 SendEvent 說成真實滑鼠測試。

本次已對上述六人編隊做原生截圖驗證；四種按鈕視覺狀態、較小 PC 視窗及其他頁面仍需目視驗收，沒有可直接切換 PC 解析度的 MCP 工具。UIBuilder lint 與 runtime 屬性檢查不取代這些項目。票保持開啟，直到其餘目視驗收完成。整備版面及完整配對、戰鬥、結果改版分屬 #49–#52。
