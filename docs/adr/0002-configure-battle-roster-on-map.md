# 以地圖放置實體配置戰鬥編隊

原本六個敵軍 ID 與座標固定在 `BattleSession`，增減怪物須修改程式。改以 Maker 放置的 model 實體保存 `MonsterId`、`Faction` 與位置；進入 `map01` 時驗證配置，從 `MonsterData` 生成真正的 `BattleUnit` 並取代放置實體。這保留單一怪物資料來源與既有戰鬥初始化流程，也讓關卡編隊可在 Maker 增刪、移動與改陣營。
