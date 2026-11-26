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
-- ADR 0017: the human who is here waits for the absent side; the entry time does not end that wait, and the count never goes below zero.
check({ state = "WAITING", waitDeadline = 41000, entryDeadline = 31000 }, 31000, "等待對手進入戰場…（10 秒）", "", "", false)
check({ state = "WAITING", waitDeadline = 41000, entryDeadline = 31000 }, 41500, "等待對手進入戰場…（0 秒）", "", "", false)
check({ state = "ENTRY_FAILED", waitDeadline = 41000 }, 1500, "入場失敗", "返回大廳", "RETURN", true, true)
check({ state = "CANCELLING" }, 10001, "正在取消配對…", "", "", false)
check({ state = "CANCELLED", busy = true }, 10001, "正在取消配對…", "", "", false)
local stopped = "配對已停止，請取消後重新配對"
check({ state = "QUEUE_ERROR" }, 10001, stopped, "取消配對", "CANCEL", true)
check({ state = "QUEUED", reasonCode = "CANCEL_FAILED" }, 10001, stopped, "取消配對", "CANCEL", true)
check({ state = "CANCELLED", reasonCode = "CANCEL_SAVE_FAILED" }, 10001, stopped, "取消配對", "CANCEL", true)
local sending = status:PresentMatch({ state = "QUEUED" }, { now = 1000, pending = true, pendingAction = "CANCEL" })
assert(sending.text == "正在取消配對…" and sending.action == "" and not sending.enabled)
-- #119 (ADR 0016): the result page of a war match says where Return goes, and says so first when the departure town fell.
local function result(context) context.now = 1 return status:Present({ state = "RESULT_WIN", attempt = "a" }, context) end
local lobby = result({})
assert(lobby.label == "返回大廳" and lobby.text == "可返回大廳繼續整備或再次配對" and lobby.action == "RETURN" and lobby.enabled, "a lobby result is unchanged")
local home = result({ originName = "左營", originLabel = "<c>左營</c>", destinationName = "<c>左營</c>" })
assert(home.label == "返回 <c>左營</c>" and home.action == "RETURN" and home.enabled, "a war result names the departure town")
assert(not string.find(home.text, "已失守", 1, true), "no fall notice while the town stands")
local fell = result({ originName = "左營", originLabel = "<c>左營</c>", destinationName = "<c>鹽埕</c>", originLost = true })
assert(fell.text == "<c>左營</c>已失守" and fell.label == "返回 <c>鹽埕</c>", "a fallen departure town is announced above a button that names the capital")
local plain = result({ originName = "左營", destinationName = "鹽埕", originLost = true })
assert(plain.text == "左營已失守" and plain.label == "返回 鹽埕", "the plain name is used when no highlight is supplied")
local anonymous = result({ originLost = true })
assert(anonymous.label == "返回大廳" and not string.find(anonymous.text, "已失守", 1, true), "no town names, no war wording")
for _, state in ipairs({ "RESULT_LOSE", "RESULT_DRAW" }) do
    local view = status:Present({ state = state, attempt = "a" }, { now = 1, originName = "左營", destinationName = "左營" })
    assert(view.label == "返回 左營", state .. " names the destination too")
end
local retry = status:Present({ state = "RETURNING", attempt = "a" }, { now = 1, originName = "左營", destinationName = "左營" })
assert(retry.label == "重試返回" and retry.action == "RETURN", "a stuck return keeps its retry button")
local moving = status:Present({ state = "RESULT_WIN", attempt = "a" }, { now = 1, pending = true, originName = "左營", destinationName = "左營" })
assert(moving.label == "返回中…" and moving.text == "正在返回…" and not moving.enabled, "pending return is not the lobby wording for a war result")
print("[VRF][MatchStatus] presentation matrix PASS cases=" .. tostring(checks + 1))
