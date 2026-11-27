-- Target selection (#124) rules: run through target_select_local.cjs. Fakes only; the production bodies run unchanged.
local doc, attack, map, ui = _FactionWarTownDocument, _FactionWarAttack, _FactionWarMap, _FactionWarMapUI
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

log = function() end
log_warning = function() end
log_error = function() end
isvalid = function(value) return value ~= nil end
DateTime = { UtcNow = { Elapsed = 1000 } }
Vector2 = function(x, y) return { x = x, y = y } end
Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
KeyboardKey = { M = 77 }
KeyDownEvent, MouseScrollEvent = {}, {}
_InputService = { ConnectEvent = function() return "handler" end, DisconnectEvent = function() end }
_WorldInstanceService = { WorldInstanceId = "instance" }
_RoomService = { IsInstanceRoom = function() return false end }

-- Zuoying (A) is attacked from: Nanzih (A capital) is its own, Gushan (B) is adjacent, Yancheng (B capital) is an enemy that is not adjacent.
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
local engaged, queued = false, {}
_MatchFlow = { StateForUser = function() return engaged and "QUEUED" or "IDLE" end, TargetForUser = function() return engaged and "gushan" or "" end, QueueForWar = function(_, userId, origin, target) table.insert(queued, userId .. ":" .. origin .. ">" .. target) end }
_FormationHandoff = { IsLockedForUser = function() return false end }
local judged = {}
_FactionWarLanding = { Judge = function(_, userId, request) table.insert(judged, userId .. ":" .. request.kind .. ":" .. request.town) return false end }

-- The retired attack panel is gone from the server side: no options request, no panel viewers, no panel push.
local realReceiveSelect, realReceiveAttackResult = attack.ReceiveSelect, attack.ReceiveAttackResult
check(attack.RequestOptions == nil and attack.OptionsFor == nil and attack.ReceiveOptions == nil, "the options request and reply are gone")
check(map.WatchPanel == nil and map.RequestPanelClose == nil and map.ReceivePanelBoard == nil and map.PushStrengths == nil, "the panel viewer is gone")

-- The selectable targets are the server's: an adjacent enemy town (a capital included), nothing else.
local list = attack:Targets("zuoying", "A", board)
check(#list == 1 and list[1].town == "gushan" and list[1].strength == 55 and list[1].owner == "B" and list[1].capital == false, "only the adjacent enemy town is a target")
local captured = doc:InitialTowns()
captured.gushan.owner = "A"
local capitalList = attack:Targets("gushan", "A", captured)
check(#capitalList == 1 and capitalList[1].town == "yancheng" and capitalList[1].capital == true, "a capital can be a target, flagged")
for _, id in ipairs(doc.TownOrder) do
    local listed = false
    for _, option in ipairs(list) do listed = listed or option.town == id end
    check(attack:CanTarget("zuoying", id, "A", board) == listed, "CanTarget agrees with the listed targets for " .. id)
end
check(not attack:CanTarget("zuoying", "zuoying", "A", board) and not attack:CanTarget("zuoying", "nanzih", "A", board) and not attack:CanTarget("zuoying", "yancheng", "A", board), "own, departure and far towns are refused")

-- The NPC press: one reply with everything, one read, the viewer registered without another read.
local answers = {}
function attack:ReceiveSelect(town, status, header, targets, mapBoard, userId) table.insert(answers, { town = town, status = status, header = header, targets = targets, board = mapBoard, userId = userId }) end
local function freshMap()
    map._T = { viewers = {}, siegeViewers = {}, waiting = {}, reading = false, readStarted = 0, inflight = {}, again = false, signature = "", links = nil }
end
freshMap()
attack._T.reading = {}
local red = player("red-user", "red", "zuoying")
reads = 0
attack:SelectFor("red-user")
local answer = answers[#answers]
check(reads == 1, "one read of the town table answers the whole selection (the faction read is separate)")
check(answer.status == "READY" and answer.town == "zuoying" and answer.userId == "red-user", "READY for an owner who is not queued")
check(answer.header.town == "zuoying" and answer.header.strength == 100 and answer.header.owner == "A" and answer.header.faction == "A" and answer.header.capital == false, "the departure town and the player's faction")
check(#answer.targets == 1 and answer.targets[1].town == "gushan", "the targets are the server's list")
check(#answer.board.towns == 4 and answer.board.towns[1].id == "nanzih" and answer.board.towns[3].strength == 55 and answer.board.towns[1].capital == true, "the board: every town with owner, strength and capital flag")
check(#answer.board.links == 3 and answer.board.links[1].a == "nanzih" and answer.board.links[1].b == "zuoying" and answer.board.links[3].b == "yancheng", "the links are the authored gates")
check(map._T.viewers["red-user"] == red and next(map._T.siegeViewers) == nil, "a READY player is a map viewer, nothing else")
check(attack._T.reading["red-user"] == nil, "the read is released")

-- Every other status answers with the status alone: no targets, no board, no viewer, no map.
local function statusOnly(label, status, expectedHeader)
    local reply = answers[#answers]
    check(reply.status == status and #reply.targets == 0 and next(reply.board) == nil, label .. ": status " .. status .. " and no targets, no board")
    for key, value in pairs(reply.header) do check(expectedHeader ~= nil and expectedHeader[key] == value, label .. ": header " .. key) end
    for key in pairs(expectedHeader or {}) do check(reply.header[key] ~= nil, label .. ": header " .. key .. " is sent") end
end
freshMap()
engaged = true
attack:SelectFor("red-user")
statusOnly("a queued player", "ENGAGED", { target = "gushan" })
check(next(map._T.viewers) == nil, "a queued player is not made a map viewer, and the answer names the town they are attacking")
engaged = false
factions.red = nil
attack:SelectFor("red-user")
statusOnly("an unreadable faction", "UNAVAILABLE")
factions.red = ""
attack:SelectFor("red-user")
statusOnly("no faction yet", "UNAVAILABLE")
factions.red = "A"
board.zuoying.owner = "B"
judged = {}
attack:SelectFor("red-user")
statusOnly("a fallen departure town", "NOT_OWNED")
check(judged[1] == "red-user:CHECK:zuoying" and next(map._T.viewers) == nil, "the fallen town sends the player to their capital and subscribes nothing")
board.zuoying.owner = "A"
-- An owner of the departure town with no adjacent enemy town has nothing to pick: a status of its own, no map, no viewer.
board.gushan.owner = "A"
judged = {}
attack:SelectFor("red-user")
statusOnly("no adjacent enemy town", "NO_TARGETS")
check(next(map._T.viewers) == nil and #judged == 0, "NO_TARGETS subscribes nothing and judges nothing")
board.gushan.owner = "B"
local before = #answers
players["red-user"].CurrentMapName = "formationlobby"
attack:SelectFor("red-user")
check(#answers == before, "outside a town nobody is answered")
players["red-user"].CurrentMapName = "zuoying"
attack._T.reading["red-user"] = true
attack:SelectFor("red-user")
check(#answers == before, "a press while the earlier one is still being read is ignored")
attack._T.reading["red-user"] = nil
attack:SelectFor("stranger")
check(#answers == before, "an unknown caller gets nothing")

-- The reply and the attack result reach the map's client logic.
local forwarded = {}
local realShowSelect, realShowAttackResult = ui.ShowSelect, ui.ShowAttackResult
ui.ShowSelect = function(_, ...) forwarded.select = { ... } end
ui.ShowAttackResult = function(_, result) forwarded.result = result end
realReceiveSelect(attack, "zuoying", "READY", { town = "zuoying" }, {}, { towns = {} })
check(forwarded.select ~= nil and forwarded.select[1] == "zuoying" and forwarded.select[2] == "READY", "ReceiveSelect hands the answer to the map")
realReceiveAttackResult(attack, "QUEUING")
check(forwarded.result == "QUEUING", "ReceiveAttackResult hands the result to the map")
ui.ShowSelect, ui.ShowAttackResult = realShowSelect, realShowAttackResult

-- The map viewer follows the board after the reply, without another request; leaving ends it.
local mapSent = {}
function map:ReceiveBoard(towns, links, userId) table.insert(mapSent, userId) end
function map:ReceiveFaction() end
function map:ReceiveUnavailable() end
function map:ReceiveSiegeBoard() end
freshMap()
attack:SelectFor("red-user")
board.gushan.strength = 35
reads = 0
map:BoardChanged("room")
check(reads == 1 and #mapSent == 1 and mapSent[1] == "red-user", "a changed board is pushed to the selecting player after one read")
mapSent = {}
map:BoardChanged("room")
check(#mapSent == 0, "an unchanged board is not pushed again")
board.gushan.strength = 15
players["red-user"].CurrentMapName = "formationlobby"
map:BoardChanged("room")
check(map._T.viewers["red-user"] == nil and #mapSent == 0, "a player who left the town is dropped without a push")
players["red-user"].CurrentMapName = "zuoying"
map:WatchMap("red-user", red)
map:WatchMap("stranger", { CurrentMapName = "zuoying", PlayerComponent = {} })
check(map._T.viewers["red-user"] == red and map._T.viewers["stranger"] == nil, "WatchMap registers only a player the server knows, in a town")
map:HandleUserLeaveEvent({ UserId = "red-user" })
check(next(map._T.viewers) == nil, "leaving the room ends it")
freshMap()
reads = 0
map:BoardChanged("room")
check(reads == 0, "nobody looking means nothing to read")
board.gushan.strength = 55

-- The attack request repeats every check on the server.
local results = {}
function attack:ReceiveAttackResult(result, userId) table.insert(results, result) end
attack._T.reading = {}
attack:AttackFor("red-user", "gushan")
check(results[#results] == "QUEUING" and queued[#queued] == "red-user:zuoying>gushan", "an adjacent enemy town is queued")
local queuedBefore = #queued
attack:AttackFor("red-user", "yancheng")
check(results[#results] == "INVALID" and #queued == queuedBefore, "a far enemy town is refused as INVALID")
attack:AttackFor("red-user", "nanzih")
check(results[#results] == "INVALID" and #queued == queuedBefore, "an own town is refused as INVALID")
engaged = true
attack:AttackFor("red-user", "gushan")
check(results[#results] == "ENGAGED" and #queued == queuedBefore, "a queued player is refused as ENGAGED")
engaged = false

-- ---- the client: the world map in target selection --------------------------------------------------------------------------------
local nodes = {}
local function node(path)
    if nodes[path] == nil then
        nodes[path] = { Enable = false, SetEnable = function(self, value) self.Enable = value end,
            TextGUIRendererComponent = { Text = "" }, SpriteGUIRendererComponent = {}, ButtonComponent = { Enable = true },
            UITransformComponent = { RectSize = Vector2(740, 810), anchoredPosition = Vector2(0, 0), ZRotation = 0 } }
    end
    return nodes[path]
end
_EntityService = { GetEntityByPath = function(_, path) return node((string.gsub(path, "^/ui/WorldMapGroup/", ""))) end }
_UserService.LocalPlayer = { CurrentMapName = "zuoying" }
_FormationLobby = { IsTownPanelOpen = function() return false end }
_FactionWarUI = { HighlightedTownName = function(_, town) return "<c>" .. doc.TownNames[town] .. "</c>" end, ShowTownStatus = function() end }
local calls
local function fresh()
    nodes = {}
    calls = { open = 0, close = 0, select = 0, attack = {} }
    ui:OnBeginPlay()
    ui._T.mapName = _UserService.LocalPlayer.CurrentMapName
end
map.RequestOpen = function() calls.open = calls.open + 1 end
map.RequestClose = function() calls.close = calls.close + 1 end
attack.RequestSelect = function() calls.select = calls.select + 1 end
attack.RequestAttack = function(_, target) table.insert(calls.attack, target) end
local function text(path) return node(path).TextGUIRendererComponent.Text end
local function rowOf(id) return "Overlay/Window/Side/Rows/" .. id end
local function towns(strengths, owners)
    local list = {}
    for _, id in ipairs(doc.TownOrder) do
        table.insert(list, { id = id, name = doc.TownNames[id], owner = (owners or {})[id] or board[id].owner, strength = (strengths or {})[id] or board[id].strength, capital = doc:IsCapital(id) })
    end
    return list
end
local links = { { a = "nanzih", b = "zuoying" }, { a = "zuoying", b = "gushan" }, { a = "gushan", b = "yancheng" } }
local header = { town = "zuoying", name = "左營", capital = false, strength = 100, owner = "A", faction = "A" }
local gushan = { town = "gushan", name = "鼓山", capital = false, strength = 55, owner = "B" }
local function ready(origin, targets, mapTowns)
    ui:ShowSelect(origin, "READY", { town = origin, strength = 100, owner = "A", faction = "A" }, targets, { towns = mapTowns, links = links })
end

-- READY opens the map in selection mode from the answer alone: no request for the board, the faction shown, only the listed town can be picked.
fresh()
board.gushan.strength = 55
ui:ShowSelect("zuoying", "READY", header, { gushan }, { towns = towns(), links = links })
check(node("Overlay").Enable and ui._T.open and ui._T.mode == "select", "READY opens the map in selection mode")
check(calls.open == 0 and calls.select == 0, "the answer carries the board: nothing is asked for again")
check(text("Overlay/Window/Side/Faction") == "A 方" and text("Overlay/Window/Side/Header") == "選擇要進攻的相鄰敵城", "the faction and the selection hint")
check(text(rowOf("gushan") .. "/Value") == "55/100" and text(rowOf("zuoying") .. "/Value") == "100/100" and text(rowOf("yancheng") .. "/Value") == "100/100", "the list shows every town's strength")
for _, id in ipairs(doc.TownOrder) do
    local selectable = id == "gushan"
    check(node(rowOf(id) .. "/Pick").Enable == selectable, id .. ": only the listed town has a pick button")
    check(node(rowOf(id) .. "/Dim").Enable == not selectable, id .. ": the others are dimmed")
end
local lit = node("Overlay/Window/Map/Content/Districts/gushan").SpriteGUIRendererComponent.Color
local dim = node("Overlay/Window/Map/Content/Districts/yancheng").SpriteGUIRendererComponent.Color
check(lit.a == ui.DistrictAlpha and dim.a == ui.DimDistrictAlpha, "a town that cannot be picked is drawn dimmer on the map")
check(node("Overlay/Window/Map/Content/Towns/gushan/Crest").SpriteGUIRendererComponent.Color.a == 1 and node("Overlay/Window/Map/Content/Towns/nanzih/Crest").SpriteGUIRendererComponent.Color.a == ui.DimCrestAlpha, "and so is its crest")
check(node("Overlay/Window/Map/Content/Towns/zuoying/Arrow").Enable and not node("Overlay/Window/Map/Content/Towns/gushan/Arrow").Enable, "the town the player stands in is marked")
check(not node("Confirm").Enable, "no confirmation before a pick")
check(ui:BlocksInteraction() == true, "the NPCs ignore the interaction key while the map is open")

-- A press on a town that is not listed does nothing.
ui:Pick("yancheng")
ui:Pick("zuoying")
ui:Pick("nanzih")
check(ui._T.selected == nil and not node("Confirm").Enable, "own, departure and far towns cannot be picked")

-- A pick asks for the confirmation, with both strengths and the live numbers.
ui:Pick("gushan")
check(node("Confirm").Enable and ui._T.selected == "gushan", "the pick opens the confirmation")
check(text("Confirm/Window/Title") == "進攻 <c>鼓山</c>？", "the title names the target")
check(text("Confirm/Window/Origin") == "出發城 <c>左營</c>　兵力 100 / 100" and text("Confirm/Window/Target") == "目標城 <c>鼓山</c>　兵力 55 / 100", "the departure and target strengths")
check(text("Confirm/Window/Note") == "" and text("Confirm/Window/Status") == "", "an ordinary town has no capital note")
check(node("Confirm/Window/Yes").ButtonComponent.Enable and node("Confirm/Window/No").ButtonComponent.Enable, "both buttons answer")
ui:ShowBoard(towns({ gushan = 35, zuoying = 90 }), links)
check(text("Confirm/Window/Origin") == "出發城 <c>左營</c>　兵力 90 / 100" and text("Confirm/Window/Target") == "目標城 <c>鼓山</c>　兵力 35 / 100", "a pushed board updates the open window")
check(text(rowOf("gushan") .. "/Value") == "35/100" and calls.select == 0, "and the list, without asking again")
ui:ShowBoard(towns({ gushan = 35 }, { yancheng = "A" }), links)
check(calls.select == 1, "a town that changed hands asks the server for the targets again")
ui:ShowBoard(towns({ gushan = 35 }, { yancheng = "A" }), links)
check(calls.select == 1, "an unchanged owner does not")
ui:Pick("gushan")
check(ui._T.selected == "gushan", "a second press while confirming changes nothing")
local hotkey = { key = KeyboardKey.M }
ui:HandleKey(hotkey)
check(ui._T.open and node("Confirm").Enable, "M does not close the map from behind the confirmation")
ui:HandleWheel({ ScrollDelta = 1 })
check(ui._T.zoom == 1, "the wheel does not zoom behind the confirmation")

-- No: only the window closes and the pick is cleared; the map stays.
ui:Decline()
check(not node("Confirm").Enable and ui._T.selected == nil and ui._T.open and ui._T.mode == "select" and #calls.attack == 0, "No closes the window, clears the pick, keeps the map, sends nothing")
check(node(rowOf("gushan") .. "/Pick").Enable, "the town can be picked again")

-- Yes: one request, then the window waits.
ui:Pick("gushan")
ui:ConfirmAttack()
check(#calls.attack == 1 and calls.attack[1] == "gushan", "Yes sends the attack request for the picked town")
check(text("Confirm/Window/Status") == "正在加入配對…" and not node("Confirm/Window/Yes").ButtonComponent.Enable and not node("Confirm/Window/No").ButtonComponent.Enable, "the buttons are disabled and the window says it is joining")
ui:ConfirmAttack()
ui:Decline()
ui:Pick("gushan")
check(#calls.attack == 1 and ui._T.selected == "gushan" and node("Confirm").Enable, "nothing else is accepted while waiting")
ui:HandleWheel({ ScrollDelta = 1 })
check(ui._T.zoom == 1, "still no zoom")

-- QUEUING closes the map and the window with it; the siege panel takes over.
ui:ShowAttackResult("QUEUING")
check(not ui._T.open and not node("Overlay").Enable and not node("Confirm").Enable and ui._T.selected == nil and ui._T.mode == "view", "QUEUING closes the map and clears the selection")
check(calls.close == 1 and not ui:BlocksInteraction(), "the server is told, and the NPCs answer again")

-- The other answers keep the window and say why.
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ui:ConfirmAttack()
ui:ShowAttackResult("ENGAGED")
check(node("Confirm").Enable and text("Confirm/Window/Status") == "已在配對中，請先取消目前的配對" and node("Confirm/Window/Yes").ButtonComponent.Enable, "ENGAGED: the window stays, says so and can be answered again")
ui:ConfirmAttack()
ui:ShowAttackResult("UNAVAILABLE")
check(node("Confirm").Enable and text("Confirm/Window/Status") == "暫時無法配對，請再試一次" and #calls.attack == 2, "UNAVAILABLE: the window stays and offers another try")
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
check(not node("Confirm").Enable and ui._T.selected == nil and ui._T.open and calls.select == 1, "INVALID: the pick is dropped, the map stays and the server is asked for the targets again")

-- A reply that arrives for a map the player already closed never reopens it.
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ui:ConfirmAttack()
ui:Close()
ui:ShowAttackResult("INVALID")
check(not ui._T.open and not node("Overlay").Enable and calls.select == 0 and ui._T.pending == false, "an INVALID that arrives after the map was closed asks for nothing")
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
check(calls.select == 1, "an INVALID while the map is open still asks for the targets again")
ui:Close()
ready("zuoying", { gushan }, towns())
check(not ui._T.open and not node("Overlay").Enable and calls.close == 2, "the relisted targets that arrive after the map was closed open nothing and tell the server nobody is watching")
ui:ConfirmAttack()
check(#calls.attack == 1, "nothing can be confirmed behind the closed map")
fresh()
ready("zuoying", { gushan }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
check(calls.select == 1, "a changed owner relists")
ui:Close()
ready("zuoying", { gushan }, towns())
check(not ui._T.open and calls.close == 2, "so does a relist answered after the map was closed")
ui:BeginSelect()
ready("zuoying", { gushan }, towns())
check(ui._T.open and ui._T.mode == "select", "a new NPC press after that opens its own answer")

-- A new answer drops a pick that is no longer listed, and a status other than READY closes a selection that is open.
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ready("zuoying", {}, towns())
check(ui._T.selected == nil and not node("Confirm").Enable and not node(rowOf("gushan") .. "/Pick").Enable and node(rowOf("gushan") .. "/Dim").Enable, "a refreshed list without the picked town drops the pick")
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(not ui._T.open and not node("Overlay").Enable and calls.close == 1, "a status other than READY closes an open selection")
ui:ShowSelect("zuoying", "ENGAGED", {}, {}, {})
ui:ShowSelect("zuoying", "UNAVAILABLE", {}, {}, {})
check(not ui._T.open and not node("Overlay").Enable and calls.close == 1, "and opens nothing when the map was closed")

-- ---- #127: an answer that is not READY opens a message window, never the map ----------------------------------------------------------
local ENGAGED_TEXT = "目前正在進攻 <c>鼓山</c>，要改變目標請先取消配對（畫面上方的攻城面板可以取消）"
local function shown() return node("Message").Enable and text("Message/Window/Text") or nil end
local function noMap(label) check(not ui._T.open and not node("Overlay").Enable and not node("Confirm").Enable, label .. ": the map stays closed") end
for _, case in ipairs({
    { "ENGAGED", { target = "gushan" }, ENGAGED_TEXT },
    { "ENGAGED", {}, "目前已在配對中，要改變目標請先取消配對（畫面上方的攻城面板可以取消）" },
    { "NOT_OWNED", {}, "這座城已不屬於你的陣營" },
    { "UNAVAILABLE", {}, "暫時無法讀取國戰資料，請再試一次" },
    { "NO_TARGETS", {}, "目前沒有可進攻的相鄰敵城" },
}) do
    fresh()
    ui:BeginSelect()
    ui:ShowSelect("zuoying", case[1], case[2], {}, {})
    noMap(case[1])
    check(shown() == case[3], case[1] .. ": the message says " .. case[3])
    check(calls.open == 0 and calls.select == 0 and #calls.attack == 0 and calls.close == 0, case[1] .. ": no further request")
    check(ui:BlocksInteraction(), case[1] .. ": the NPCs ignore the key while the message is shown")
    ui:HandleKey({ key = KeyboardKey.M })
    ui:Open()
    check(not ui._T.open and calls.open == 0, case[1] .. ": neither M nor the map button opens a map behind the message")
    ui:DismissMessage()
    check(shown() == nil and not ui:BlocksInteraction(), case[1] .. ": 確定 closes it and the NPCs answer again")
end
fresh()
ui:ShowSelect("zuoying", "SOMETHING_ELSE", {}, {}, {})
check(shown() == nil, "an unknown status shows no message")

-- The same message when a selection that was open is ended by a non-READY answer (a relist), and none when the map was closed meanwhile.
fresh()
ready("zuoying", { gushan }, towns())
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(not ui._T.open and calls.close == 1 and shown() == "這座城已不屬於你的陣營", "an open selection that is answered NOT_OWNED closes and says so")
fresh()
ready("zuoying", { gushan }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:Close()
ui:ShowSelect("zuoying", "ENGAGED", { target = "gushan" }, {}, {})
check(shown() == nil and not ui:BlocksInteraction(), "a relist answered after the player closed the map shows nothing")
fresh()
_UserService.LocalPlayer.CurrentMapName = "gushan"
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(shown() == nil, "an answer for a town the player has left shows nothing")
_UserService.LocalPlayer.CurrentMapName = "zuoying"

-- The message stands above the map too: over the open view it is shown and blocks the view.
fresh()
ui:Open()
ui:ShowSelect("zuoying", "UNAVAILABLE", {}, {}, {})
check(ui._T.open and shown() == "暫時無法讀取國戰資料，請再試一次", "over the open view the message is shown and the view stays")
ui:HandleWheel({ ScrollDelta = 1 })
ui:HandleKey({ key = KeyboardKey.M })
check(ui._T.open and ui._T.zoom == 1, "behind the message the wheel does not zoom and M does not close the view")
ui:DismissMessage()
ui:HandleKey({ key = KeyboardKey.M })
check(not ui._T.open, "after 確定 M closes the view again")

-- A fallen departure town lands the player in their capital right after the answer: the message must still be there to read.
fresh()
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
_UserService.LocalPlayer.CurrentMapName = "nanzih"
ui:ExpireAsk()
check(shown() == "這座城已不屬於你的陣營" and ui:BlocksInteraction(), "the message stays after the player was moved, until 確定")
ui:DismissMessage()
check(shown() == nil and not ui:BlocksInteraction(), "確定 closes it")
_UserService.LocalPlayer.CurrentMapName = "zuoying"

-- ---- the guard: one request and one window per press, no interaction behind a window -------------------------------------------------
local war, lobbyNpc = _FactionWarNpc, _FactionWarLobbyNpc
local lobbyOpened = 0
_FormationLobby.OpenTownPanel = function() lobbyOpened = lobbyOpened + 1 end
local me = _UserService.LocalPlayer
local function pressWar(who) war:HandleInteractionEvent({ InteractionEntity = who or me }) end
local function pressLobby() lobbyNpc:HandleInteractionEvent({ InteractionEntity = me }) end
fresh()
lobbyOpened = 0
DateTime.UtcNow.Elapsed = 1000
pressWar()
check(calls.select == 1 and ui:BlocksInteraction(), "a press asks the server once and then waits")
pressWar()
pressLobby()
check(calls.select == 1 and lobbyOpened == 0, "while the answer is awaited neither NPC reacts: no second request")
pressWar({})
check(calls.select == 1, "and a press by someone else is never this player's request")
ui:ShowSelect("zuoying", "ENGAGED", { target = "gushan" }, {}, {})
pressWar()
pressLobby()
check(calls.select == 1 and lobbyOpened == 0 and shown() == ENGAGED_TEXT, "while the message is shown neither NPC reacts: no second window")
ui:DismissMessage()
pressWar()
check(calls.select == 2, "after 確定 the war NPC asks again")
ui:ShowSelect("zuoying", "READY", header, { gushan }, { towns = towns(), links = links })
check(ui._T.open and not ui._T.asking, "the answer ends the wait")
pressWar()
pressLobby()
check(calls.select == 2 and lobbyOpened == 0, "behind the open map neither NPC reacts")
ui:Pick("gushan")
pressWar()
pressLobby()
check(ui._T.selected == "gushan" and calls.select == 2 and lobbyOpened == 0, "nor behind the confirmation window")
ui:ConfirmAttack()
ui:ShowAttackResult("QUEUING")
pressLobby()
check(lobbyOpened == 1, "with every window closed the lobby NPC opens its panel")
-- A reply that never comes must not lock the NPCs for good.
fresh()
DateTime.UtcNow.Elapsed = 1000
pressWar()
DateTime.UtcNow.Elapsed = 1000 + ui.AskTimeout * 1000 - 1
ui:ExpireAsk()
check(ui:BlocksInteraction(), "the wait lasts the whole timeout")
DateTime.UtcNow.Elapsed = 1000 + ui.AskTimeout * 1000 + 1
ui:ExpireAsk()
check(not ui:BlocksInteraction(), "then it ends and the NPC answers a new press")
pressWar()
check(calls.select == 2, "which asks again")
-- A READY answer that is not shown (lobby screen over the town) also ends the wait.
fresh()
_FormationLobby.IsTownPanelOpen = function() return true end
pressWar()
ready("zuoying", { gushan }, towns())
check(not ui:BlocksInteraction(), "an answer that opens nothing still ends the wait")
_FormationLobby.IsTownPanelOpen = function() return false end
DateTime.UtcNow.Elapsed = 1000

-- The capital note.
fresh()
local fallen = doc:InitialTowns()
fallen.gushan.owner = "A"
_UserService.LocalPlayer.CurrentMapName = "gushan"
ui:ShowSelect("gushan", "READY", { town = "gushan", strength = 100, owner = "A", faction = "A" }, { { town = "yancheng", name = "鹽埕", capital = true, strength = 100, owner = "B" } },
    { towns = (function() local list = {} for _, id in ipairs(doc.TownOrder) do table.insert(list, { id = id, name = doc.TownNames[id], owner = fallen[id].owner, strength = fallen[id].strength, capital = doc:IsCapital(id) }) end return list end)(), links = links })
ui:Pick("yancheng")
check(text("Confirm/Window/Note") == "打贏不扣主城兵力" and text("Confirm/Window/Title") == "進攻 <c>鹽埕</c>？", "a capital target adds the note that winning takes no strength")
_UserService.LocalPlayer.CurrentMapName = "zuoying"

-- Closing the map (the close button, leaving the town) drops the selection, the window included, and a later view is a plain view.
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ui:Close()
check(not node("Overlay").Enable and not node("Confirm").Enable and ui._T.selected == nil and ui._T.mode == "view" and next(ui._T.targets) == nil and calls.close == 1, "closing the map cancels the selection")
ui:Open()
check(ui._T.open and ui._T.mode == "view" and calls.open == 1 and text("Overlay/Window/Side/Header") == "城鎮兵力（由北到南）", "the view opens as before, asking the server")
for _, id in ipairs(doc.TownOrder) do
    check(not node(rowOf(id) .. "/Pick").Enable and not node(rowOf(id) .. "/Dim").Enable, id .. ": the view has no pick button and no veil")
end
check(node("Overlay/Window/Map/Content/Districts/yancheng").SpriteGUIRendererComponent.Color.a == ui.DistrictAlpha, "and no town is dimmed")
ui:Pick("gushan")
check(ui._T.selected == nil and not node("Confirm").Enable, "a view cannot pick")
ui:ShowBoard(towns({}, { gushan = "A" }), links)
check(calls.select == 0, "a changed owner in the view does not ask for targets")
ui:HandleKey({ key = KeyboardKey.M })
check(not ui._T.open and calls.close == 2, "M still closes the view")
ui:HandleKey({ key = KeyboardKey.M })
check(ui._T.open and ui._T.mode == "view" and calls.open == 2, "and opens it again as a view")

-- The NPC while the view is open switches it to the selection without a second subscription.
ui:ShowSelect("zuoying", "READY", header, { gushan }, { towns = towns(), links = links })
check(ui._T.open and ui._T.mode == "select" and calls.open == 2 and node(rowOf("gushan") .. "/Pick").Enable, "an answer while the view is open switches it to the selection")

-- The lobby screen over a town hides the map: no selection opens from an answer that arrives then.
fresh()
_FormationLobby.IsTownPanelOpen = function() return true end
ready("zuoying", { gushan }, towns())
check(not ui._T.open and not node("Overlay").Enable, "an answer that arrives under the lobby screen opens nothing")
check(calls.close == 1, "and tells the server nobody is watching, so the viewer it registered is dropped")
_FormationLobby.IsTownPanelOpen = function() return false end
_UserService.LocalPlayer.CurrentMapName = "gushan"
ready("zuoying", { gushan }, towns())
check(not ui._T.open, "nor one for the town the player left")
check(calls.close == 2, "which is also unwatched")
_UserService.LocalPlayer.CurrentMapName = "zuoying"

-- ---- #128: the town table changes while the map or the confirmation window is open ---------------------------------------------------
local yancheng = { town = "yancheng", name = "鹽埕", capital = true, strength = 100, owner = "B" }
local TARGET_GONE = "<c>鼓山</c> 已不能進攻"
local ORIGIN_GONE = "這座城已不屬於你的陣營"
local function notice() return node("Overlay/Window/Side/Notice").Enable and text("Overlay/Window/Side/Notice") or nil end
local function openConfirm()
    fresh()
    ready("zuoying", { gushan, yancheng }, towns())
    ui:Pick("gushan")
    check(node("Confirm").Enable and ui._T.selected == "gushan" and notice() == nil, "setup: a pick is being confirmed and no line is shown")
end
local function everythingDim(label)
    for _, id in ipairs(doc.TownOrder) do
        check(not node(rowOf(id) .. "/Pick").Enable and node(rowOf(id) .. "/Dim").Enable, label .. ": " .. id .. " cannot be picked and is dimmed")
    end
end

-- Only the strength moves: the window keeps both numbers current, stays open, and nothing else changes.
openConfirm()
ui:ShowBoard(towns({ gushan = 20, zuoying = 70 }), links)
check(node("Confirm").Enable and ui._T.selected == "gushan" and not ui._T.pending, "a strength change keeps the confirmation window open")
check(text("Confirm/Window/Origin") == "出發城 <c>左營</c>　兵力 70 / 100" and text("Confirm/Window/Target") == "目標城 <c>鼓山</c>　兵力 20 / 100", "and updates both numbers")
check(text(rowOf("gushan") .. "/Value") == "20/100" and text("Overlay/Window/Map/Content/Towns/gushan/Strength") == "兵力 20/100", "the list and the map follow")
check(calls.select == 0 and notice() == nil and node(rowOf("gushan") .. "/Pick").Enable, "no request, no line, the same pick buttons")

-- A town changed hands but the picked one is still a target: the list is asked for again and the window stays.
openConfirm()
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
check(calls.select == 1 and ui._T.relisting, "a town that changed hands asks the server for the list")
ready("zuoying", { gushan }, towns({}, { yancheng = "A" }))
check(node("Confirm").Enable and ui._T.selected == "gushan" and notice() == nil and not ui._T.relisting, "a picked town that is still listed keeps its window and shows no line")

-- The relisted answer redraws the list and the rows exactly as the server listed them.
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ui:ShowSelect("zuoying", "READY", header, { yancheng }, { towns = towns({}, { gushan = "A" }), links = links })
check(node(rowOf("yancheng") .. "/Pick").Enable and not node(rowOf("yancheng") .. "/Dim").Enable, "the new target can be picked")
check(not node(rowOf("gushan") .. "/Pick").Enable and node(rowOf("gushan") .. "/Dim").Enable, "the town that is no longer listed cannot, and is dimmed")
check(text(rowOf("gushan") .. "/Owner") == "A 方" and node("Overlay/Window/Map/Content/Districts/gushan").SpriteGUIRendererComponent.Color.a == ui.DimDistrictAlpha, "its row and district show the new owner, dimmed")

-- The picked target can no longer be attacked (taken by the player's own side): the window closes and one line says so.
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(not node("Confirm").Enable and ui._T.selected == nil and ui._T.open and ui._T.mode == "select", "the confirmation window closes, the map stays in selection")
check(notice() == TARGET_GONE, "the side panel says the town can no longer be attacked: " .. tostring(notice()))
check(node(rowOf("yancheng") .. "/Pick").Enable and not node(rowOf("gushan") .. "/Pick").Enable, "and the list is redrawn")
check(not node("Message").Enable and ui._T.message == nil and calls.close == 0, "no message window and the map is not closed")
ui:Pick("yancheng")
check(notice() == nil and ui._T.selected == "yancheng", "the line goes away on the next pick")
-- Nothing is left to pick at all (the server answers NO_TARGETS): same line, everything dimmed, map still open.
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(ui._T.open and ui._T.mode == "select" and not node("Confirm").Enable and ui._T.selected == nil, "NO_TARGETS to the map's own relist keeps the map and closes the window")
check(notice() == TARGET_GONE and not node("Message").Enable and calls.close == 0, "with the same line and no message window")
everythingDim("NO_TARGETS")
-- Without a pick open the line names the cause.
fresh()
ready("zuoying", { gushan }, towns())
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(ui._T.open and notice() == "目前沒有可進攻的相鄰敵城" and not node("Message").Enable, "no pick open: the line says there is no target left")
everythingDim("no pick")

-- The departure town fell: the window closes, nothing can be picked, the line says so; the map stays open.
openConfirm()
ui:ShowBoard(towns({}, { zuoying = "B" }), links)
check(calls.select == 1, "the departure town changing hands asks the server")
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(ui._T.open and ui._T.mode == "select" and node("Overlay").Enable, "the map stays open")
check(not node("Confirm").Enable and ui._T.selected == nil and not ui._T.pending, "the confirmation window closes")
check(notice() == ORIGIN_GONE, "the side panel says the town is no longer the player's faction's: " .. tostring(notice()))
everythingDim("NOT_OWNED")
check(not node("Message").Enable and ui._T.message == nil and calls.close == 0, "no message window and the map is not closed")
ui:Pick("gushan")
check(ui._T.selected == nil and not node("Confirm").Enable, "nothing can be picked")
check(ui:BlocksInteraction(), "the NPCs still ignore the key while the map is open")
-- The player stands elsewhere now (sent to the capital) and a later change asks again: a READY answer ends that line.
_UserService.LocalPlayer.CurrentMapName = "nanzih"
ui._T.mapName = "nanzih"
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:ShowSelect("nanzih", "READY", { town = "nanzih", strength = 100, owner = "A", faction = "A" }, { gushan }, { towns = towns(), links = links })
check(notice() == nil and node(rowOf("gushan") .. "/Pick").Enable, "a READY answer lists the targets again and clears the line")
_UserService.LocalPlayer.CurrentMapName = "zuoying"
ui._T.mapName = "zuoying"
-- Closing and opening the map again never shows an old line.
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(notice() == TARGET_GONE, "setup: a line is shown")
ui:Close()
check(notice() == nil, "closing the map clears the line")
ui:BeginSelect()
ready("zuoying", { gushan }, towns())
check(ui._T.open and notice() == nil, "and a map opened later starts without one")

-- The server refuses the attack after 是: no stuck waiting window, the list is asked again and the line says why.
openConfirm()
ui:ConfirmAttack()
check(ui._T.pending and text("Confirm/Window/Status") == "正在加入配對…", "setup: waiting for the server")
ui:ShowAttackResult("INVALID")
check(not ui._T.pending and not node("Confirm").Enable and ui._T.selected == nil and ui._T.open, "INVALID: the window is closed, nothing waits, the map stays")
check(notice() == TARGET_GONE and calls.select == 1 and ui._T.relisting, "the line names the town and the list is asked for again")
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(notice() == TARGET_GONE and node(rowOf("yancheng") .. "/Pick").Enable and not node(rowOf("gushan") .. "/Pick").Enable, "the relisted answer redraws the list and the line stays while the town is not listed")
openConfirm()
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
ready("zuoying", { gushan }, towns())
check(notice() == nil and node(rowOf("gushan") .. "/Pick").Enable, "a refusal that the new list does not confirm (the town is a target again) leaves no line")
-- The map's own relist drops the pick while the request is on its way: the answer to it still closes the map for the siege panel.
openConfirm()
ui:ConfirmAttack()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(not ui._T.pending and not node("Confirm").Enable and notice() == TARGET_GONE, "a relist answered while waiting also closes the window and says so")
ui:ShowAttackResult("QUEUING")
check(not ui._T.open and not node("Overlay").Enable and calls.close == 1, "and the QUEUING that was already on its way still closes the map")
openConfirm()
ui:ConfirmAttack()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
ui:ShowAttackResult("INVALID")
check(notice() == TARGET_GONE and not ui._T.pending and ui._T.open, "an INVALID after the relist already dropped the pick keeps the line and does not get stuck")
-- The other refusals still keep the window (unchanged by #128), without a line.
openConfirm()
ui:ConfirmAttack()
ui:ShowAttackResult("UNAVAILABLE")
check(node("Confirm").Enable and notice() == nil and not ui._T.pending, "UNAVAILABLE keeps the window and shows no line")
-- A relist answered ENGAGED / UNAVAILABLE still ends the selection with a message window (#127).
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ui:ShowSelect("zuoying", "UNAVAILABLE", {}, {}, {})
check(not ui._T.open and calls.close == 1 and shown() == "暫時無法讀取國戰資料，請再試一次" and notice() == nil, "UNAVAILABLE to a relist closes the map and says so in the message window")
ui:DismissMessage()
-- The server's side of the same relist: after a capture the answer is exactly the targets CanTarget accepts.
board.gushan.owner = "A"
local relistAnswers = #answers
freshMap()
attack:SelectFor("red-user")
check(#answers == relistAnswers + 1 and answers[#answers].status == "NO_TARGETS" and next(map._T.viewers) == nil, "server: the departure town without an adjacent enemy is answered NO_TARGETS")
board.gushan.owner = "B"
board.zuoying.owner = "B"
judged = {}
attack:SelectFor("red-user")
check(answers[#answers].status == "NOT_OWNED" and judged[1] == "red-user:CHECK:zuoying", "server: a lost departure town is answered NOT_OWNED and judged")
board.zuoying.owner = "A"

print("[VRF][TargetSelect] target selection rules PASS checks=" .. tostring(checks))
