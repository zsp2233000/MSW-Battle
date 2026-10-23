# 以持久編隊銜接真人對戰與後續國戰

玩家先在世界內的整備區保存預存編隊，持久保存兵種、數量與相對站位，重新登入後仍可使用。對戰採兩名在線玩家各帶一支預存編隊，進入同一戰場觀看自動戰鬥；每次進戰場重新配兵的流程改由戰前整備承擔。預存編隊與 ADR 0002 的關卡預配置單位是不同概念。

本次範圍先完成遊戲大廳、玩家資料與編隊持久化，以及跨 world instance 的真人一對一配對對戰。大地圖、陣營加入與據點結算留到後續，以先驗證完整對戰流程、再接上國戰；里程碑安排以 [Roadmap](../BattlePOC-Roadmap.md) 為準。

每名玩家可保存五組預存編隊，每隊一至六個單位、兵種可重複，所有玩家使用相同可選兵種池。五組之中選定一組出戰編隊；玩家可編輯其他組配置並先保存，進入戰場時使用啟用的出戰編隊。儲存與切換出戰組是分開的操作，只有「設為出戰編隊」才更換啟用組；例如第一組出戰、編輯第二組時，儲存只更新第二組，不會將第二組自動設為出戰。編隊配置仍是單一功能，玩家在模擬地圖編輯草稿，排隊期間也可以繼續調整。雙方入場流程完成後直接戰鬥，沒有第二次準備確認。

按下配對時，固定當下已保存且有效的出戰編隊內容，作為本局編隊。後續編輯、保存或切換出戰組不改變本局編隊；要更換本局使用的內容，須先取消再配對。即使正在編輯的就是啟用出戰組，其後續保存的新內容也只供之後的對局使用。

配對成功後，若目前編輯組有未保存的變更，自動儲存至原組別，再使用本局編隊進場。保存成功不切換啟用組，也不改變本局編隊；沒有未保存變更時直接進場。保存失敗或編輯內容不合法時，提示原因並保留草稿，仍以本局編隊進場；不得顯示為保存成功。草稿在同次登入內跨入戰場及返回大廳時也須保留，轉移流程須攜帶這份尚未保存的內容。

2026-10-18 需求修訂：由一組擴為五組，保存與出戰選擇分離；原先配對成功後的保存／捨棄提示與三十秒倒數，改為自動保存目前編輯組後直接進場。保存失敗仍繼續使用本局編隊，避免編輯中的配置阻塞已成立的對戰。

第一版採個人功能大廳，提供整備、設定及配對入口；模擬地圖先提供布陣與儲存，不包含對 AI 試打。其他編隊欄位可留空，只要有一組已保存、有效且啟用的出戰編隊，就能加入配對池。

配對持續到成功或玩家主動取消，不以等候六十秒為由結束。大廳及模擬地圖須提示配對狀態、顯示已等候時間並提供取消操作；計時器顯示已等待時間，不是結束配對的倒數。

編隊草稿在個人功能大廳與模擬地圖之間切換時保留；重新登入只恢復已保存的預存編隊。排隊期間編輯不會自動覆蓋預存編隊；手動保存及配對成功時的自動保存是明確的保存時點。

已開始的自動戰鬥不因玩家斷線直接判負，仍繼續完成；若雙方都離開且戰場被回收，該局視為中止，預存編隊保留。本次只顯示當局戰鬥結果，結束後返回個人功能大廳；歷史戰績與斷線重返原戰場留到後續，安排以 Roadmap 為準。

2026-10-18 已核對完整流程並確認本次設計基線。套件整合選用與原生配對能力的技術驗證，仍須在實作規劃中具體確認。

2026-10-18 已查核官方 [MSWPackages](https://github.com/MSW-Git/MSWPackages) 的完整目錄與相關程式，查核版本為 `80f5613e3479539465aa67446bfe4ee23f2ff553`。候選重用範圍為 [PlayerData](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/README.md) 的玩家存讀骨架與兩鍵提示視窗、[CardGame UI](https://github.com/MSW-Git/MSWPackages/blob/main/ui-resource-cardgame-package/README.md) 的 Lobby／RankedMatch 視覺模組，以及 [UI Component](https://github.com/MSW-Git/MSWPackages/blob/main/ui-component-package/README.md) 的等待動畫等零件；尚未安裝或決定整合哪些模組。編隊編輯與配對流程仍需本遊戲串接；RankedMatch 視覺模組本身不提供配對服務。

PlayerData 範例中的 [PlayerDBManager](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/MyDesk/PlayerDataPackage/Sample/PlayerDBManager.mlua) 與 [PlayerData](https://github.com/MSW-Git/MSWPackages/blob/main/player-data-package/MyDesk/PlayerDataPackage/Sample/PlayerData.mlua) 尚無完整的保存成功回覆與失敗補救，且組裝待寫資料時便清除 dirty。採用時須補足寫入確認、失敗保留待存狀態與版本處理；五組編隊及啟用組欄位須由本遊戲定義。草稿、已保存編隊與本局編隊須分離，避免排隊期間的編輯或後續保存改變本局使用的內容。

原生 [MatchmakingService](https://maplestoryworlds-creators.nexon.com/en/apiReference?postId=1397) 可列為配對候選；其請求／結果有效期限、成功後等待編隊保存完成再傳送的支援仍未獲文件證實，須在發布環境驗證。驗證亦須涵蓋保存失敗時攜帶草稿與固定本局編隊跨 instance 進場。官方 [001_Lobby 教學](https://maplestoryworlds-creators.nexon.com/en/docs?postId=1136) 可參考等待 UI 與 InstanceRoom 派送，但尚未證實涵蓋跨 WorldInstance 配對，且其 Ready／倒數流程須依本次已確認流程調整。
