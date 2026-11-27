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

-- A board: Zuoying (A) is attacked from, Gushan (B) is hurt, Nanzih and Yancheng are the capitals.
local board = doc:InitialTowns()
board.gushan.strength = 55
local gates = { ["zuoying>nanzih"] = true, ["zuoying>gushan"] = true, ["gushan>zuoying"] = true, ["gushan>yancheng"] = true }
local reads = 0
doc.Read = function(_, complete) reads = reads + 1; complete(board) end
local factions = { red = "A", blue = "B" }
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
local list = attack:Targets("zuoying", "A", board)
check(#list == 1 and list[1].town == "gushan", "only an adjacent enemy town is a target")
check(list[1].strength == 55 and list[1].owner == "B" and list[1].capital == false and list[1].name == "鼓山", "a target carries its strength, owner and name")
local taken = doc:InitialTowns()
taken.gushan.owner = "A"
local capitalTargets = attack:Targets("gushan", "A", taken)
check(#capitalTargets == 1 and capitalTargets[1].town == "yancheng" and capitalTargets[1].capital == true and capitalTargets[1].strength == 100, "a capital target is flagged")
local header = attack:Header("zuoying", "A", board)
check(header.town == "zuoying" and header.name == "左營" and header.strength == 100 and header.owner == "A" and header.faction == "A" and header.capital == false, "the departure town header")

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
factions.red = "A"
engaged = false
board.zuoying.owner = "B"
_FactionWarLanding = { Judge = function() return false end }
attack:OptionsFor("red-user")
check(answers[#answers].status == "NOT_OWNED" and next(watched) == nil, "a fallen departure town gets no live panel")
board.zuoying.owner = "A"

_FactionWarMap.WatchPanel = realWatch
-- #117: the panel's viewers get the strengths when a board change arrives; the map's own viewers are untouched.
local mapSent, panelSent = {}, {}
function map:ReceiveBoard(towns, links, userId) table.insert(mapSent, userId) end
function map:ReceivePanelBoard(towns, userId) table.insert(panelSent, { userId = userId, towns = towns }) end
function map:ReceiveFaction() end
function map:ReceiveUnavailable() end
local function freshMap()
    map._T = { viewers = {}, panelViewers = {}, siegeViewers = {}, waiting = {}, reading = false, readStarted = 0, inflight = {}, again = false, signature = "", links = nil }
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
check(pushed.gushan.strength == 55 and pushed.zuoying.owner == "A" and pushed.nanzih.capital == true, "the pushed board holds owner and strength per town")
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

-- #123: the siege panel follows the board for as long as it shows, as a viewer of its own kind (never the attack panel's, never the map's).
freshMap()
local siegeSent = {}
function map:ReceiveSiegeBoard(towns, userId) table.insert(siegeSent, { userId = userId, towns = towns }) end
senderUserId = "stranger"
map:RequestSiegeOpen()
check(next(map._T.siegeViewers) == nil and #siegeSent == 0, "an unknown sender is not watched")
senderUserId = "red-user"
reads = 0
board.gushan.strength = 55
map:RequestSiegeOpen()
check(map._T.siegeViewers["red-user"] == players["red-user"] and next(map._T.viewers) == nil and next(map._T.panelViewers) == nil, "the siege viewer is its own kind")
check(reads == 1 and #siegeSent == 1 and siegeSent[1].userId == "red-user" and #panelSent == 0 and #mapSent == 0, "opening reads the board once and answers the opener alone")
local seen = {}
for _, town in ipairs(siegeSent[1].towns) do seen[town.id] = town end
check(seen.gushan.strength == 55 and seen.zuoying.owner == "A" and seen.nanzih.capital == true, "owner and strength per town reach the siege panel")
siegeSent = {}
reads = 0
board.gushan.strength = 35
map:BoardChanged("room")
check(reads == 1 and #siegeSent == 1 and #panelSent == 0 and #mapSent == 0, "a change with only the siege panel showing reads once and pushes to it alone")
map:BoardChanged("room")
check(#siegeSent == 1, "an unchanged board is not pushed again")
players["red-user"].CurrentMapName = "formationlobby"
board.gushan.strength = 15
map:BoardChanged("room")
check(map._T.siegeViewers["red-user"] == nil and #siegeSent == 1, "a player who left the town is dropped without a push")
players["red-user"].CurrentMapName = "zuoying"
map:RequestSiegeOpen()
map:RequestSiegeClose()
check(map._T.siegeViewers["red-user"] == nil, "hiding the panel ends the push")
map:RequestSiegeOpen()
map:HandleUserLeaveEvent({ UserId = "red-user" })
check(next(map._T.siegeViewers) == nil, "leaving the room ends it too")
freshMap()
reads = 0
map:BoardChanged("room")
check(reads == 0, "nobody looking at all means nothing to read")
-- The attack panel and the siege panel are open at the same time for a queued player; closing one keeps the other.
freshMap()
map._T.panelViewers["red-user"] = red
map._T.siegeViewers["red-user"] = red
map:RequestPanelClose()
check(map._T.siegeViewers["red-user"] == red, "closing the attack panel keeps the siege panel following")
map._T.panelViewers["red-user"] = red
map:RequestSiegeClose()
check(map._T.panelViewers["red-user"] == red, "closing the siege panel keeps the attack panel following")

-- #123: what the siege card says, from the same pre-battle rules as the lobby.
local clock = 500000
local function queued(fields)
    local value = { state = "QUEUED", reasonCode = "", started = clock - 8000, players = 0, busy = false, summary = "", attempt = "a",
        origin = "zuoying", target = "gushan", guardAt = clock + 2000, opponentFound = false }
    for key, entry in pairs(fields or {}) do value[key] = entry end
    return value
end
local figures = { zuoying = 80, gushan = 55 }
local function card(fields, strengths, pendingAction)
    return ui:SiegeView(queued(fields), { origin = "zuoying", now = clock, strengths = strengths or figures, pendingAction = pendingAction })
end
local queuing = card()
check(queuing.origin == "<c>左營</c> 兵力 80" and queuing.target == "<c>鼓山</c> 兵力 55", "line one: each town with its strength")
check(queuing.status == "配對中 · 倒數 2 秒" and queuing.label == "取消配對" and queuing.action == "CANCEL" and queuing.enabled, "line two and the button while waiting")
local unknown = card({}, {})
check(unknown.origin == "<c>左營</c> 兵力 —" and unknown.target == "<c>鼓山</c> 兵力 —", "a strength not heard yet is a dash, never 0")
local live = card({}, { zuoying = 60, gushan = 0 })
check(live.origin == "<c>左營</c> 兵力 60" and live.target == "<c>鼓山</c> 兵力 0", "the numbers follow the board, a real 0 included")
local fired = card({ guardAt = clock })
check(fired.status == "即將開戰…" and fired.action == "" and fired.label == "", "countdown at zero: no button")
local matched = card({ state = "SAVING", opponentFound = true })
check(matched.status == "配對成功，正在進入戰場" and matched.action == "" and not matched.enabled, "a pairing cannot be cancelled")
local failed = card({ state = "SAVING", opponentFound = true, reasonCode = "HANDOFF_SEAL_FAILED" })
check(failed.status == "入場失敗" and failed.label == "停止入場" and failed.action == "RETURN" and failed.enabled, "a failed entry offers Stop Entry")
local cancelling = card({}, nil, "CANCEL")
check(cancelling.status == "正在取消配對…" and cancelling.action == "" and not cancelling.enabled, "cancelling")
local waiting = card({ state = "WAITING", opponentFound = true, waitDeadline = clock + 9000, entryDeadline = clock + 9000 })
check(waiting.status == "等待對手進入戰場…（9 秒）" and waiting.action == "", "waiting for the absent side")
-- The glossary: the card never says who the opponent is, never 守衛, never 編隊.
for _, shown in ipairs({ queuing, fired, matched, failed, cancelling, waiting, card({ state = "QUEUE_ERROR" }) }) do
    local text = shown.origin .. shown.target .. shown.status .. shown.label
    check(not string.find(text, "守衛", 1, true) and not string.find(text, "編隊", 1, true) and not string.find(text, "取消入場", 1, true), "no 守衛, 編隊 or 取消入場 on the card")
end

-- #123: the card keeps the board it heard, and forgets it when it hides.
ui._T.siegeStrengths = nil
ui._T.siegeShown = false
ui:ShowSiegeBoard({ { id = "zuoying", owner = "A", strength = 70 }, { id = "gushan", owner = "B", strength = 40 } })
check(ui._T.siegeStrengths == nil, "a board that arrives after the card hid is stale")
ui._T.siegeShown = true
ui:ShowSiegeBoard({ { id = "zuoying", owner = "A", strength = 70 }, { id = "gushan", owner = "B", strength = 40 } })
check(ui._T.siegeStrengths.zuoying == 70 and ui._T.siegeStrengths.gushan == 40, "a pushed board is kept by town")
-- Following: ask when the card starts to show, again only while nothing has arrived, tell the server when it hides.
local asks, closes = 0, 0
_FactionWarMap = { RequestSiegeOpen = function() asks = asks + 1 end, RequestSiegeClose = function() closes = closes + 1 end }
DateTime.UtcNow.Elapsed = 1000000
ui._T.siegeShown, ui._T.siegeStrengths, ui._T.siegeAsked, ui._T.shownText = false, nil, 0, {}
ui:FollowSiege(true)
check(asks == 1 and ui._T.siegeShown, "showing the card asks the server for the board")
ui:FollowSiege(true)
check(asks == 1, "once is enough while it is within ten seconds")
DateTime.UtcNow.Elapsed = 1011000
ui:FollowSiege(true)
check(asks == 2, "no strength heard after ten seconds: ask again")
ui._T.siegeStrengths = { zuoying = 80 }
DateTime.UtcNow.Elapsed = 1030000
ui:FollowSiege(true)
check(asks == 2, "a heard board needs no new ask")
ui:FollowSiege(false)
check(closes == 1 and not ui._T.siegeShown and ui._T.siegeStrengths == nil, "hiding the card ends the push and forgets the numbers")
ui:FollowSiege(false)
check(closes == 1, "hiding twice tells the server once")

-- #123: the card as a whole, drawn against fake nodes: where it shows, what it writes, what its button sends.
local nodes = {}
local function fakeNode(path)
    if nodes[path] == nil then
        local entry = { Enable = false, writes = 0, ButtonComponent = { Enable = false }, SetEnable = function(self, value) self.Enable = value end }
        local store = { Text = "" }
        entry.TextGUIRendererComponent = setmetatable({}, { __index = store, __newindex = function(_, key, value)
            if key == "Text" then entry.writes = entry.writes + 1 end
            store[key] = value
        end })
        nodes[path] = entry
    end
    return nodes[path]
end
_EntityService = { GetEntityByPath = function(_, path) return fakeNode((string.gsub(path, "^/ui/FactionWarGroup/", ""))) end }
local townStatusAsks = 0
_FactionWar.RequestTownStatus = function() townStatusAsks = townStatusAsks + 1 end
local sent = {}
_MatchFlow = { RequestCancel = function(_, attempt) table.insert(sent, "CANCEL:" .. tostring(attempt)) end, RequestReturn = function(_, attempt) table.insert(sent, "RETURN:" .. tostring(attempt)) end }
_UserService.LocalPlayer = { CurrentMapName = "zuoying" }
DateTime.UtcNow.Elapsed = clock
ui:OnBeginPlay()
local waitingSnapshot = queued({ sequenceKey = "k", sequence = 1 })
_MatchFlowInput = { Snapshot = waitingSnapshot }
asks, closes = 0, 0
ui:RenderSiege("zuoying")
local siege, cancel = fakeNode("SiegePanel"), fakeNode("SiegePanel/Cancel")
check(siege.Enable and asks == 1, "a war pairing in a town shows the card and asks for the board")
check(fakeNode("SiegePanel/Status").TextGUIRendererComponent.Text == "配對中 · 倒數 2 秒" and cancel.Enable and cancel.ButtonComponent.Enable, "the words and the button")
local writes = fakeNode("SiegePanel/Status").writes
ui:RenderSiege("zuoying")
check(fakeNode("SiegePanel/Status").writes == writes and asks == 1, "an unchanged frame writes nothing and asks nothing")
ui:PressSiege()
check(sent[1] == "CANCEL:a", "the button sends the cancel of the observed attempt")
ui:RenderSiege("zuoying")
check(fakeNode("SiegePanel/Status").TextGUIRendererComponent.Text == "正在取消配對…" and not cancel.Enable, "pending until the server answers")
ui:PressSiege()
check(#sent == 1, "a second click while pending sends nothing")
-- Not in a town, or the lobby's town panel open: no card, no subscription.
ui._T.siegePendingAction = ""
_UserService.LocalPlayer.CurrentMapName = "formationlobby"
ui:RenderSiege("formationlobby")
check(not siege.Enable and closes == 1 and not ui._T.siegeShown, "outside a town the card is hidden and the subscription ends")
ui:PressSiege()
check(#sent == 1, "no button outside a town")
_UserService.LocalPlayer.CurrentMapName = "zuoying"
ui:RenderSiege("zuoying")
check(siege.Enable and asks == 2, "back in a town it shows and asks again")
ui._T.panelOpen = true
ui:RenderSiege("zuoying")
check(not siege.Enable and closes == 2, "the lobby's town panel covers the town: the card hides")
ui:PressSiege()
check(#sent == 1, "and its button is dead")
ui._T.panelOpen = false
-- Idle ends it; a failed entry offers Stop Entry through the same button.
_MatchFlowInput.Snapshot = { state = "IDLE", reasonCode = "CANCELLED", started = 0, players = 0, busy = false, summary = "", attempt = "", origin = "", target = "" }
ui:RenderSiege("zuoying")
check(not siege.Enable and townStatusAsks >= 1, "cancelled: the card hides and the town status is read again")
_MatchFlowInput.Snapshot = queued({ state = "SAVING", opponentFound = true, reasonCode = "HANDOFF_SEAL_FAILED", sequenceKey = "k2", sequence = 1 })
ui:RenderSiege("zuoying")
check(siege.Enable and cancel.TextGUIRendererComponent.Text == "停止入場" and cancel.Enable, "a failed entry offers Stop Entry")
ui:PressSiege()
check(sent[2] == "RETURN:a", "Stop Entry sends the return of the observed attempt")
-- A reconnect restarts the client logic: the card subscribes again by itself.
asks = 0
ui:OnBeginPlay()
_MatchFlowInput.Snapshot = waitingSnapshot
ui:RenderSiege("zuoying")
check(siege.Enable and asks == 1, "after a reconnect the card asks for the board again")

-- A town never hides the player's avatar (only the lobby screen and a battle room do): a hidden one is shown again, anywhere else it is left alone.
local avatar = { Visible = false, shown = 0 }
function avatar:SetVisible(value) self.Visible = value; self.shown = self.shown + 1 end
check(ui:KeepAvatarVisible(avatar, "zuoying") == true and avatar.Visible and avatar.shown == 1, "a hidden avatar in a town is shown again")
check(ui:KeepAvatarVisible(avatar, "zuoying") == false and avatar.shown == 1, "a visible one is left alone")
avatar.Visible = false
check(ui:KeepAvatarVisible(avatar, "formationlobby") == false and not avatar.Visible, "the lobby hides it on purpose")
check(ui:KeepAvatarVisible(avatar, "matchprobe") == false and not avatar.Visible, "so does a battle room")

print("[VRF][SiegePanels] attack panel, siege panel and team preview rules PASS checks=" .. tostring(checks))
