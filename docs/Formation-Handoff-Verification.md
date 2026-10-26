# 本局編隊交接重構與驗證

2026-10-24 開始實作，2026-10-26 接續。依架構報告第二項實作，維持 ADR-0003 的操作規則，以及 `BattleFormationsV2`／`BattleTransferV2` 的資料格式。

2026-10-26 已完成本機驗收。重跑時曾以 `HandoffLateLeave FAIL` 重現延遲離開事件清除已還原 session 的問題；現在 session 綁定實際玩家實體，離開後依該實體的銷毀事件清理。真實換房已確認舊 session 被清除，返回後再注入舊離開／銷毀事件，也不會清除新 session。

`FormationHandoff` 管理交接內容、固定本局編隊、最新五組草稿、儲存確認及返回還原。`FormationService` 保留編輯、保存與啟用功能。`MatchProbe` 處理配對身分、狀態與原生傳送，拿不到編隊 payload 或原始保存 bytes；`MatchedBattle` 取得授權後向交接模組讀取已驗證編隊。

## 已執行的檢查

| 情境 | 證據與結果 |
| --- | --- |
| 測試先失敗 | 新介面尚未實作時，Maker 日誌出現 `HandoffReserve FAIL ... FormationHandoff interface is required`。 |
| 本局編隊固定 | `formation_handoff_runtime_probe.lua`：票券僅含中繼資料，編隊為獨立副本；後續草稿保存與封存不改變本局內容。 |
| 保存失敗與返回清理 | `formation_handoff_failure_runtime_probe.lua`：保存失敗仍可封存；返回清理失敗重試不覆蓋新草稿。 |
| 保存逾時 | 同一 probe：封存保留草稿，延遲成功回覆不修改已封存狀態；之後明確重新讀取可核對結果。 |
| 交接逾時與舊回覆 | 同一 probe：等待有上限；舊寫入不能覆蓋新票券，舊取消不能解除新鎖，舊 handle 不能再保存。 |
| 配對成功後取消 | `formation_handoff_cancellation_runtime_probe.lua`：在 SAVING 期間取消雙方並重新排隊，新票券維持 QUEUED，舊對局不傳送已取消的玩家。 |
| 延遲離開與舊實體銷毀 | `formation_handoff_late_leave_runtime_probe.lua`：延遲離開不清除仍連線的已還原 session。完整往返 probe 在返回後注入舊玩家實體的銷毀事件，sessionId、五組編隊及草稿仍保留；原生換房也實際觸發兩次舊 owner 清理。 |
| 損毀資料 | `centered_transfer_validation_runtime_probe.lua`：舊座標格式、舊存檔 schema、損毀本局編隊與草稿版本均不能入場或部分還原；測試結束已恢復原生地形。 |
| 雙玩家完整往返 | `matched_battle_queue_runtime_probe.lua` → 房間內 `matched_battle_room_runtime_probe.lua` → 返回後 `matched_battle_return_runtime_probe.lua`。排隊六隻、後存一隻，入場仍為六對一，自然產生 WIN／LOSE。五組預存編隊、出戰選擇、草稿及編輯組保留，返回後可再次配對／取消。 |
| 房間回收 | 雙方返回後，Maker context 清單只剩 `server_main` 與 `client`。 |
| 編譯與自動檢查 | Maker build 無 Error；`node --test` 為 32/32 通過。既有過時 API 與 avatar selector Warning 仍存在。 |

失敗注入僅使用獨立 Maker 虛擬玩家，未修改原玩家的預存編隊；測試後已將保存回覆及失敗注入設定復原，Maker 回到編輯模式。

交接重構及延遲離開修正已完成規範與需求兩軸審查，沒有未解決的受支持發現。自動保存及編輯鎖更新保留在 FormationService，交接模組不直接存取其私有 session 表。

本輪 Maker 日誌的主要正向證據（2026-10-26）：

```text
19:15:18 [VRF][HandoffCancellation] PASS cancel during SAVING; requeue intact; old matched callback cannot enter
19:16:13 [VRF][Formations] departed owner session cleared  （雙玩家各一次）
19:16:14 [VRF][MatchedBattle] initialized home=6 away=1 started=true
19:17:30 [VRF][MatchedRoom] PASS immutable 6v1; natural WIN/LOSE; stable terminal; return dispatched
19:17:31 [VRF][MatchedPreservation] PASS five saved slots, active selection, draft contents and editor selection
19:19:08 [VRF][MatchedReturn] PASS both lobby; saved active formations retained; requeue/cancel
19:19:08 [VRF][HandoffLateLeave] PASS delayed leave cannot clear the connected restored session
```

## 重跑方式與限制

在 Maker Play 用 `add_virtual_player -profile_code hf2601 -nickname HandoffA` 及 `add_virtual_player -profile_code hf2602 -nickname HandoffB` 建立專用測試玩家。先於 `server_main` 執行 `formation_handoff_fixture_runtime_probe.lua`，再依序執行上表 probes。進入戰鬥後需改用實際的 `server_instance_*` context 執行房間 probe；返回驗證與 `formation_handoff_late_leave_runtime_probe.lua` 在 `server_main` 執行。

這些測試覆蓋 Maker 本機 FIFO、真實 Room API 與相同的伺服器入列路徑，沒有偽造原生跨 instance 配對成功通知。公開環境的 MatchmakingService、leaderboard 設定及跨 WorldInstance 傳送，仍須用兩個真實帳號驗收。本次沒有新增 package、變更地圖或玩家操作流程。
