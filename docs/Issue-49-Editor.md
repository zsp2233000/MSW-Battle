# #49 戰術沙盤整備

沿用 [#44](https://github.com/zsp2233000/MSW-Battle/issues/44) 的 B 方案與 Cardgame 素材。真正的 formationsim 戰場與連續座標布陣保留；依使用者後續回饋，所有常駐整備控制集中在右側，左半場留給部署。半透明棕色面板與空心邊框保留地圖可見性；技術 ID、座標及六人名單放入可開關的詳情。

MonsterCatalog 從已驗證的伺服器 profile 發送種類、生命值、傷害、攻擊間隔與距離。既有 options 的 ID／名稱／圖像仍在原本前三個位置，追加的情報只供顯示，沒有進入草稿命令或取代服務驗證。選取始終使用 MonsterId；選中場上單位時，情報跟隨該單位。

保留既有 UI UUID、正式事件、保存格式及地圖。右側列表採兩欄與原生垂直捲動，卡片間隙也有透明接收表面。面板填色在 runtime 明確排到既有控制項後方，避免 Maker 保留舊匯入順序後遮住文字與按鈕。讀取失敗時重試顯示在右側停用的卡片區；未確認及保存待處理期間停用相關操作。失敗後沿用既有重讀確認流程，保留草稿及已確認資料。

## 左半場視野修訂

1920×1080 參考畫布中，整備控制從 x=1040 開始，左半場 x<960 沒有本專案整備面板覆蓋。上方是返回、收合、詳情與五組選擇；中段是兩欄怪物卡片及情報；下方是保存、設為出戰、繼續部署、移除與配對。草稿數、目前移動／放置提示及狀態訊息也在右側。詳情開啟後覆蓋右側卡片區，維持左半場可見。

同日修訂後複測：`EditorIntel` 包含各整備區塊留在右半場及螢幕內的 runtime 檢查；`EditorNativeInput`、`EditorFailure`、18 筆正式目錄與原生滾輪皆 PASS。本機契約 32/32 通過，strict lint 無 Error／Warning，build 保留相同兩項既有 Warning。原生畫面確認三種卡片、完整情報、移動提示、配對文字及左半場清楚可見。

## 驗證紀錄

2026-10-30，原生 Maker，1920×1080 參考畫布。Refresh 後讀 build，再 Play；下列 runtime 結論均有最終 PASS，派送成功不算測試通過。

| 檢查 | 證據 |
|---|---|
| 本機契約 | `node --test tests/*.test.cjs`：32/32 通過 |
| UIBuilder strict lint | 108 entities，0 Error、0 Warning |
| Maker build | 0 Error；保留原有 IsPCPlatform 舊 API、BattleViewAvatar 動作選擇器兩項 Warning |
| 正式卡片與情報 | `editor_intel_runtime_probe.lua`：逐張卡片選取、正式五項情報、場上選取、詳情開關、移除狀態與實際背景排序 PASS |
| 編輯完整流程 | `editor_flow_runtime_probe.lua`：重複兵種、分數座標移動、移除、六人上限、邊界、0.3 間距、保存、明確設為出戰、乾淨返回與未保存返回選擇 PASS |
| 原生戰場輸入 | `editor_native_input_runtime_probe.lua`：實際 mouse_input 在 `(640,540)` 放置，與 ScreenToWorldPosition 結果相符，保存內容不變，最後恢復草稿與組別，PASS |
| 讀寫失敗 | `editor_failure_runtime_probe.lua`：讀取失敗、重試可達、待處理停用、阻止離開、寫入失敗保留草稿與已保存內容、重讀後可再保存，PASS |
| 正式目錄溢出 | 18 筆暫時 CSV，原 Tank 改名及同種類不同 ID／數值；`editor_catalog_runtime_probe.lua` PASS，最後一張選取與情報正確 |
| 原生滾輪 | 右側間隙 `(1208,570)` 向下、卡面 `(1120,570)` 向上，各 40 次 delta ±1、間隔 250ms；到達底端及回到頂端，PASS |
| POC 相容 | `formation_poc_regression_runtime_probe.lua`、`deployment_ui_runtime_probe.lua` PASS；後者改檢查 EnabledInHierarchy，符合既有父容器隱藏方式 |
| 審查 | Standards／Spec 兩軸審查及修訂後複查，無剩餘阻擋項目 |

原生畫面已確認標題、卡片、種類、情報與右側操作可讀，填色不再蓋住內容。這不代表所有按鈕視覺狀態均已驗收。

## 重現與清理

一般 client probes 從 formationlobby 啟動。原生輸入 probe 依其 READY 訊息立即派送 mouse_input，再讀取最終結果。完整流程 probe 要先在 server_main 將 `_FormationService.StorageKey` 設為唯一的新測試鍵；它會保存及設為出戰，不能用原有存檔測試。Stop/Play 恢復預設鍵。

失敗 probe 先進入整備，再於 server_main 呼叫 `_FormationStorage:ConfigureMakerFaults(1, 1, 1)`，接著執行 client 檔案。唯一保存請求在儲存邊界注入失敗，沒有改寫原有存檔；結束後重設 `(0, 0, 0)` 並 Stop。草稿及所選組別由 probe 還原，Stop/Play 重設登入內版本。

目錄測試用 `node tests/editor_catalog_fixture_driver.cjs` 的 guarded transaction。逐一完成 JSON 請求指定的真實 Maker 操作後，以對應 id 回覆。`editor-catalog-probe` 階段執行 client probe；看到 WHEEL_READY 後立即開始上述滾輪序列，三十秒內須到達底端。另在底端觀察原生向上捲動至頂端。只有最終 PASS 才可確認該階段。還原階段在 fresh Play 執行 `monster_catalog_restored_runtime_probe.lua`，讀到 PASS 再回覆。取消或失敗也須讓 guard 完成 Stop、原始位元組還原、Refresh 與正式目錄驗證。

本輪 guard 完整 PASS，正式目錄恢復三筆，原始 CSV 1458 bytes、SHA-256 `45e1358c0596fb4008b2830f93d79c2ec677d0df4263db87b51fbed55a3e15a5`。原有編隊存檔未被覆寫，沒有重設 Maker DataStorage；隔離測試鍵可能留在本機。Maker 已停止。

## 人工驗收邊界

mouse_input 工具明示不會點擊引擎管理的 UI；正式按鈕用已綁定的 SendEvent 驗證，不能稱作真實滑鼠點擊。額外面板點擊 probe 的 IsPointerOverUI 回傳 false，未能證明真實滑鼠的 UI 阻擋；保留人工檢查，不能以模擬器結果宣稱通過。面板接收表面及裝飾不接收點擊的設定已檢查。

請用實際 PC 滑鼠確認面板點擊不會穿透布陣、四種按鈕視覺狀態、詳情彈出後的閱讀感，以及較小 PC 視窗。沒有可直接切換 PC 解析度的 Maker MCP 工具；未驗證手機。本票保留開啟等待使用者驗收，#50–#52 的後續改版未納入。
