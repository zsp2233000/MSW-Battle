# 國戰大地圖在城鎮中查看，戰果寫入後以事件推送戰況，不輪詢

Roadmap 原本把「國戰大地圖」放在 Backlog，呈現與操作形式待定。2026-11-24 使用者確認首版：依高雄行政區的實際排列畫四座城鎮，以連線表示相鄰；只能查看；在城鎮裡開啟，遊戲大廳不提供；戰況由伺服器推送給客戶端；底圖要有高雄地形。這份 ADR 記下做法，詞彙依 CONTEXT.md（國戰大地圖、據點、兵力值、主城、戰果）。

## 決定一：地圖是畫好的底圖加上執行時上色，相鄰關係取自傳送門

- 介面在 `ui/WorldMapGroup.ui`，由 `assets/worldmap/build_ui.cjs` 以 UIBuilder 產生；客戶端邏輯 `FactionWarMapUI` 以路徑找元件，和 `FactionWarUI` 相同。
- 素材找不到現成的高雄地圖，改用 `assets/worldmap/paint_worldmap.cjs` 以像素繪出：行政區外框是以經緯度描的近似輪廓（等距圓柱投影，北上），包含海岸、壽山、半屏山、蓮池潭、愛河與旗津。輸出一張地形底圖、每城一張白色遮罩、一張城徽，上傳為帳號資源（RUID 記在 `assets/worldmap/ruids.json`）。遊戲中把遮罩與城徽依歸屬著色，地形底圖不變。各城節點的位置是遮罩的中心，寫在 `layout.json`，建 UI 時讀它。
- 連線不寫死在圖上：伺服器以 `FactionWar:FindGate` 列出任一方向有傳送門的城鎮對，客戶端在兩個城徽之間畫線。改了傳送門，地圖跟著改。

## 決定二：開著地圖的人才是訂閱者

按「大地圖」或 M 鍵時，客戶端呼叫 `FactionWarMap:RequestOpen`。伺服器確認玩家站在城鎮裡，記下他是這個靜態房的觀看者，讀一次城鎮文件後回傳戰況，另外讀一次他的陣營。關閉地圖、離開城鎮（客戶端在 `OnUpdate` 偵測到後關閉，並送 `RequestClose`）、離開這個房間（`UserLeaveEvent`）都會結束訂閱。

## 決定三：戰果寫入後發事件，有觀看者的房間才重讀

`FactionWarAttack:Finish` 在 `SAVED` 或 `DUPLICATE` 時呼叫 `FactionWarMap:AnnounceChange`：

- 同一個 world instance：比賽房以 `RequestSendEventToRoomAsync` 通知靜態房，作法同 `TownFellEvent`（ADR 0012）；結算若就在靜態房，直接處理。
- 其他 world instance：以 `_WorldInstanceService:RequestSendEventToAllWorldInstancesAsync` 送 `TownBoardChangedEvent`，事件帶發送端的 `WorldInstanceId`（`Source`）。Maker 實測這個事件也會送回發送端自己的 instance，所以處理器略過 `Source` 等於自己 instance 的事件，這種事件已經用房間事件收過了。

收到通知的房間，沒有觀看者就什麼都不做，不花儲存額度。有觀看者就重讀城鎮文件，同一時間只讀一次，讀取中又來的通知會在讀完後再讀一次。讀到的戰況和上次推送的不同，才推給所有觀看者；剛開地圖的人一定會收到回覆。

**不選**：

- 定時輪詢城鎮文件：與 ADR 0012 和 `MatchFlow`「不做重複的儲存輪詢」相同理由，每個房間都要付固定額度。
- 把戰況直接放進事件：兩場結算的事件可能不按順序到達，較舊的戰況會蓋掉較新的。重讀已存的文件才是準的，也只多花一次讀取。
- 用 `@Sync` 屬性同步：table 不能同步，而且會送給房內所有客戶端，包括沒開地圖的人。

## 附帶效果

地圖開著時，推送來的戰況也會更新所在城鎮的 HUD 兵力（`FactionWarUI:ShowTownStatus`）。地圖沒開時，HUD 仍照 ADR 0012 的規則，只在進城與排隊回到 IDLE 時重讀。

## 已知缺口

- 只有戰果結算會發通知。`FactionWar:WriteTowns`（種子資料、測試夾具）不會通知；GM 也沒有改城鎮文件的工具。
- 事件送失敗不重試。少掉的那次變動，要等下一場戰果的通知或重開地圖才看得到。
- 跨 world instance 的推送只在 Maker 的單一 instance 驗證過：本 instance 會收到自己發出的事件。發布環境中多個 instance 的實際送達還沒驗證，留給 #110 雙帳號驗收時一併觀察。
- 失守城鎮的清掃（ADR 0012）仍只用房間事件，這份 ADR 沒有改它。
- M 鍵用 `KeyDownEvent` 偵測，目前沒有 API 能判斷輸入框是否有焦點，所以在聊天框打字時按 M 也會開關地圖。
