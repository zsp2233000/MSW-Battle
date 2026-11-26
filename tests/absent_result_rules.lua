-- Run from absent_result_local.cjs. Fake storage, fake room events and a fake player list; the AbsentResult bodies are production code.
local doc = _AbsentResult
local checks = 0
local function check(condition, label) checks = checks + 1; assert(condition, label) end

-- Storage stand-in: opaque bytes, create-or-compare-and-swap like FormationStorage.Write (an existing key needs its exact expected bytes).
local store, snapshots, writes, failReads, failWrites, conflicts = {}, {}, 0, false, false, 0
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
_HttpService = {
    JSONEncode = function(_, value) table.insert(snapshots, copy(value)); return "bytes" .. tostring(#snapshots) end,
    JSONDecode = function(_, raw) return copy(assert(snapshots[tonumber(string.sub(raw, 6))], "invalid bytes")) end,
}
_FormationStorage = {
    Read = function(_, owner, key, complete)
        if failReads then complete(1000004, key, nil) return end
        local raw = store[owner .. "/" .. key]
        if raw == nil then complete(1000002, key, nil) else complete(0, key, raw) end
    end,
    Write = function(_, owner, key, expected, raw, complete)
        if failWrites then complete(1000004) return end
        local slot = owner .. "/" .. key
        if conflicts > 0 then
            conflicts = conflicts - 1
            -- Somebody else wrote in between: the stored bytes are no longer the expected ones.
            store[slot] = raw .. "-other"
            complete(2000000)
            return
        end
        if (expected == "" and store[slot] ~= nil) or (expected ~= "" and store[slot] ~= expected) then complete(2000000) return end
        writes = writes + 1
        store[slot] = raw
        complete(0)
    end,
}
_FactionWar = { IsMissing = function(_, code, raw) return code == 1000002 or (code == 0 and raw == nil) end }
_FactionWarTownDocument = { TownNames = { nanzih = "楠梓", zuoying = "左營", gushan = "鼓山", yancheng = "鹽埕" } }
_FactionWarUI = { HighlightedTownName = function(_, town) return "<c>" .. _FactionWarTownDocument.TownNames[town] .. "</c>" end }
function wait() end
isvalid = function(value) return value ~= nil end

local key = "red/" .. doc.StorageKey
local function stored() return store[key] end
local function storedRecord() return _HttpService:JSONDecode(stored()) end

-- Compose: a war record carries the war block, a lobby record only the result; nothing about experience.
local receipt = { origin = "zuoying", target = "gushan", status = "SAVED", conclusion = "未易主", originBefore = 100, originAfter = 100,
    targetBefore = 100, targetAfter = 80, destination = "zuoying", originLost = false, matchId = "m1", profile = "red", revision = 3, exp = { 1, 2 } }
local war = doc:Compose("WAR", "m1", "WIN", receipt)
check(war.v == 1 and war.id == "m1" and war.kind == "WAR" and war.result == "WIN" and war.war.targetAfter == 80, "a war record carries the settled figures")
check(war.war.destination == nil and war.war.matchId == nil and war.war.exp == nil and war.exp == nil, "only the war block is kept, never experience or the return preview")
local lobby = doc:Compose("LOBBY", "m2", "LOSE", receipt)
check(lobby.kind == "LOBBY" and lobby.war == nil, "a lobby record has no war block")

-- Decode: only a complete record, or a cleared marker, is understood.
local function decodes(record) snapshots = {}; return doc:Decode(_HttpService:JSONEncode(record)) end
check(decodes(war) ~= nil and decodes(lobby) ~= nil, "valid records decode")
check(decodes({ v = 1, id = "m1", cleared = true }).cleared == true, "a cleared marker decodes")
check(doc:Decode("bytes99") == nil, "unreadable bytes are nothing")
check(decodes({ v = 2, id = "m1", kind = "LOBBY", result = "WIN" }) == nil, "an unknown version is nothing")
check(decodes({ v = 1, id = "", kind = "LOBBY", result = "WIN" }) == nil and decodes({ v = 1, kind = "LOBBY", result = "WIN" }) == nil, "a record needs an id")
check(decodes({ v = 1, id = "m", kind = "LOBBY", result = "WON" }) == nil and decodes({ v = 1, id = "m", kind = "TEAM", result = "WIN" }) == nil, "result and kind are checked")
check(decodes({ v = 1, id = "m", kind = "WAR", result = "WIN" }) == nil, "a war record needs its war block")
snapshots = {}

-- Write: the newest match replaces the older one, the same match twice changes nothing, a lost race is read again.
local done
doc:Write("red", war, function(saved) done = saved end)
check(done == true and storedRecord().id == "m1" and writes == 1, "the first record is created")
doc:Write("red", war, function(saved) done = saved end)
check(done == true and writes == 1, "writing the same match again changes nothing")
doc:Write("red", lobby, function(saved) done = saved end)
check(done == true and storedRecord().id == "m2" and storedRecord().kind == "LOBBY" and writes == 2, "a newer match replaces the older record")
conflicts = 1
doc:Write("red", war, function(saved) done = saved end)
check(done == true and storedRecord().id == "m1", "a lost race is read again and written")
conflicts = 5
doc:Write("red", lobby, function(saved) done = saved end)
check(done == false, "attempts are bounded")
conflicts = 0
failReads = true
doc:Write("red", lobby, function(saved) done = saved end)
check(done == false, "an unreadable record is not overwritten blindly")
failReads = false
failWrites = true
doc:Write("red", lobby, function(saved) done = saved end)
check(done == false, "a failed write is reported")
failWrites = false
store[key] = nil

-- Clear: only the record of that match, and only once.
doc:Write("red", war, function() end)
doc:Clear("red", "other", function(cleared) done = cleared end)
check(done == true and storedRecord().kind == "WAR", "another match's clear leaves the record")
doc:Clear("red", "m1", function(cleared) done = cleared end)
check(done == true and storedRecord().cleared == true, "the confirmed record is cleared")
check(doc:PendingFor("red") == nil and not doc:IsPending("red", "m1"), "a cleared record is no longer pending")
doc:Write("red", lobby, function() end)
check(doc:IsPending("red", "m2") and not doc:IsPending("red", "m1") and not doc:IsPending("red", "") and not doc:IsPending("", "m2"), "pending is per match and needs both names")
check(doc:PendingFor("blue") == nil, "another player has none")
failReads = true
check(doc:PendingFor("red") == nil, "an unreadable record is nothing")
failReads = false
store[key] = nil

-- Presentation: war results show the strengths and the conclusion, lobby results only win or lose; never experience.
local view = doc:Present(doc:Compose("LOBBY", "m", "LOSE", nil))
check(view.title == "上一場對戰結果" and view.resultText == "失敗" and not view.war and #view.rows == 0 and view.conclusion == "", "lobby: only the result")
view = doc:Present(doc:Compose("WAR", "m", "WIN", receipt))
check(view.title == "上一場戰果" and view.resultText == "勝利" and view.war, "war title")
check(#view.rows == 2 and view.rows[1] == "<c>左營</c>　兵力 100 → 100", "the departure town's row")
check(view.rows[2] == "<c>鼓山</c>　兵力 100 → 80" and view.conclusion == "未易主", "the target row and the conclusion")
view = doc:Present(doc:Compose("WAR", "m", "DRAW", { origin = "zuoying", target = "gushan", status = "NO_CHANGE", conclusion = "未易主" }))
check(view.resultText == "平手" and #view.rows == 2 and view.rows[1] == "<c>左營</c>　兵力不變", "no change reads as unchanged")
view = doc:Present(doc:Compose("WAR", "m", "WIN", { origin = "zuoying", target = "nanzih", status = "NO_CHANGE", conclusion = "主城：兵力不變" }))
check(#view.rows == 0 and view.conclusion == "主城：兵力不變", "a capital as the loser has no rows")
view = doc:Present(doc:Compose("WAR", "m", "LOSE", { origin = "zuoying", target = "gushan", status = "EXEMPT", conclusion = "過期戰果：本場不計兵力" }))
check(#view.rows == 0 and view.conclusion == "過期戰果：本場不計兵力", "a stale result")
view = doc:Present(doc:Compose("WAR", "m", "LOSE", { origin = "zuoying", target = "gushan", status = "FAILED", conclusion = "戰果結算失敗，兵力未變動" }))
check(#view.rows == 0 and view.conclusion == "戰果結算失敗，兵力未變動", "a failed settlement")
view = doc:Present(doc:Compose("WAR", "m", "WIN", { origin = "zuoying", target = "gushan", status = "SAVED", conclusion = "奪城：鼓山 改為 紅方",
    originBefore = 100, originAfter = 100, targetBefore = 20, targetAfter = 100, capturedTown = "gushan", newOwner = "RED" }))
check(view.conclusion == "奪城：<c>鼓山</c> 改為 紅方" and view.rows[2] == "<c>鼓山</c>　兵力 20 → 100", "a captured town is highlighted in the conclusion")

-- Delivery in the static room: the window is pushed once per match, again after a reconnect, never in a match room.
local users, recovered, hinted, pushed, instance = {}, {}, {}, {}, false
local player = { PlayerComponent = { UserId = "red-user", ProfileCode = "red" } }
users[1] = player
_UserService = { UserEntities = { Values = users } }
_RoomService = { IsInstanceRoom = function() return instance end, StaticRoomKey = "static" }
_MatchFlow = {
    Player = function(_, userId) if userId == "red-user" then return player end end,
    Recover = function(_, userId) table.insert(recovered, userId) end,
    HintSettled = function(_, userId) table.insert(hinted, userId) end,
}
function doc:ReceiveAbsentResult(record, userId) table.insert(pushed, { record = record, userId = userId }) end
doc:OnBeginPlay()
doc:Write("red", war, function() end)
doc:Settled("red", "m1")
check(#pushed == 1 and pushed[1].userId == "red-user" and pushed[1].record.id == "m1", "an online absent player gets the window")
check(recovered[1] == "red-user" and hinted[1] == "red-user", "the ticket of that match is recovered (and ended) first, past the check interval")
doc:Settled("red", "m1")
check(#pushed == 1, "the same match is not pushed twice")
doc:HandleUserReconnectEvent({ UserId = "red-user" })
check(#pushed == 2, "a reconnected client gets the window again")
doc:Settled("blue", "m1")
check(#pushed == 2, "another profile is not delivered")
instance = true
doc:HandleUserReconnectEvent({ UserId = "red-user" })
check(#pushed == 2, "a match room never delivers")
instance = false
doc:Clear("red", "m1", function() end)
doc:HandleUserReconnectEvent({ UserId = "red-user" })
check(#pushed == 2, "a confirmed record is not delivered again")
doc:Write("red", lobby, function() end)
local recoveries = #recovered
doc:Deliver("red-user", false)
check(#pushed == 3 and pushed[3].record.id == "m2" and #recovered == recoveries, "a newer match is delivered; a login delivery does not recover again")
users[1] = nil
doc:Settled("red", "m2")
check(#pushed == 3, "nobody online: the record waits for the next login")
users[1] = player

-- Acknowledge: the sender's own record of that match is cleared.
senderUserId = "red-user"
doc:RequestAcknowledge("m2")
check(storedRecord().cleared == true and storedRecord().id == "m2", "pressing 確定 clears the record")
senderUserId = "stranger"
doc:Write("red", war, function() end)
doc:RequestAcknowledge("m1")
check(storedRecord().id == "m1" and storedRecord().cleared == nil, "somebody else cannot clear it")

-- Announce: a match room reaches the static room and every world instance; the static room delivers directly.
local sentRoom, sentInstances = {}, {}
AbsentResultEvent = function() return {} end
SendEventRequestResultCode = { OK = 0 }
_RoomService.RequestSendEventToRoomAsync = function(_, event, room, complete) table.insert(sentRoom, { event = event, room = room }); complete(0) end
_WorldInstanceService = { RequestSendEventToAllWorldInstancesAsync = function(_, event, complete) table.insert(sentInstances, event); complete(0) end }
instance = true
doc:Announce("red", "m1")
check(#sentRoom == 1 and sentRoom[1].room == "static" and sentRoom[1].event.Profile == "red" and sentRoom[1].event.MatchKey == "m1" and #sentInstances == 1, "a match room announces to the static room and to every instance")
instance = false
local before = #pushed
doc.ReceiveAbsentResult = function(self, record, userId) table.insert(pushed, { record = record, userId = userId }) end
doc._T.delivered = {}
doc:Announce("red", "m1")
check(#sentRoom == 1 and #sentInstances == 2 and #pushed == before + 1, "the static room delivers its own players directly")
doc:HandleRoomAbsentResult({ Profile = "red", MatchKey = "m1" })
doc:HandleInstanceAbsentResult({ Profile = "red", MatchKey = "m1" })
check(#pushed == before + 1, "a repeated hint repeats nothing")

print("[VRF][AbsentResult] record, presentation and delivery rules PASS checks=" .. tostring(checks))
