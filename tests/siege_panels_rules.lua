-- Team preview (#118) and siege panel (#123) rules: run through siege_panels_local.cjs. Fakes only; the production bodies run unchanged.
-- (The attack panel's rules of #117 are gone with the panel: the target selection of #124 is in target_select_rules.lua.)
local doc, map, team, ui = _FactionWarTownDocument, _FactionWarMap, _FactionWarTeam, _FactionWarUI
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

-- #130: identical town ownership, opposite perspectives; unknown/missing ownership is grey.
local function tint(faction, owner)
    local color = ui:TownColor(faction, owner)
    return string.format("%.2f/%.2f/%.2f", color.r, color.g, color.b)
end
check(tint("A", "A") == "0.27/0.50/0.88" and tint("A", "B") == "0.84/0.29/0.24", "A sees its own towns blue and B's towns red")
check(tint("B", "A") == "0.84/0.29/0.24" and tint("B", "B") == "0.27/0.50/0.88", "B sees the same board in opposite colours")
for _, unknown in ipairs({ "", "UNREADABLE" }) do
    check(tint(unknown, "A") == "0.62/0.60/0.56" and tint(unknown, "B") == "0.62/0.60/0.56", "an unknown or unaligned viewer sees grey")
end
check(tint("A", "") == "0.62/0.60/0.56", "unknown town ownership is grey even for a known viewer")

local red = player("red-user", "red", "zuoying")
local blue = player("blue-user", "blue", "gushan")
-- The world map's viewers (the siege panel is a kind of its own, below). The target selection that registers a map viewer is in target_select_rules.lua (#124).
local mapSent, mapFactions, siegeFactions = {}, {}, {}
function map:ReceiveBoard(towns, links, userId) table.insert(mapSent, userId) end
function map:ReceiveFaction(faction, userId) table.insert(mapFactions, { faction = faction, userId = userId }) end
function map:ReceiveSiegeFaction(faction, userId) table.insert(siegeFactions, { faction = faction, userId = userId }) end
function map:ReceiveUnavailable() end
local function freshMap()
    map._T = { viewers = {}, siegeViewers = {}, waiting = {}, reading = false, readStarted = 0, inflight = {}, again = false, signature = "", links = nil }
    mapSent = {}
end
freshMap()
map:WatchMap("red-user", red)
board.gushan.strength = 45
map:BoardChanged("room")
check(#mapSent == 1 and mapSent[1] == "red-user", "a map viewer still gets the map board")
freshMap()
reads = 0
map:BoardChanged("room")
check(reads == 0, "nobody looking means nothing to read")
function ui:HighlightedTownName(town) return "<c>" .. doc.TownNames[town] .. "</c>" end

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

-- #123: the siege panel follows the board for as long as it shows, as a viewer of its own kind (never the map's).
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
check(next(map._T.siegeViewers) ~= nil and next(map._T.viewers) == nil, "the siege viewer is its own kind")
check(#siegeFactions == 1 and siegeFactions[1].faction == "A" and siegeFactions[1].userId == "red-user" and #mapFactions == 0, "the siege subscription answers with the sender's own faction only")
check(reads == 1 and #siegeSent == 1 and siegeSent[1].userId == "red-user" and #mapSent == 0, "opening reads the board once and answers the opener alone")
local seen = {}
for _, town in ipairs(siegeSent[1].towns) do seen[town.id] = town end
check(seen.gushan.strength == 55 and seen.zuoying.owner == "A" and seen.nanzih.capital == true, "owner and strength per town reach the siege panel")
siegeSent = {}
reads = 0
board.gushan.strength = 35
map:BoardChanged("room")
check(reads == 1 and #siegeSent == 1 and #mapSent == 0, "a change with only the siege panel showing reads once and pushes to it alone")
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

-- A delayed response from an earlier opening must not overwrite a newer subscription.
local pendingReads = {}
_FactionWar.ReadFaction = function(_, profile, complete) table.insert(pendingReads, complete) end
senderUserId = "blue-user"
map:RequestOpen()
map:RequestClose()
map:RequestOpen()
pendingReads[2]("B")
pendingReads[1](nil)
check(#mapFactions == 1 and mapFactions[1].faction == "B" and mapFactions[1].userId == "blue-user", "only the latest map reply reaches B")
siegeFactions = {}
map:RequestSiegeOpen()
map:RequestSiegeClose()
pendingReads[3]("B")
check(#siegeFactions == 0, "a closed siege subscription gets no late faction reply")
map:RequestSiegeOpen()
pendingReads[4]("")
check(#siegeFactions == 1 and siegeFactions[1].faction == "" and siegeFactions[1].userId == "blue-user", "no faction is an explicit unaligned reply")

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
    local towns = {}
    for id, strength in pairs(strengths or figures) do towns[id] = { strength = strength } end
    return ui:SiegeView(queued(fields), { origin = "zuoying", now = clock, towns = towns, pendingAction = pendingAction })
end
local queuing = card()
check(queuing.origin == "<c>左營</c> 兵力 80" and queuing.target == "<c>鼓山</c> 兵力 55", "line one: each town with its strength")
check(queuing.status == "配對中 · 倒數 2 秒" and queuing.label == "取消配對" and queuing.action == "CANCEL" and queuing.enabled, "line two and the button while waiting")
local unknown = card({}, {})
check(unknown.origin == "<c>左營</c> 兵力 —" and unknown.target == "<c>鼓山</c> 兵力 —", "a strength not heard yet is a dash, never 0")
local live = card({}, { zuoying = 60, gushan = 0 })
check(live.origin == "<c>左營</c> 兵力 60" and live.target == "<c>鼓山</c> 兵力 0", "the numbers follow the board, a real 0 included")
-- (#132) Once the viewer's faction and both owners are known the names take the stance colour: the departure town blue (A's), the target red (B's).
ui._T.siegeFaction = "A"
local stanced = ui:SiegeView(queued(), { origin = "zuoying", now = clock, towns = { zuoying = { strength = 80, owner = "A" }, gushan = { strength = 55, owner = "B" } } })
check(stanced.origin == "<color=#4580E0>左營</color> 兵力 80" and stanced.target == "<color=#D64A3D>鼓山</color> 兵力 55", "the card's names are in the stance colours")
local flipped = ui:SiegeView(queued(), { origin = "zuoying", now = clock, towns = { zuoying = { strength = 80, owner = "B" }, gushan = { strength = 55, owner = "A" } } })
check(flipped.origin == "<color=#D64A3D>左營</color> 兵力 80" and flipped.target == "<color=#4580E0>鼓山</color> 兵力 55", "and follow a town that changed hands")
ui._T.siegeFaction = nil
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
ui._T.siegeTowns = nil
ui._T.siegeShown = false
ui:ShowSiegeBoard({ { id = "zuoying", owner = "A", strength = 70 }, { id = "gushan", owner = "B", strength = 40 } })
check(ui._T.siegeTowns == nil, "a board that arrives after the card hid is stale")
ui._T.siegeShown = true
ui:ShowSiegeBoard({ { id = "zuoying", owner = "A", strength = 70 }, { id = "gushan", owner = "B", strength = 40 } })
check(ui._T.siegeTowns.zuoying.strength == 70 and ui._T.siegeTowns.gushan.owner == "B", "a pushed board keeps strength and owner by town")
-- Following: ask when the card starts to show, again only while nothing has arrived, tell the server when it hides.
local asks, closes = 0, 0
_FactionWarMap = { RequestSiegeOpen = function() asks = asks + 1 end, RequestSiegeClose = function() closes = closes + 1 end }
DateTime.UtcNow.Elapsed = 1000000
ui._T.siegeShown, ui._T.siegeTowns, ui._T.siegeAsked, ui._T.shownText = false, nil, 0, {}
ui:FollowSiege(true)
check(asks == 1 and ui._T.siegeShown, "showing the card asks the server for the board")
ui:FollowSiege(true)
check(asks == 1, "once is enough while it is within ten seconds")
DateTime.UtcNow.Elapsed = 1011000
ui:FollowSiege(true)
check(asks == 2, "no strength heard after ten seconds: ask again")
ui._T.siegeTowns = { zuoying = { strength = 80 } }
DateTime.UtcNow.Elapsed = 1030000
ui:FollowSiege(true)
check(asks == 2, "a heard board needs no new ask")
ui:FollowSiege(false)
check(closes == 1 and not ui._T.siegeShown and ui._T.siegeTowns == nil, "hiding the card ends the push and forgets the numbers")
ui:FollowSiege(false)
check(closes == 1, "hiding twice tells the server once")

-- #123: the card as a whole, drawn against fake nodes: where it shows, what it writes, what its button sends.
local nodes = {}
local function fakeNode(path)
    if nodes[path] == nil then
        local entry = { Enable = false, writes = 0, ButtonComponent = { Enable = false }, SetEnable = function(self, value) self.Enable = value end }
        entry.UITransformComponent = { RectSize = { x = 220, y = 10 } }
        entry.SpriteGUIRendererComponent = {}
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
local originFill, targetFill = fakeNode("SiegePanel/OriginBar/Fill"), fakeNode("SiegePanel/TargetBar/Fill")
check(not originFill.Enable and not targetFill.Enable, "unknown strengths have no fill")
ui:ShowSiegeBoard({ { id = "zuoying", strength = 70, owner = "A" }, { id = "gushan", strength = 40, owner = "B" } })
ui:RenderSiege("zuoying")
check(originFill.Enable and math.abs(originFill.UITransformComponent.RectSize.x - 154) < 0.01 and originFill.SpriteGUIRendererComponent.Color.r == 0.62
    and targetFill.SpriteGUIRendererComponent.Color.r == 0.62, "board before faction paints both strengths grey")
ui:ShowSiegeFaction("B")
ui:RenderSiege("zuoying")
check(originFill.SpriteGUIRendererComponent.Color.r == 0.84 and targetFill.SpriteGUIRendererComponent.Color.b == 0.88, "late faction repaints both siege bars")
ui:ShowSiegeBoard({ { id = "zuoying", strength = 100, owner = "B" }, { id = "gushan", strength = 40, owner = "B" } })
ui:RenderSiege("zuoying")
check(originFill.UITransformComponent.RectSize.x == 220 and originFill.SpriteGUIRendererComponent.Color.b == 0.88, "a push follows changed strength and ownership")
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

print("[VRF][SiegePanels] siege panel and team preview rules PASS checks=" .. tostring(checks))
