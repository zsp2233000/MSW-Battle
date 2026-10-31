# #49 戰術沙盤整備

沿用 [#44](https://github.com/zsp2233000/MSW-Battle/issues/44) 的 B 方案與 Cardgame 素材。真正的 formationsim 戰場與連續座標布陣保留；依使用者最新回饋，右側只保留編隊組別、怪物卡片及能力情報，其他操作分布在頂端與左下方，讓左側中央部署區保持清楚。半透明棕色面板與空心邊框保留地圖可見性；技術 ID、座標及六人名單放入可開關的詳情。

MonsterCatalog 從已驗證的伺服器 profile 發送種類、生命值、傷害、攻擊間隔與距離。既有 options 的 ID／名稱／圖像仍在原本前三個位置，追加的情報只供顯示，沒有進入草稿命令或取代服務驗證。選取始終使用 MonsterId；選中場上單位時，情報跟隨該單位。

保留其餘既有 UI UUID、正式事件、保存格式及地圖，移除「繼續部署」與「移除單位」按鈕及其綁定。點選怪物卡片即可回到部署；右鍵先取消已選單位，沒有選取單位時可對場上單位右鍵移除。右側列表採三欄與原生垂直捲動，卡片間隙也有透明接收表面。面板填色在 runtime 明確排到既有控制項後方，避免 Maker 保留舊匯入順序後遮住文字與按鈕。讀取失敗時重試顯示在右側停用的卡片區；未確認及保存待處理期間停用相關操作。失敗後沿用既有重讀確認流程，保留草稿及已確認資料。

## 版面與卡片比例修訂

1920×1080 參考畫布中，右側區塊從 x=1040 開始、寬 832，右邊留 48、底部留 24。組別在 y=136；卡片面板在 y=256、高 480，實際捲動視窗為 784×412；能力情報在 y=752、高 304，延伸到 y=1056。三個區塊依序填滿右側可用高度。

卡片外框原素材 Border_2 為 142×206，原先被壓成 144×138，造成扁平。改為 213×309。CardSign 依套件原卡片的相對尺寸放大至 226.5×318，略超出底框；名稱置於 y=-84。選取時直接切換底框為套件 Border_2_Gold，並顯示勾選，移除覆蓋在裝飾與內容上方的第二張完整卡框及名稱臨時提層。底框、裝飾、圖像與文字維持固定層級，原生 ColorTint 按鈕狀態保留。每列三張卡片，正式三種怪物可在同一列看到；更多怪物用原生垂直捲動顯示。

標題與草稿摘要移到頂端；操作提示、橫向配對面板，以及保存、設為出戰、返回、詳情與收合五個按鈕放在左下方。狀態文字位於最下緣。詳情由使用者主動開啟，顯示在左側，關閉後恢復中央地圖視野。

同日修訂後複測：`EditorIntel` 包含右側三個區塊及選取提示的螢幕邊界檢查，以及已移除按鈕不存在的檢查；`EditorNativeInput`、`EditorFlow`、`EditorFailure`、18 筆正式目錄與原生滾輪皆 PASS。本機契約 32/32 通過，strict lint 無 Error／Warning，build 保留相同兩項既有 Warning。原生畫面確認直式卡框、完整情報、操作提示、配對文字及中央部署區清楚可見。

同日卡片層級修訂另行驗證：本機契約 32/32、105 entities strict lint 無 Error／Warning，Maker build 0 Error、同兩項既有 Warning。`EditorIntel` 新增逐張切換時的金色／一般底框、唯一勾選、裝飾超出底框及重複卡框不存在檢查，PASS；`CardLayers` runtime 檢查裝飾在名稱後、勾選在圖像前及原生 ColorTint 保留，PASS。兩次原生截圖確認 Shooter 與 Tank 切換後的框色、名稱及圖像清楚，最後 Stop 返回編輯模式。此輪只重跑卡片與情報檢查，完整保存流程、失敗注入、18 筆目錄及實體滑鼠各狀態未重跑；此前紀錄保留如下。

## Maker 編輯方式修訂

整備與卡片模板預設在編輯模式啟用，大廳預設隱藏。Maker 開啟 `FormationGroup` 的 UI 編輯畫面後，可直接調整 `Editor` 與 `Editor/Catalog/Template`，不用先解除父節點的停用狀態。Play 時 `FormationLobby.OnBeginPlay` 自動隱藏預覽；正式怪物卡片仍從模板複製，再填入伺服器目錄的名稱、圖片與種類。結束 Play 會恢復檔案中的編輯預設。

固定版面由 `.ui` 管理；程式負責資料、選取、事件與顯示切換。原本共用且由程式搬動的狀態、重試與收合按鈕，改為各畫面各自的控制項。收合按鈕位於獨立的 `EditorControls`，收起 `Editor` 後仍能操作。配對面板也分為同一 `MatchGroup.ui` 內的三個容器，各自保存版面；切換畫面時解除前一顆按鈕的事件，再綁定目前的按鈕。既有 Cardgame 圖像、按鈕狀態、正式編隊權限與保存流程沿用。

| 要調整的內容 | Maker 路徑與屬性 |
|---|---|
| 單張卡片尺寸及內容跟隨 | `FormationGroup/Editor/Catalog` → `ScrollLayoutGroupComponent.CellSize`，目前採用 `149×216`。原生伸縮錨點讓外框、圖片區域與文字寬度跟隨尺寸，模板根節點由網格管理，不能直接改其 Width／Height |
| 卡片間隔與欄數 | 同一 `Catalog` → `ScrollLayoutGroupComponent.GridSpacing`、`ConstraintCount`；卡片區域尺寸另由 Catalog 的 UITransform 管理 |
| 名稱文字與排列 | `FormationGroup/Editor/Catalog/Template/MonsterName` → `TextGUIRendererComponent` 字型、對齊、`FontSize`，以及 `UITransformComponent` 尺寸、位置；啟用 `BestFit` 時也需調整 `MinSize`／`MaxSize` |
| 種類、圖像與裝飾 | 同一模板下的 `Identity`、`PortraitViewport/Portrait`、`CardSign`；修改尺寸時同步留意子項位置與原素材比例 |
| 整備狀態、重試及收合位置 | `FormationGroup/EditorControls/Status`、`Retry`、`Toggle` |
| 各畫面的配對版面 | `MatchGroup/Match`（大廳）、`EditorMatch`（整備）、`BattleMatch`（戰鬥）及各自的 `Action`、`Status`、`FixedSummary` |

編輯預覽使用一張示例卡片。正式名稱、種類、情報及圖片由資料提供；編輯模板的文字內容不會改掉正式目錄。大廳相對站位縮放及重疊避讓仍依編隊內容動態計算；這部分保留程式排版。既有背景排序修正也保留。

目前採用原生屬性面板編輯，已移除 FormationCardLayout 與 CardScale，沒有新增 Editor UI 面板或 Play 時覆寫尺寸的程式。CardSign、PortraitViewport、Portrait 及 SelectedGlow 使用全伸縮；名稱與種類使用底部水平伸縮，保留文字區域高度並開啟 BestFit；怪物圖片保持自身比例。這是跟隨父尺寸的重新排版，不是所有元素嚴格等比例縮放。大幅改變長寬比仍會使 Cardgame 裝飾變形，固定底部的文字也不會自動追隨素材內部銘牌。

149×216 修正：原先沿用 213×309 的兩層圖片留白，縮小後圖片容器只剩 56×27。改為外層左右 16、上 20、下 70，內層四邊 8，使圖片容器為 101×110；名稱高度 28、底部中心 44，種類高度 24、底部中心 16，並調小字級上限。非對稱伸縮留白的 anchoredPosition 同步保存為中心偏移 25，避免 Maker 匯入後回到垂直置中。靜態 lint 的 L004 因此保留；以 Maker 解析後的尺寸、位置與截圖驗證。

本輪驗證：本機契約 33/33，UI lint 0 Error、2 Warning（上述 L004 及既有 L016）。Maker build 0 Error、2 項既有 Warning，runtime 無 Error／Warning。CardResize PASS：149×216、181×263、213×309 的圖片可用範圍、圖像／名稱／種類不重疊、選取及重建目錄；原生 Play 截圖確認 149×216 三張正式卡片。已 Stop／Refresh 返回編輯模式；未操作 Maker 原生屬性面板或重跑保存／配對流程。

2026-10-31 原生尺寸修訂：本機契約 33/33，strict lint 109 entities、0 Error、1 項既有 L016 Warning。Maker build 無 Error，最終 runtime 無 Error／Warning；CardResize、EditorAuthoring、EditorIntel PASS。已測試 181×263、160×250、恢復原尺寸及重建目錄，並比對 Play 中 181×263 畫面。Maker 原生屬性面板的手動輸入及編輯畫面預覽仍待使用者確認；未重跑完整保存／配對或手機。以下縮放紀錄屬先前版本。

縮放修訂驗證：本機契約 33/33；strict lint 維持 109 entities、0 Error、1 項既有 L016 Warning。Maker build 0 Error、兩項既有 Warning，最終驗證輪 runtime 無 Error／Warning。`CardScaleProbe`、`EditorAuthoring`、`EditorIntel` PASS；原生畫面比對確認 65% 與 100% 的框、圖片、文字及標記同比例縮放。此輪未重跑保存失敗注入、完整配對對戰或手機；最後已 Stop 返回編輯模式。

此輪驗證：本機契約 **33/33**；FormationGroup 109 entities strict lint **0 Error、1 Warning**（L016，底部操作列刻意靠左，保留玩家部署區）；MatchGroup 19 entities strict lint **0 Error、0 Warning**。Maker build **0 Error**、保留原有兩項 Warning，runtime 無 Error／Warning。`EditorAuthoring` PASS：Play 隱藏預覽、卡片繼承模板字級、改動固定位置／尺寸後 Render 與地圖切換不覆蓋、收合／展開、三種配對容器的內容路由。`EditorIntel`、`EditorFlow`、`EditorFailure`、`MatchedLobbyUI`、`AuthoringPOC` 均 PASS；配對測試實際排隊後取消，POC 測試經正式入口進入再返回。

原生整備截圖確認版面與卡片內容維持可讀。Stop 後透過 Maker Command Console 的 `list_entities -path World/ui/FormationGroup/Editor -enableonly`、模板及 `EditorMatch` 查詢，確認編輯模式中的預設啟用狀態。完整保存流程使用唯一隔離儲存鍵；失敗注入已重設，原有存檔未覆寫。戰鬥版面以畫面切換方法與結果顯示驗證，未重跑雙玩家完整對戰；實體滑鼠各狀態、小視窗與手機仍屬下方人工驗收範圍。

## 驗證紀錄

2026-10-30，原生 Maker，1920×1080 參考畫布。Refresh 後讀 build，再 Play；下列 runtime 結論均有最終 PASS，派送成功不算測試通過。

| 檢查 | 證據 |
|---|---|
| 本機契約 | `node --test tests/*.test.cjs`：32/32 通過 |
| UIBuilder strict lint | 105 entities，0 Error、0 Warning |
| Maker build | 0 Error；保留原有 IsPCPlatform 舊 API、BattleViewAvatar 動作選擇器兩項 Warning |
| 正式卡片與情報 | `editor_intel_runtime_probe.lua`：逐張卡片選取、正式五項情報、場上選取、詳情開關、保存操作可見、冗餘按鈕已移除與實際背景排序 PASS |
| 編輯完整流程 | `editor_flow_runtime_probe.lua`：重複兵種、分數座標移動、移除、六人上限、邊界、0.3 間距、保存、明確設為出戰、乾淨返回與未保存返回選擇 PASS |
| 原生戰場輸入 | `editor_native_input_runtime_probe.lua`：實際 mouse_input 在 `(640,540)` 放置，與事件實際 TouchPoint 的 ScreenToWorldPosition 結果相符，保存內容不變，最後恢復草稿與組別，PASS |
| 讀寫失敗 | `editor_failure_runtime_probe.lua`：讀取失敗、重試可達、待處理停用、阻止離開、寫入失敗保留草稿與已保存內容、重讀後可再保存，PASS |
| 正式目錄溢出 | 18 筆暫時 CSV，原 Tank 改名及同種類不同 ID／數值；`editor_catalog_runtime_probe.lua` PASS，最後一張選取與情報正確 |
| 原生滾輪 | 右側間隙 `(1305,600)` 向下、卡面 `(1140,600)` 向上，各 60 次 delta ±1、間隔 250ms；到達底端及回到頂端，PASS |
| POC 相容（前一版驗證） | `formation_poc_regression_runtime_probe.lua`、`deployment_ui_runtime_probe.lua` PASS；本次未重跑，POC 配對版面條件保留原值 |
| 審查（初版驗證） | Standards／Spec 兩軸審查及當時修訂後複查，無剩餘阻擋項目；本次版面修訂未重跑雙軸審查 |

原生畫面已確認標題、直式卡片、種類、情報與底部操作可讀，填色不再蓋住內容。這不代表所有按鈕視覺狀態均已驗收。

## 重現與清理

一般 client probes 從 formationlobby 啟動。原生輸入 probe 依其 READY 訊息立即派送 mouse_input，再讀取最終結果。Maker 會將模擬座標換算到遊戲視窗，因此 probe 監聽實際 ScreenTouchEvent.TouchPoint 作為轉換基準，結束時解除監聽。完整流程 probe 要先在 server_main 將 `_FormationService.StorageKey` 設為唯一的新測試鍵（例如 `'CodexIssue49_' .. _UtilLogic:NewGuid()`）；它會保存及設為出戰，不能用原有存檔測試。Stop/Play 恢復預設鍵。

失敗 probe 先進入整備，再於 server_main 呼叫 `_FormationStorage:ConfigureMakerFaults(1, 1, 1)`，接著執行 client 檔案。唯一保存請求在儲存邊界注入失敗，沒有改寫原有存檔；結束後重設 `(0, 0, 0)` 並 Stop。草稿及所選組別由 probe 還原，Stop/Play 重設登入內版本。

目錄測試用 `node tests/editor_catalog_fixture_driver.cjs` 的 guarded transaction。逐一完成 JSON 請求指定的真實 Maker 操作後，以對應 id 回覆。`editor-catalog-probe` 階段執行 client probe；看到 WHEEL_READY 後立即開始上述滾輪序列，三十秒內須到達底端。另在底端觀察原生向上捲動至頂端。只有最終 PASS 才可確認該階段。還原階段在 fresh Play 執行 `monster_catalog_restored_runtime_probe.lua`，讀到 PASS 再回覆。取消或失敗也須讓 guard 完成 Stop、原始位元組還原、Refresh 與正式目錄驗證。

本次目錄與滾輪 probe 均 PASS；中斷讓 guard 在等待還原驗證回覆時逾時，因此不記為 guard 完整 PASS。清理已接續完成：原始 CSV 1458 bytes、SHA-256 `45e1358c0596fb4008b2830f93d79c2ec677d0df4263db87b51fbed55a3e15a5`，fresh Play 的 `CatalogRestoreProbe` 確認正式三筆資料及原 Tank 數值還原、臨時 ID 不存在，`EditorIntel` 再次 PASS。最後透過 MCP Stop 返回編輯模式。原有編隊存檔未被覆寫，沒有重設 Maker DataStorage；隔離測試鍵可能留在本機。

## 人工驗收邊界

mouse_input 工具明示不會點擊引擎管理的 UI；正式按鈕用已綁定的 SendEvent 驗證，不能稱作真實滑鼠點擊。額外面板點擊 probe 的 IsPointerOverUI 回傳 false，未能證明真實滑鼠的 UI 阻擋；保留人工檢查，不能以模擬器結果宣稱通過。面板接收表面及裝飾不接收點擊的設定已檢查。

請用實際 PC 滑鼠確認面板點擊不會穿透布陣、右鍵取消選取與移除、四種按鈕視覺狀態、詳情彈出後的閱讀感，以及較小 PC 視窗。移除流程已由世界輸入方法驗證；mouse_input 不會發出右鍵 KeyDownEvent，尚未驗證實體 PC 右鍵。沒有可直接切換 PC 解析度的 Maker MCP 工具；未驗證手機。本票保留開啟等待使用者驗收，#50–#52 的後續改版未納入。
