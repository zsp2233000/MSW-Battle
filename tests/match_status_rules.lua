-- Shared production-rule assertions: run on the Maker client or via match_status_local.cjs.
local status = _MatchFlowState
local checks = 0
local function check(snapshot, now, message, label, action, enabled, inMatchRoom)
    for _, surface in ipairs({ "WAR", "LOBBY" }) do
        local view = status:PresentMatch(snapshot, { now = now, inMatchRoom = inMatchRoom,
            originName = surface == "WAR" and "左營" or "" })
        local expectedLabel = inMatchRoom and surface == "WAR" and "返回 左營" or label
        assert(view.text == message, snapshot.state .. ": " .. view.text)
        assert(view.label == expectedLabel and view.action == action and view.enabled == enabled, snapshot.state .. ": wrong action")
        assert(not string.find(view.text .. view.label, "守衛", 1, true))
        checks = checks + 1
    end
end
check({ state = "QUEUED", guardAt = 11000 }, 10001, "配對中 · 倒數 1 秒", "取消配對", "CANCEL", true)
check({ state = "QUEUED", guardAt = 11000 }, 11000, "即將開戰…", "", "", false)
check({ state = "RENEWING", guardAt = 11000 }, 12000, "即將開戰…", "", "", false)
check({ state = "QUEUED", started = 1000 }, 9000, "配對中 · 已等候 8 秒", "取消配對", "CANCEL", true)
local entering = "配對成功，正在進入戰場"
for _, stage in ipairs({ "SAVING", "COMMITTING", "TRANSFER", "IN_ROOM", "WAITING" }) do
    for _, guard in ipairs({ false, true }) do
        check({ state = stage, guard = guard, entryDeadline = 31000 }, 30999, entering, "", "", false)
    end
end
check({ state = "QUEUED", opponentFound = true, guardAt = 11000 }, 10001, entering, "", "", false)
check({ state = "TRANSFER", entryDeadline = 31000 }, 31000, "入場失敗", "停止入場", "RETURN", true)
check({ state = "TRANSFER", reasonCode = "ROOM_MOVE_FAILED", entryDeadline = 31000 }, 1500, "入場失敗", "停止入場", "RETURN", true)
check({ state = "SAVING", reasonCode = "READINESS_FAILED", entryDeadline = 31000 }, 1500, entering, "", "", false)
check({ state = "ENTRY_FAILED" }, 1500, "入場失敗", "返回大廳", "RETURN", true, true)
check({ state = "WAITING", entryDeadline = 31000 }, 31000, "入場失敗", "返回大廳", "RETURN", true, true)
check({ state = "CANCELLING" }, 10001, "正在取消配對…", "", "", false)
check({ state = "CANCELLED", busy = true }, 10001, "正在取消配對…", "", "", false)
local stopped = "配對已停止，請取消後重新配對"
check({ state = "QUEUE_ERROR" }, 10001, stopped, "取消配對", "CANCEL", true)
check({ state = "QUEUED", reasonCode = "CANCEL_FAILED" }, 10001, stopped, "取消配對", "CANCEL", true)
check({ state = "CANCELLED", reasonCode = "CANCEL_SAVE_FAILED" }, 10001, stopped, "取消配對", "CANCEL", true)
local sending = status:PresentMatch({ state = "QUEUED" }, { now = 1000, pending = true, pendingAction = "CANCEL" })
assert(sending.text == "正在取消配對…" and sending.action == "" and not sending.enabled)
print("[VRF][MatchStatus] presentation matrix PASS cases=" .. tostring(checks + 1))
