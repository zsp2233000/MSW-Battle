-- Attack panel (#117) and team preview (#118) rules: run through siege_panels_local.cjs. Fakes only; the production bodies run unchanged.
local doc, attack, map, team, ui = _FactionWarTownDocument, _FactionWarAttack, _FactionWarMap, _FactionWarTeam, _FactionWarUI
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

log = function() end
isvalid = function(value) return value ~= nil end
DateTime = { UtcNow = { Elapsed = 1000 } }
_WorldInstanceService = { WorldInstanceId = "instance" }
_RoomService = { IsInstanceRoom = function() return false end }

-- A board: Zuoying (RED) is attacked from, Gushan (BLUE) is hurt, Nanzih and Yancheng are the capitals.
local board = doc:InitialTowns()
board.gushan.strength = 55
local gates = { ["zuoying>nanzih"] = true, ["zuoying>gushan"] = true, ["gushan>zuoying"] = true, ["gushan>yancheng"] = true }
local reads = 0
doc.Read = function(_, complete) reads = reads + 1; complete(board) end
local factions = { red = "RED", blue = "BLUE" }
local players = {}
local function player(id, profile, town) players[id] = { CurrentMapName = town, PlayerComponent = { UserId = id, ProfileCode = profile } } return players[id] end
_UserService = { GetUserEntityByUserId = function(_, id) return players[id] end }
_FactionWar = {
    IsTown = function(_, name) return doc:IsTown(name) end,
    FindGate = function(_, origin, destination) return gates[origin .. ">" .. destination] and { gate = destination } or nil end,
    StillIn = function(_, user, id, town) return players[id] == user and user.CurrentMapName == town end,
    ReadFaction = function(_, profile, complete) complete(factions[profile]) end,
}

-- #117: the answer to the NPC carries every target's strength and capital flag and the departure town, from one board read.
local list = attack:Targets("zuoying", "RED", board)
check(#list == 1 and list[1].town == "gushan", "only an adjacent enemy town is a target")
check(list[1].strength == 55 and list[1].owner == "BLUE" and list[1].capital == false and list[1].name == "鼓山", "a target carries its strength, owner and name")
local taken = doc:InitialTowns()
taken.gushan.owner = "RED"
local capitalTargets = attack:Targets("gushan", "RED", taken)
check(#capitalTargets == 1 and capitalTargets[1].town == "yancheng" and capitalTargets[1].capital == true and capitalTargets[1].strength == 100, "a capital target is flagged")
local header = attack:Header("zuoying", "RED", board)
check(header.town == "zuoying" and header.name == "左營" and header.strength == 100 and header.owner == "RED" and header.faction == "RED" and header.capital == false, "the departure town header")

local answers = {}
function attack:ReceiveOptions(town, options, status, head, userId) table.insert(answers, { town = town, options = options, status = status, header = head, userId = userId }) end
local watched = {}
local realWatch = _FactionWarMap.WatchPanel
_FactionWarMap.WatchPanel = function(_, userId, user) watched[userId] = user end
local engaged, target = false, ""
_MatchFlow = { StateForUser = function() return engaged and "QUEUED" or "IDLE" end, TargetForUser = function() return target end }
_FormationHandoff = { IsLockedForUser = function() return false end }
attack._T.reading = {}
local red = player("red-user", "red", "zuoying")
reads = 0
attack:OptionsFor("red-user")
local answer = answers[#answers]
check(reads == 1, "one board read answers the whole panel; the header and the strengths add none")
check(answer.status == "READY" and #answer.options == 1 and answer.header.strength == 100 and answer.options[1].strength == 55, "the options reply carries the numbers")
check(answer.header.target == nil and watched["red-user"] == red, "a ready panel is followed for board pushes")
engaged, target = true, "gushan"
attack:OptionsFor("red-user")
answer = answers[#answers]
check(answer.status == "ENGAGED" and answer.header.target == "gushan" and #answer.options == 1, "a queued player's panel names the town being attacked")
check(reads == 2, "still one read per answer")
watched = {}
factions.red = nil
attack:OptionsFor("red-user")
check(answers[#answers].status == "UNAVAILABLE" and next(answers[#answers].header) == nil and next(watched) == nil, "an unreadable answer is not watched")
factions.red = "RED"
engaged = false
board.zuoying.owner = "BLUE"
_FactionWarLanding = { Judge = function() return false end }
attack:OptionsFor("red-user")
check(answers[#answers].status == "NOT_OWNED" and next(watched) == nil, "a fallen departure town gets no live panel")
board.zuoying.owner = "RED"

_FactionWarMap.WatchPanel = realWatch
-- #117: the panel's viewers get the strengths when a board change arrives; the map's own viewers are untouched.
local mapSent, panelSent = {}, {}
function map:ReceiveBoard(towns, links, userId) table.insert(mapSent, userId) end
function map:ReceivePanelBoard(towns, userId) table.insert(panelSent, { userId = userId, towns = towns }) end
function map:ReceiveFaction() end
function map:ReceiveUnavailable() end
local function freshMap()
    map._T = { viewers = {}, panelViewers = {}, waiting = {}, reading = false, readStarted = 0, inflight = {}, again = false, signature = "", links = nil }
    mapSent, panelSent = {}, {}
end
freshMap()
local blue = player("blue-user", "blue", "gushan")
map:WatchPanel("red-user", red)
check(map._T.panelViewers["red-user"] == red and next(map._T.viewers) == nil, "the panel viewer is not a map viewer")
map:WatchPanel("nobody", { CurrentMapName = "zuoying", PlayerComponent = {} })
check(map._T.panelViewers["nobody"] == nil, "a player the server does not know is not watched")
reads = 0
map:BoardChanged("room")
check(reads == 1 and #panelSent == 1 and panelSent[1].userId == "red-user" and #mapSent == 0, "a change with only the panel open still reads once and pushes to the panel alone")
local pushed = {}
for _, town in ipairs(panelSent[1].towns) do pushed[town.id] = town end
check(pushed.gushan.strength == 55 and pushed.zuoying.owner == "RED" and pushed.nanzih.capital == true, "the pushed board holds owner and strength per town")
map:BoardChanged("room")
check(#panelSent == 1, "an unchanged board is not pushed again")
board.gushan.strength = 35
map:BoardChanged("room")
check(#panelSent == 2, "a changed strength is pushed")
local latest = {}
for _, town in ipairs(panelSent[#panelSent].towns) do latest[town.id] = town end
check(latest.gushan.strength == 35, "the new strength arrives")
players["red-user"].CurrentMapName = "formationlobby"
board.gushan.strength = 15
map:BoardChanged("room")
check(map._T.panelViewers["red-user"] == nil and #panelSent == 2, "a player who left the town is dropped, nothing is pushed to them")
players["red-user"].CurrentMapName = "zuoying"
map:WatchPanel("red-user", red)
senderUserId = "red-user"
map:RequestPanelClose()
check(map._T.panelViewers["red-user"] == nil, "closing the panel ends the push")
map:WatchPanel("red-user", red)
map:HandleUserLeaveEvent({ UserId = "red-user" })
check(map._T.panelViewers["red-user"] == nil, "leaving the room ends it too")
check(next(map._T.panelViewers) == nil, "nothing is left subscribed")
-- Map viewers keep their old behaviour.
freshMap()
map._T.viewers["red-user"] = red
map._T.panelViewers["blue-user"] = blue
board.gushan.strength = 45
map:BoardChanged("room")
check(#mapSent == 1 and mapSent[1] == "red-user" and #panelSent == 1 and panelSent[1].userId == "blue-user", "both kinds of viewers get their own kind of push")
freshMap()
reads = 0
map:BoardChanged("room")
check(reads == 0, "nobody looking means nothing to read")

-- #117: the client panel's words and bars.
check(ui:StrengthText(80) == "兵力 80 / 100" and ui:StrengthText(nil) == "兵力 —", "the strength line")
check(ui:StrengthRatio(80) == 0.8 and ui:StrengthRatio(250) == 1 and ui:StrengthRatio(-3) == 0 and ui:StrengthRatio(nil) == 0, "the bar fill is clamped")
function ui:HighlightedTownName(town) return "<c>" .. doc.TownNames[town] .. "</c>" end
check(ui:AttackStatusText("READY", {}, 2) == "選擇要進攻的城鎮", "ready")
check(ui:AttackStatusText("READY", {}, 0) == "目前沒有可進攻的相鄰敵城", "no adjacent enemy town")
check(ui:AttackStatusText("ENGAGED", { target = "gushan" }, 2) == "目前正在進攻 <c>鼓山</c>，要改變目標請先取消配對", "a queued player is told which town is being attacked")
check(ui:AttackStatusText("ENGAGED", {}, 2) == "已在配對中，請先取消目前的配對", "queued without a known target")
check(ui:AttackStatusText("NOT_OWNED", {}, 0) == "這座城已不屬於你的陣營" and ui:AttackStatusText("UNAVAILABLE", {}, 0) == "暫時無法讀取國戰資料，請再試一次", "the failure lines")
for _, text in ipairs({ ui:AttackStatusText("ENGAGED", { target = "gushan" }, 2), ui:AttackStatusText("READY", {}, 2) }) do
    check(not string.find(text, "編隊", 1, true), "the glossary says 隊伍, never 編隊")
end

-- #118: the team preview. Server side: the ticket's frozen team, never the current one.
local roster = nil
_FormationHandoff = { Roster = function(_, ticketId) return ticketId == "t-1" and roster or nil end }
local state, ticketId = "IDLE", ""
_MatchFlow = { StateForUser = function() return state end, TicketIdForUser = function() return ticketId end }
local none = team:TicketTeam("red-user")
check(none.status == "NONE" and #none.units == 0, "no ticket: the client shows its own saved team")
state, ticketId = "QUEUED", "t-1"
roster = { { monsterId = "monster_tank", x = -3.25, y = -1.25, level = 3 }, { monsterId = "monster_shooter", x = -4, y = 0.5, level = 7, extra = "dropped" } }
local frozen = team:TicketTeam("red-user")
check(frozen.status == "TICKET" and #frozen.units == 2 and frozen.units[1].level == 3 and frozen.units[2].level == 7 and frozen.units[2].extra == nil, "the ticket's units and frozen levels")
state, ticketId = "TRANSFER", "gone"
check(team:TicketTeam("red-user").status == "UNAVAILABLE", "a ticket whose roster cannot be read says so")
state, ticketId = "QUEUED", "t-1"
roster = {}
for index = 1, 9 do roster[index] = { monsterId = "m" .. index, x = index, y = 0, level = 1 } end
check(#team:TicketTeam("red-user").units == 6, "never more than six units")
local replies = {}
function team:ReceiveTeam(status, units, userId) table.insert(replies, { status = status, units = units, userId = userId }) end
players["red-user"].CurrentMapName = "formationlobby"
team:TeamFor("red-user")
check(#replies == 0, "the preview is answered only inside a town")
players["red-user"].CurrentMapName = "zuoying"
team:TeamFor("red-user")
check(#replies == 1 and replies[1].userId == "red-user", "answered for a player standing in a town")
team:TeamFor("stranger")
check(#replies == 1, "an unknown caller gets nothing")

-- Client side: what the preview shows.
_FormationSchema = { IsLoadConfirmed = function(_, loadState) return loadState == "READY" or loadState == "NEW" end }
local snapshot = {
    loadState = "READY", levelLoadState = "READY",
    options = { { monsterId = "monster_tank", level = 9 }, { monsterId = "monster_shooter", level = 4 } },
    saved = { activeSlot = 2, slots = { ["2"] = { units = { { monsterId = "monster_tank", x = -3.25, y = -1.25 }, { monsterId = "monster_shooter", x = -4, y = 0.5 } } } } },
}
local view = team:Present({ status = "NONE", units = {} }, snapshot)
check(view.title == "出戰隊伍" and view.hint == "要更換出戰隊伍，請找大廳 NPC" and #view.units == 2, "no queue: the saved active team with the NPC hint")
check(view.units[1].level == 9 and view.units[2].level == 4, "with the levels the client knows now")
view = team:Present({ status = "TICKET", units = { { monsterId = "monster_tank", x = -3.25, y = -1.25, level = 3 } } }, snapshot)
check(view.title == "本局隊伍" and view.hint == "" and #view.units == 1 and view.units[1].level == 3, "a queue: the ticket's team and the level frozen at queueing, not Lv 9")
snapshot.saved.activeSlot = 0
view = team:Present({ status = "NONE", units = {} }, snapshot)
check(view.empty == "尚未選定出戰隊伍" and #view.units == 0 and view.hint ~= "", "no active team says so")
snapshot.saved.activeSlot = 2
snapshot.loadState = "LOADING"
check(team:Present({ status = "NONE", units = {} }, snapshot).empty == "正在讀取隊伍資料…", "still loading")
snapshot.loadState = "ERROR"
check(string.find(team:Present({ status = "NONE", units = {} }, snapshot).empty, "失敗", 1, true), "a failed load")
snapshot.loadState, snapshot.levelLoadState = "READY", "LOADING"
check(team:Present({ status = "NONE", units = {} }, snapshot).units[1].level == nil, "levels that are not loaded are unknown, not Lv 1")
check(team:Present(nil, snapshot).empty == "正在讀取隊伍…", "before the server answers")
check(team:Present({ status = "UNAVAILABLE", units = {} }, snapshot).title == "本局隊伍", "an unreadable ticket is still about the ticket")
for _, reply in ipairs({ { status = "NONE", units = {} }, { status = "TICKET", units = {} }, { status = "UNAVAILABLE", units = {} } }) do
    local shown = team:Present(reply, snapshot)
    check(not string.find(shown.title .. shown.hint .. shown.empty, "編隊", 1, true), "no 編隊 anywhere in the preview")
end
-- Layout keeps the stance and never lets markers overlap.
local single = team:Layout({ { x = -3, y = 1 } }, 740, 380)
check(single.places[1].x == 0 and single.places[1].y == 8 and single.portrait == team.MaxPortrait, "one unit sits in the middle of the field")
local many = {}
for index = 1, 6 do many[index] = { x = -3.25 - (index - 1) * 0.75, y = -1.25 + ((index % 2) * 0.75) } end
local layout = team:Layout(many, 740, 380)
check(#layout.places == 6 and layout.portrait <= team.MaxPortrait and layout.portrait > 0, "six units fit")
for index = 2, 6 do check(layout.places[index].x < layout.places[index - 1].x, "the stance order is kept") end
local minX, maxX = math.huge, -math.huge
for _, place in ipairs(layout.places) do minX, maxX = math.min(minX, place.x), math.max(maxX, place.x) end
check(math.abs(minX + maxX) < 0.001 and maxX - minX <= 740 - team.FieldPadX + 0.001, "centered and inside the field")

print("[VRF][SiegePanels] attack panel and team preview rules PASS checks=" .. tostring(checks))
