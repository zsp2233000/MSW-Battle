# 以模板地形與共用規則保證編隊站位相容

玩家保存的相對站位必須能在不同地圖原樣套用，因此所有地圖的站位地形以 [template.map](../../map/template.map) 為共同基準，統一地圖模式、格子座標與尺寸、可行走區域及碰撞配置。地形與模板不一致屬於開發配置缺陷，須由涵蓋所有地圖的一致性檢查攔截並修正地圖，避免將有效的預存編隊誤判為玩家資料錯誤。

沿用 [FormationMapLayout](../../RootDesk/MyDesk/Formations/FormationMapLayout.mlua) 作為全遊戲共用的站位規則模組，集中合法位置、部署間距與左右鏡射；編隊資料層負責兵種、數量與存檔欄位，戰鬥層負責生成單位。保留連續座標自由布陣、左側玩家部署區、以 x=0.5 為中心的鏡射，以及既有存檔格式；最小部署間距為 0.3 世界單位，等於門檻時可放置，浮點誤差採一致判定。

本決策延續 [ADR 0001](0001-keep-recttile-for-poc.md) 的 RectTile 模式與 [ADR 0002](0002-configure-battle-roster-on-map.md) 的關卡預配置單位，並維持 [ADR 0003](0003-persist-formations-before-live-pvp.md) 對編隊草稿、預存編隊與本局編隊的區分。
