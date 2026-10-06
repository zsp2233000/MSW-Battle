# Battle 驗證

本機結構與資料檢查：

```powershell
node --test tests/*.test.cjs
```

攻擊行為使用 Maker 的真實 AttackComponent、HitEvent 與 BattleSession，不以 JavaScript 重建戰鬥邏輯。

每個 runtime probe 應在新的 Play test 執行。先 Stop、Refresh、讀取 build logs、Play，待 DEPLOYMENT ready 後，將 Lua 檔案完整內容傳給 maker_execute_script，context 使用 server_main。execute_script 回傳 ok 只代表派送成功；必須讀取 normal logs，等到最後的 PASS 或 failures=0，並檢查 Error／Warning。attack_execution 的無效配置案例會刻意產生一次「unsupported attack profile」診斷；其餘 Error／Warning 都須處理。最後 Stop。

| Probe | 驗收內容 |
|---|---|
| attack_execution_runtime_probe.lua | 三兵種命中、取消、重配置前後已接受命中的政策、openingDelay、死亡、hit stop、RESULT |
| attack_clock_runtime_probe.lua | 取得／釋放手動時鐘、自動／手動互斥、恢復正式攻擊 |
| shooter_runtime_probe.lua | 受控編隊中的射手原生移動、資料命中影格、hitscan 與自然 WIN／RESULT |
| tank_contact_runtime_probe.lua | 受控編隊中的原生接觸、各目標獨立 cooldown、擊退邊界與自然 WIN／RESULT |
| six_vs_six_batch_outcome_probe.lua | 登記存活數、停用不算死亡、致死傷害只扣一次、同批已接受命中不因攻擊者死亡而撤回；DRAW 只發布一次 |
| six_vs_six_runtime_probe.lua | 六名正式部署玩家對六名地圖固定敵人的整合驗證 |
| targeting_crowding_runtime_probe.lua | 最近目標與平手偏好、停用／死亡後重索敵、重疊單位原生移動與邊界、自然 WIN／LOSE／DRAW 及 RESULT 停止 |
| six_vs_six_full_battle_probe.lua | 十二個單位自然對戰、結果及終止後狀態 |
| controlled_scenario_runtime_probe.lua | Maker-only 受控編隊、輸入原子驗證、profile 覆寫、時鐘所有權、場景切換隔離及中途生成失敗清理 |

`controlled_scenario_runtime_probe.lua` 會故意嘗試一次不存在的模型，驗證部分生成失敗後清理已建立單位；該案例預期出現 `LEA-3028`、`SpawnByModelId returned nil` 與 `[M1][BattleSession] CONFIG_ERROR` 診斷。除此之外，probe 的 Error／Warning 都須處理。

手動 probe 以 BeginManualSimulation 取得自有邏輯的時間控制權，結束或發生 Lua 錯誤時以 EndManualSimulation 釋放。InitializeBattle 與 OnEndPlay 也會恢復正式時鐘。手動時間不推進原生 Body；移動與擊退必須使用正式 Maker frames 驗收。

Issue #17 的接觸、射手、索敵與擁擠 probe 透過 PrepareBattleForTest 建立完整受控編隊；終局只能由原生攻擊、HitEvent、正式傷害批次與存活數自然產生。只有索敵 probe 的明確無效目標案例會 SetEnable(false)，並驗證停用不會改變存活計數。六對六 probe 保留六名玩家加六名地圖固定敵人的正式部署檢查。

新測試直接觀察 HP、AttackSerial、語意事件與結果，不檢查 module 私有 pending／cooldown。來源字串中的方法名稱、timer 所在檔案及 adapter 組成不再是攻擊行為的驗收條件。
