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
| shooter_runtime_probe.lua | 射手正式移動、射程、資料中的命中影格、無 projectile、RESULT |
| tank_contact_runtime_probe.lua | 正式接觸、各目標 cooldown、擊退、邊界、RESULT |
| six_vs_six_batch_outcome_probe.lua | 同批已接受命中不因攻擊者死亡而撤回；DRAW 只發布一次 |
| six_vs_six_runtime_probe.lua | 固定編隊、索敵、擁擠移動、WIN／LOSE／DRAW、RESULT |
| six_vs_six_full_battle_probe.lua | 十二個單位自然對戰、結果及終止後狀態 |

手動 probe 以 BeginManualSimulation 取得自有邏輯的時間控制權，結束或發生 Lua 錯誤時以 EndManualSimulation 釋放。InitializeBattle 與 OnEndPlay 也會恢復正式時鐘。手動時間不推進原生 Body；移動與擊退必須使用正式 Maker frames 驗收。

新測試直接觀察 HP、AttackSerial、語意事件與結果，不檢查 module 私有 pending／cooldown。來源字串中的方法名稱、timer 所在檔案及 adapter 組成不再是攻擊行為的驗收條件。
