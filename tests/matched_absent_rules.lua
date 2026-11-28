-- Absent-side rules (ADR 0017, #120): run through matched_absent_local.cjs. Fake room, storage and clock; the production Lua bodies run unchanged.
local flow, handoff, status = _MatchFlow, _FormationHandoff, _MatchFlowState
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local clock = 1000
log = function() end
isvalid = function(value) return value ~= nil end
DateTime = { UtcNow = setmetatable({}, { __index = function(_, key) if key == "Elapsed" then return clock end end }) }
local room = { key = "room", instance = true }
_RoomService = { RoomKey = "room", IsInstanceRoom = function() return room.instance end }
local users = {}
_UserService = { UserEntities = { Values = users } }
_FactionWarAttack = { Combine = function(_, first, second) return nil end }
_FactionWarGuard = { Roster = function() return { { monsterId = "guard", x = 1, y = 1, level = 1 } } end, IsGuardProfile = function() return false end }
_FormationSchema = { IsFinite = function(_, value) return type(value) == "number" end }

local pairing = { key = "room", home = "red", away = "blue", homeAttempt = "rq-red", awayAttempt = "rq-blue", homeOrigin = "", awayOrigin = "" }
local function player(id, profile) return { CurrentMapName = "matchprobe", PlayerComponent = { UserId = id, ProfileCode = profile } } end
local function ticket(profile, state, match)
    return { data = { state = state or "IN_ROOM", matchKey = "room", profile = profile, attempt = "t-" .. profile, requestId = "rq-" .. profile,
        match = match or pairing, expires = 10 ^ 12, origin = "", target = "" } }
end
local function setRoom(entries)
    for index = #users, 1, -1 do users[index] = nil end
    flow._T = { records = {}, busy = {} }
    for _, entry in ipairs(entries) do
        table.insert(users, entry.player)
        if entry.ticket ~= nil then flow._T.records[entry.player.PlayerComponent.UserId] = entry.ticket end
    end
end
function flow:Player(userId) return { userId = userId } end
local red, blue = player("red-user", "red"), player("blue-user", "blue")

-- RoomBattleAdmission: only a room that waited out the entry time may field a missing human side.
setRoom({ { player = red, ticket = ticket("red") } })
check(flow:RoomBattleAdmission(false) == nil, "a lone human is not admitted before the entry time is over")
local lone = flow:RoomBattleAdmission(true)
check(lone ~= nil and lone.absent == "away" and lone.absentProfile == "blue" and lone.home == "red" and lone.away == "blue", "the missing away side is reported")
check(lone.homeTicket == "t-red" and lone.awayTicket == "" and lone.pairing == pairing and lone.guard == false, "only the present ticket is named")
setRoom({ { player = blue, ticket = ticket("blue") } })
local loneAway = flow:RoomBattleAdmission(true)
check(loneAway.absent == "home" and loneAway.absentProfile == "red" and loneAway.away == "blue" and loneAway.awayTicket == "t-blue", "the missing home side is reported")
setRoom({ { player = red, ticket = ticket("red") }, { player = blue, ticket = ticket("blue") } })
local both = flow:RoomBattleAdmission(true)
check(both ~= nil and both.absent == nil and both.homeTicket == "t-red" and both.awayTicket == "t-blue", "both sides present leaves nobody absent")
check(flow:RoomBattleAdmission(false) ~= nil, "both present is admitted the old way too")
setRoom({ { player = red, ticket = ticket("red", "TRANSFER") }, { player = blue, ticket = ticket("blue") } })
check(flow:RoomBattleAdmission(false) == nil, "an unready ticket still blocks the strict admission")
local unready = flow:RoomBattleAdmission(true)
check(unready.absent == "home" and unready.absentProfile == "red", "a present player whose ticket is not ready counts as absent")
setRoom({ { player = red }, { player = blue } })
check(flow:RoomBattleAdmission(true) == nil, "nobody with a ready ticket is nobody to play: no match")
setRoom({})
check(flow:RoomBattleAdmission(true) == nil, "an empty room admits nothing")
local guardMatch = { key = "room", home = "red", away = "guard:gushan", homeAttempt = "rq-red", awayAttempt = "guard", homeOrigin = "zuoying", awayOrigin = "gushan", guard = true }
setRoom({ { player = red, ticket = ticket("red", "IN_ROOM", guardMatch) } })
flow._T.records["red-user"].data.origin, flow._T.records["red-user"].data.target = "zuoying", "gushan"
local guard = flow:RoomBattleAdmission(true)
check(guard ~= nil and guard.guard == true and guard.absent == nil and guard.awayTown == "gushan", "a guard match never counts the guard as an absent human")
check(flow:RoomBattleAdmission(false) ~= nil, "the guard admission is the same with and without the flag")

-- FormationHandoff:LoadAbsentRoster copies the sealed roster once and never depends on the ticket afterwards.
local catalog = {}
_FormationService = { GetCatalog = function() return catalog end }
local stored, readCode = {}, 0
local decodes = {}
_FormationStorage = { Read = function(_, profile, key, complete)
    assert(key == handoff.StorageKey)
    complete(readCode, key, stored[profile])
end }
_HttpService = { JSONDecode = function(_, raw) return raw end }
function handoff:DecodeTransfer(transfer, given)
    assert(given == catalog)
    table.insert(decodes, transfer)
    return { units = { { monsterId = "slime", x = 1, y = 2, level = transfer.levelOf } } }
end
local function envelope(profile, state, matchKey, level)
    local data = { schema = 1, profile = profile, attempt = "t-" .. profile, requestId = "rq-" .. profile, state = state, started = 1, expires = 2,
        source = "s", matchKey = matchKey, match = pairing, origin = "", target = "" }
    if state ~= "RETURNED" and state ~= "CANCELLED" then
        data.transfer = { coordinateSchema = 2, saved = "", fixed = "", confirmedRaw = "", editSlot = 1, levelOf = level }
    end
    return data
end
handoff._T = {}
local function load(profile)
    local answer, called = nil, false
    handoff:LoadAbsentRoster(profile, pairing, function(units) answer, called = units, true end)
    return answer, called
end
stored.blue = envelope("blue", "TRANSFER", "room", 9)
local units, called = load("blue")
check(called and units ~= nil and #units == 1 and units[1].level == 9, "the sealed roster is copied with its frozen level")
stored.blue = envelope("blue", "TRANSFER", "other-room", 9)
units = load("blue")
check(units == nil, "a ticket sealed for another match is not fielded")
stored.blue = envelope("blue", "RETURNED", "room", 9)
units = load("blue")
check(units == nil, "an already closed ticket has no roster to copy")
stored.blue = nil
units = load("blue")
check(units == nil, "a missing record has no roster")
stored.blue = envelope("blue", "TRANSFER", "room", 9)
readCode = 1000004
units, called = load("blue")
check(called and units == nil, "a failed read reports no roster instead of hanging")
readCode = 0
handoff._T.ended = true
units, called = load("blue")
check(called and units == nil, "a room that is shutting down fields nothing")
local late
_FormationStorage = { Read = function(_, _, key, complete) late = function() complete(0, key, stored.blue) end end }
called = false
handoff._T.ended = false
handoff:LoadAbsentRoster("blue", pairing, function() called = true end)
handoff._T.ended = true
late()
check(not called, "a read that lands after the room ended answers nothing")
handoff._T.ended = false
_FormationStorage = { Read = function(_, profile, key, complete) assert(key == handoff.StorageKey); complete(readCode, key, stored[profile]) end }
-- The copy a room already holds survives the ticket being closed afterwards.
stored.blue = envelope("blue", "TRANSFER", "room", 9)
local copy = load("blue")
stored.blue = envelope("blue", "RETURNED", "room", 9)
check(copy ~= nil and copy[1].level == 9, "closing the absent ticket later cannot take the copy away")

-- MatchedBattle: the lone human waits, the room starts without the absent side, and a late opponent still starts at once.
local rosters = { ["t-red"] = { { monsterId = "tank", x = 1, y = 1, level = 3 } }, ["t-blue"] = { { monsterId = "mage", x = 2, y = 2, level = 5 } } }
function handoff:Roster(ticketId) return rosters[ticketId] end
local published = {}
function flow:PublishState(userId, code) table.insert(published, userId .. ":" .. code) end
local function newRoom()
    local battle = { Phase = "WAITING", MatchKey = "room" }
    function battle:InitializeMatchedBattle(key, home, away, homeUnits, awayUnits)
        self.started = { key = key, home = home, away = away, homeUnits = homeUnits, awayUnits = awayUnits }
        self.Phase = "BATTLE"
        return true
    end
    local map = { GetComponent = function(_, name) assert(name == "script.BattleSession"); return battle end }
    local match = setmetatable({ _T = {}, Entity = { CurrentMap = map } }, { __index = _MatchedBattle })
    match:OnBeginPlay()
    published = {}
    return match, battle
end
local function run(match, seconds)
    for _ = 1, math.floor(seconds / 0.5) do
        clock = clock + 500
        match:OnUpdate(0.5)
    end
end

stored.blue = envelope("blue", "TRANSFER", "room", 9)
setRoom({ { player = red, ticket = ticket("red") } })
local match, battle = newRoom()
run(match, 1)
check(battle.started == nil and match.WaitDeadline > clock and match.WaitDeadline <= clock + 30000, "the lone human waits with a deadline in the future")
local waiting = 0
for _, line in ipairs(published) do if line == "red-user:WAITING_OPPONENT" then waiting = waiting + 1 end end
check(waiting == 1, "the waiting human is told once")
local snapshot = { state = "WAITING", waitDeadline = match.WaitDeadline, entryDeadline = 1 }
local view = status:PresentMatch(snapshot, { now = clock })
check(view.text == "等待對手進入戰場…（30 秒）" or view.text == "等待對手進入戰場…（29 秒）", "the waiting text counts down: " .. tostring(view.text))
check(view.action == "" and view.label == "" and not view.enabled, "the waiting human has no button")
check(not status:EntryFailed(snapshot, clock + 10 ^ 9), "the entry time no longer fails a room that waits for the absent side")
stored.blue = envelope("blue", "RETURNED", "room", 9) -- the absent player presses Stop Entry while the room waits
run(match, 20)
check(battle.started == nil, "nothing starts before the entry time is over")
run(match, 10)
check(battle.started ~= nil, "the match starts without the absent side once the entry time is over")
check(battle.started.home == "red" and battle.started.away == "blue", "both profiles are fielded")
check(battle.started.homeUnits[1].monsterId == "tank" and battle.started.awayUnits[1].monsterId == "slime" and battle.started.awayUnits[1].level == 9,
    "the absent side fights with its frozen roster and level, although its ticket closed meanwhile")
check(match._T.started == true and not match.AdmissionFailed and match.WaitDeadline == 0, "started, not failed, nobody waits any more")
check(match._T.kind == "HUMAN", "an absent side is still a human match")
local sawStarted = false
for _, line in ipairs(published) do if line == "red-user:BATTLE_STARTED" then sawStarted = true end end
check(sawStarted, "the waiting human is told the battle started")

-- The absent side is the home side.
stored.red = envelope("red", "TRANSFER", "room", 4)
setRoom({ { player = blue, ticket = ticket("blue") } })
match, battle = newRoom()
run(match, 31)
check(battle.started ~= nil and battle.started.homeUnits[1].monsterId == "slime" and battle.started.homeUnits[1].level == 4 and battle.started.awayUnits[1].monsterId == "mage",
    "an absent home side is fielded from its own roster too")

-- A roster that cannot be copied never starts a match.
readCode = 1
setRoom({ { player = red, ticket = ticket("red") } })
match, battle = newRoom()
run(match, 31)
check(battle.started == nil and match.AdmissionFailed == true, "no roster to copy: the admission fails and nothing is deducted")
readCode = 0

-- The opponent arrives in time: the match starts at once, with both tickets' rosters.
stored.blue = envelope("blue", "TRANSFER", "room", 9)
setRoom({ { player = red, ticket = ticket("red") } })
match, battle = newRoom()
run(match, 5)
check(battle.started == nil and match.WaitDeadline > 0, "still waiting at five seconds")
setRoom({ { player = red, ticket = ticket("red") }, { player = blue, ticket = ticket("blue") } })
run(match, 1)
check(battle.started ~= nil and battle.started.awayUnits[1].monsterId == "mage" and match.WaitDeadline == 0, "a late opponent inside the entry time starts the match with his own roster")

-- Nobody here, or nobody who can play: no match, no failure to publish to anyone.
setRoom({})
match, battle = newRoom()
run(match, 40)
check(battle.started == nil and match._T.started == false, "an empty room never starts")
setRoom({ { player = red }, { player = blue } })
match, battle = newRoom()
run(match, 31)
check(battle.started == nil and match.AdmissionFailed == true, "players without a ready ticket make the admission fail")

-- A guard match starts at once, unchanged.
setRoom({ { player = red, ticket = ticket("red", "IN_ROOM", guardMatch) } })
flow._T.records["red-user"].data.origin, flow._T.records["red-user"].data.target = "zuoying", "gushan"
match, battle = newRoom()
run(match, 1)
check(battle.started ~= nil and battle.started.away == "guard:gushan" and match._T.kind == "GUARD" and match.WaitDeadline == 0, "the guard fight starts without waiting")

print("[VRF][MatchedAbsent] absent-side rules PASS checks=" .. tostring(checks))
