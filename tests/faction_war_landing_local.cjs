// Run: node tests/faction_war_landing_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// Lower only declarations; execute the production landing and town rule bodies with fake room/player I/O.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
function load(name) {
  return readFileSync(join(__dirname, `../RootDesk/MyDesk/Formations/${name}.mlua`), 'utf8')
    .replace(/\r\n/g, '\n')
    .replace(/^@Logic\nscript .* extends Logic\n/, `_${name} = { _T = {} }\n`)
    .replace(/^    @(ExecSpace|EventSender)\([^\n]*\)\n/gm, '')
    .replace(/^    property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
    .replace(/^    (?:method \w+|handler) (\w+)\(([^)]*)\)$/gm, (_, method, params) =>
      `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
    .replace(/\nend\s*$/, '\n');
}
process.stdout.write(`local ok, failure = xpcall(function()\n${load('FactionWarTownDocument')}\n${load('FactionWarLanding')}\n`);
process.stdout.write(String.raw`
log = function() end
log_error = error
isvalid = function(value) return value ~= nil end
DateTime = { UtcNow = { Elapsed = 0 } }
wait = function(seconds) coroutine.yield(seconds) end
local landing, doc = _FactionWarLanding, _FactionWarTownDocument
local user = "test"
local player, faction, home, board, offline, instance, owned, vacate
local moves, notices, reads, cancels, remembered, factionReplies, holdFaction, settling, moveFailed
local function reset(here, side, preferred)
    landing:OnBeginPlay()
    player = { CurrentMapName = here, PlayerComponent = { ProfileCode = "profile" } }
    faction, home, board = side or "BLUE", preferred or "gushan", doc:InitialTowns()
    offline, instance, owned, vacate = false, false, false, function() return true end
    moves, notices, factionReplies = {}, {}, {}
    reads, cancels, remembered, holdFaction, settling, moveFailed = 0, 0, 0, false, false, false
end
_UserService = { GetUserEntityByUserId = function(_, id) if id == user then return player end end }
_RoomService = { IsInstanceRoom = function() return instance end }
_FormationHandoff = { IsLockedForUser = function() return owned end }
_MatchFlow = {
    IsOffline = function() return offline end,
    Vacate = function() cancels = cancels + 1; return vacate() end
}
_FactionWar = {
    ReadFaction = function(_, _, done)
        if holdFaction then table.insert(factionReplies, done) else done(faction) end
    end,
    ReadTown = function(_, _, done) done(home) end,
    Move = function(_, target, town)
        assert(not instance and target == player)
        if moveFailed then return false end
        table.insert(moves, town)
        player.CurrentMapName = town
        return true
    end,
    Remember = function() remembered = remembered + 1 end,
    ReceiveTownNotice = function(_, town, text, id)
        assert(town == player.CurrentMapName and id == user)
        table.insert(notices, text)
    end
}
function doc:Read(done) reads = reads + 1; done(board) end
function doc:IsSettling() return settling end
local function reply()
    table.remove(factionReplies, 1)(faction)
end
local function check(snapshot)
    landing:Judge(user, { kind = "CHECK", town = "gushan", board = snapshot })
end
local function login(cause, held)
    return landing:Judge(user, { kind = "LOGIN", cause = cause or "enter", owned = held == true })
end
local function battle(kind, move, origin, matchKey)
    return landing:Judge(user, { kind = kind, origin = origin or "zuoying", matchKey = matchKey or "capture", move = move })
end
local function captured()
    board.gushan.owner, board.gushan.e = "RED", 1
    board.settled = { { k = "capture", w = "zuoying", l = "gushan", s = 100, o = "RED" } }
end
local function advance(co)
    local ok, value = coroutine.resume(co)
    assert(ok, debug.traceback(co, tostring(value)))
    return value
end

reset("gushan")
local friendly = board
board = doc:InitialTowns(); captured()
holdFaction = true
check(friendly)
check(board)
assert(landing:IsJudging(user) and #factionReplies == 1 and #moves == 0)
reply()
assert(reads == 1 and #factionReplies == 1 and #moves == 0, "queued check must read anew before judging")
reply()
assert(not landing:IsJudging(user) and cancels == 1 and reads == 2 and moves[1] == "yancheng" and #notices == 1)

reset("gushan"); captured()
local fallen = board
vacate = function() board = doc:InitialTowns(); board.gushan.e = 2; return true end
check(fallen)
assert(cancels == 1 and reads == 1 and #moves == 0, "a town retaken during cancellation keeps its player")
vacate = function() offline = true; return true end
check(fallen)
assert(cancels == 2 and #moves == 0, "offline players are not moved")

reset("gushan"); captured()
vacate = function() return false end
check(board)
assert(cancels == 1 and reads == 0 and #moves == 0, "a matched ticket is not evicted")
vacate = function() board = nil; return true end
check(board)
assert(reads == 1 and #moves == 0, "an unreadable recheck cannot move a player")

reset("gushan"); captured()
holdFaction = true
check(board)
DateTime.UtcNow.Elapsed = DateTime.UtcNow.Elapsed + 31000
check(board)
reply()
assert(landing:IsJudging(user) and #moves == 0, "an expired callback cannot clear the new slot or move the player")
reply()
assert(not landing:IsJudging(user) and #moves == 1)

reset("gushan"); captured()
holdFaction = true
check(board)
landing:HandleUserLeaveEvent({ UserId = user })
reply()
assert(not landing:IsJudging(user) and #moves == 0)

reset("formationlobby")
assert(login() and moves[1] == "gushan" and #notices == 1)
reset("formationlobby"); captured()
assert(login() and moves[1] == "yancheng")
reset("formationlobby")
assert(not login("enter", true) and not login("reconnect") and reads == 0 and #moves == 0)
owned = true
assert(not login() and reads == 0)
reset("gushan"); captured()
assert(not login("reconnect", true) and remembered == 1 and cancels == 0, "remember the arrival, but leave ticket-owned players alone")
local loginThread = coroutine.create(function() return login("reconnect") end)
holdFaction = true
assert(advance(loginThread) == 0.1)
assert(not login() and #factionReplies == 1, "a second login must not run")
check(board)
assert(#factionReplies == 1, "sweep and login share a slot")
reply()
assert(advance(loginThread) == true and not landing:IsJudging(user) and #moves == 1)

reset("formationlobby", "RED"); captured()
assert(battle("RESTORE") and moves[1] == "zuoying" and reads == 1, "a capturer restored from the lobby returns to origin")
assert(notices[1] == "上一場戰果：奪下鼓山。")
assert(not login() and #moves == 1 and #notices == 1, "login following restore does not replay the battle notice")
board = nil
local priorReads = reads
assert(not battle("RESTORE") and #moves == 1 and #notices == 1 and reads == priorReads + 2,
    "unreadable restore leaves the player in place after two attempts, without a notice")

reset("zuoying", "RED"); captured()
holdFaction = true
landing:Judge(user, { kind = "CHECK", town = "zuoying", board = board })
local restore = coroutine.create(function() return battle("RESTORE") end)
assert(advance(restore) == 0.1, "restore waits for the sweep")
holdFaction = false; reply()
assert(advance(restore) == false and not landing:IsJudging(user) and #moves == 0)
assert(#notices == 1 and notices[1] == "上一場戰果：奪下鼓山。", "already at origin: notify once without moving")

reset("matchprobe", "RED"); captured()
instance, settling = true, true
local transferred, transferCount = nil, 0
local function transfer(town)
    transferred = town
    transferCount = transferCount + 1
    return true
end
local returning = coroutine.create(function() return battle("RETURN", transfer) end)
assert(advance(returning) == 0.1 and transferred == nil and reads == 0)
assert(not battle("RETURN", transfer) and transferCount == 0)
settling = false
assert(advance(returning) == true and transferred == "zuoying" and #moves == 0 and #notices == 0)
board.gushan.owner = "BLUE"
assert(battle("RETURN", transfer) and transferred == "zuoying", "losing the captured town does not change the landing")
board.zuoying.owner = "BLUE"
assert(battle("RETURN", transfer) and transferred == "nanzih", "ownership of the origin is checked anew on return")
board = nil
assert(battle("RETURN", transfer) and transferred == "zuoying", "unreadable cross-room return uses its departure town")
assert(not battle("RESTORE") and not login() and #moves == 0)

-- The defender lost its origin in this very match; ordinary return is already at the capital when restore runs.
reset("matchprobe", "BLUE"); captured()
instance = true
assert(battle("RETURN", transfer, "gushan") and transferred == "yancheng" and #notices == 0)
instance = false
player.CurrentMapName = transferred
assert(not battle("RESTORE", nil, "gushan") and #moves == 0)
assert(#notices == 1 and notices[1]:find("鼓山已失守，已撤回主城。", 1, true))
assert(not login("reconnect") and #notices == 1)

-- A failed admission can restore a ticket in its still-friendly origin with no recorded battle.
reset("zuoying", "RED")
assert(not battle("RESTORE", nil, "zuoying", "unplayed") and #moves == 0 and #notices == 0,
    "an in-place restore without a record or a lost origin does not announce a battle")

-- The capture history and a later loss of the origin can both be true; recovering a stale ticket reports both.
reset("formationlobby", "RED"); captured()
board.zuoying.owner = "BLUE"
moveFailed = true
assert(not battle("RESTORE") and #notices == 0, "do not send a notice for a failed move")
moveFailed = false
assert(battle("RESTORE") and moves[1] == "nanzih")
assert(#notices == 1 and notices[1] == "左營已失守，已撤回主城。上一場戰果：奪下鼓山。")

-- The stale match was EXEMPT and has no stored outcome; the other match's capture does not determine this landing or notice.
reset("matchprobe", "BLUE"); captured()
instance = true
assert(battle("RETURN", transfer, "gushan", "exempt") and transferred == "yancheng")
instance = false
player.CurrentMapName = "formationlobby"
assert(battle("RESTORE", nil, "gushan", "exempt") and moves[1] == "yancheng")
assert(#notices == 1 and notices[1] == "鼓山已失守，已撤回主城。上一場對戰已結束。")

reset("matchprobe", "RED"); captured()
instance, settling = true, true
local late = coroutine.create(function() return battle("RETURN", function() error("moved an offline player") end) end)
assert(advance(late) == 0.1)
offline, settling = true, false
assert(advance(late) == false)
print("[VRF][FactionWarLanding] local placement scenarios PASS")
end, debug.traceback)
if not ok then io.stderr:write(failure, "\n"); os.exit(1) end
`);
