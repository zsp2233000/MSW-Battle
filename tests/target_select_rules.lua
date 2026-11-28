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
check(map._T.viewers["red-user"] ~= nil and next(map._T.siegeViewers) == nil, "a READY player is a map viewer, nothing else")
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
check(map._T.viewers["red-user"] ~= nil and map._T.viewers["stranger"] == nil, "WatchMap registers only a player the server knows, in a town")
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
-- The town nodes sit where layout.json puts them (content units, the content is centred in the viewport).
local TOWN_AT = { nanzih = { -211.5, -173.5 }, zuoying = { -210.5, -197.5 }, gushan = { -218.5, -218.5 }, yancheng = { -213.5, -241.5 } }
local function node(path)
    if nodes[path] == nil then
        local town = string.match(path, "Content/Towns/(%a+)$")
        local at = TOWN_AT[town] or { 0, 0 }
        nodes[path] = { Enable = false, SetEnable = function(self, value) self.Enable = value end,
            TextGUIRendererComponent = { Text = "" }, SpriteGUIRendererComponent = {}, ButtonComponent = { Enable = true },
            UITransformComponent = { RectSize = Vector2(740, 810), anchoredPosition = Vector2(at[1], at[2]), ZRotation = 0 } }
        if path == "Overlay/Window/Side" then
            -- (#132) The town list floats over the viewport: 420 x 800, its pivot at the middle of its right edge, which is on the screen at screenPivot. Here the view is
            -- 740 wide and centred on the screen origin, so the list (screen x from 280 to 700) covers the right edge of it and reaches beyond.
            nodes[path].UITransformComponent.RectSize = Vector2(420, 800)
            nodes[path].UITransformComponent.Pivot = Vector2(1, 0.5)
            nodes[path].UITransformComponent.screenPivot = Vector2(700, 0)
        end
    end
    return nodes[path]
end
-- One screen pixel is unitsPerPixel UI units (0.5 on a screen twice as dense as the 1920 canvas); the view is centred on the screen origin here.
local unitsPerPixel = 1
_UILogic = {
    ScreenWidth = 1920, ScreenHeight = 1080,
    -- A point as a transform sees it: measured from its pivot (the fake list has one on the screen, the others are at the screen origin).
    ScreenToLocalUIPosition = function(_, point, transform)
        local origin = transform ~= nil and transform.screenPivot or Vector2(0, 0)
        -- (#132) in the units of the transform itself: one drawn at a scale (the viewport, at BaseScale) has that many screen pixels in a unit
        local scale = transform ~= nil and transform.UIScale ~= nil and transform.UIScale.x or 1
        return Vector2((point.x - origin.x) * unitsPerPixel / scale, (point.y - origin.y) * unitsPerPixel / scale)
    end,
    ScreenToUIPosition = function(_, point) return Vector2(point.x * unitsPerPixel, point.y * unitsPerPixel) end,
}
local cursorAt = Vector2(0, 0)
_InputService.GetCursorPosition = function() return cursorAt end
_EntityService = { GetEntityByPath = function(_, path) return node((string.gsub(path, "^/ui/WorldMapGroup/", ""))) end }
_UserService.LocalPlayer = { CurrentMapName = "zuoying" }
_FormationLobby = { IsTownPanelOpen = function() return false end }
function _FactionWarUI:HighlightedTownName(town) return "<c>" .. doc.TownNames[town] .. "</c>" end
function _FactionWarUI:ShowTownStatus() end
local calls
local function fresh()
    nodes = {}
    calls = { open = 0, close = 0, select = 0, attack = {} }
    ui:OnBeginPlay()
    ui._T.mapName = _UserService.LocalPlayer.CurrentMapName
    -- (#132) The scenarios below were written for a viewport drawn at scale 1, where a screen pixel is a unit of the viewport; the one about the base scale sets it back.
    ui.BaseScale = 1
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
check(text("Confirm/Window/Title") == "進攻 <color=#D64A3D>鼓山</color>？", "the title names the target")
check(text("Confirm/Window/Origin") == "出發城 <color=#4580E0>左營</color>　兵力 100 / 100" and text("Confirm/Window/Target") == "目標城 <color=#D64A3D>鼓山</color>　兵力 55 / 100", "the departure and target strengths")
check(text("Confirm/Window/Note") == "" and text("Confirm/Window/Status") == "", "an ordinary town has no capital note")
check(node("Confirm/Window/Yes").ButtonComponent.Enable and node("Confirm/Window/No").ButtonComponent.Enable, "both buttons answer")
ui:ShowBoard(towns({ gushan = 35, zuoying = 90 }), links)
check(text("Confirm/Window/Origin") == "出發城 <color=#4580E0>左營</color>　兵力 90 / 100" and text("Confirm/Window/Target") == "目標城 <color=#D64A3D>鼓山</color>　兵力 35 / 100", "a pushed board updates the open window")
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
local zoomBehind = ui._T.zoom
ui:HandleWheel({ ScrollDelta = 1 })
check(ui._T.zoom == zoomBehind, "the wheel does not zoom behind the confirmation")

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
check(ui._T.zoom == zoomBehind, "still no zoom")

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
check(text("Confirm/Window/Note") == "打贏不扣主城兵力" and text("Confirm/Window/Title") == "進攻 <color=#D64A3D>鹽埕</color>？", "a capital target adds the note that winning takes no strength")
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
local GONE_ENEMY, GONE_ALLY = "<color=#D64A3D>鼓山</color> 已不能進攻", "<color=#4580E0>鼓山</color> 已不能進攻"
local TARGET_GONE = GONE_ENEMY
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

-- #131: the share starts from the first town. Use the canonical 100-strength capital from the map board.
local capital = map:Board(doc:InitialTowns()).towns[1]
check(capital.capital and capital.strength == 100, "canonical capital arrives at full strength")
local function endOf(owner, strength) return { owner = owner, strength = strength } end
local function split(faction, a, b, expected, label)
    check(math.abs(ui:FrontlineSplit(faction, a, b) - expected) < 1e-9, label)
end
split("A", endOf("A", 80), endOf("B", 40), 2 / 3, "80 to 40 puts the seam two thirds from the first town")
split("B", endOf("A", 80), endOf("B", 40), 2 / 3, "reversing the viewer does not move the seam")
split("A", endOf("B", 40), endOf("A", 80), 1 / 3, "reversing the endpoints mirrors the seam")
split("A", capital, endOf("B", 0), 1, "100-strength capital against zero fills the whole line")
split("A", endOf("B", 0), capital, 0, "zero at the first endpoint leaves the line to the capital")
split("A", capital, endOf("B", 100), 0.5, "full-strength opponents meet in the middle")
split("A", endOf("A", 0), endOf("B", 0), 0.5, "two zero-strength opponents meet in the middle")
split("A", endOf("A", 20), endOf("A", 80), 1, "two allies use a single segment regardless of strength")
split("A", endOf("B", 20), endOf("B", 80), 1, "two enemies use a single segment regardless of strength")
split("", endOf("A", 80), endOf("B", 40), 1, "without a viewer faction, show one neutral segment")

fresh()
ui:Open()
ui:ShowBoard(towns({ zuoying = 100, gushan = 0 }), links)
local tug = "Overlay/Window/Map/Content/Links/Link2"
local first, second = node(tug .. "/First"), node(tug .. "/Second")
check(first.Enable and not second.Enable and first.SpriteGUIRendererComponent.Color == _FactionWarUI.NeutralTownColor, "a board arriving before the faction paints a single grey bar")
ui:ReceiveViewFaction("A")
check(first.Enable and not second.Enable and first.SpriteGUIRendererComponent.Color == _FactionWarUI.AllyTownColor, "100 against 0 paints solely the ally's colour when the faction is read")
ui:ShowBoard(towns({ zuoying = 0, gushan = 100 }), links)
check(not first.Enable and second.Enable and second.SpriteGUIRendererComponent.Color == _FactionWarUI.EnemyTownColor, "0 against 100 paints solely the enemy's colour after the push")

-- Only the strength moves: the window keeps both numbers current and stays open.
openConfirm()
ui:ShowBoard(towns({ gushan = 20, zuoying = 70 }), links)
check(node("Confirm").Enable and ui._T.selected == "gushan" and not ui._T.pending, "a strength change keeps the confirmation window open")
check(text("Confirm/Window/Origin") == "出發城 <color=#4580E0>左營</color>　兵力 70 / 100" and text("Confirm/Window/Target") == "目標城 <color=#D64A3D>鼓山</color>　兵力 20 / 100", "and updates both numbers")
check(text(rowOf("gushan") .. "/Value") == "20/100", "the side list still shows the strength")
check(calls.select == 0 and notice() == nil and node(rowOf("gushan") .. "/Pick").Enable, "no request, no line, the same pick buttons")

-- A town changed hands but the picked one is still a target: the list is asked for again and the window stays.
openConfirm()
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
check(calls.select == 1 and ui._T.relistsOutstanding == 1, "a town that changed hands asks the server for the list")
ready("zuoying", { gushan }, towns({}, { yancheng = "A" }))
check(node("Confirm").Enable and ui._T.selected == "gushan" and notice() == nil and ui._T.relistsOutstanding == 0, "a picked town that is still listed keeps its window and shows no line")

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
check(notice() == GONE_ALLY, "the side panel says the town can no longer be attacked: " .. tostring(notice()))
check(node(rowOf("yancheng") .. "/Pick").Enable and not node(rowOf("gushan") .. "/Pick").Enable, "and the list is redrawn")
check(not node("Message").Enable and ui._T.message == nil and calls.close == 0, "no message window and the map is not closed")
ui:Pick("yancheng")
check(notice() == nil and ui._T.selected == "yancheng", "the line goes away on the next pick")
-- Nothing is left to pick at all (the server answers NO_TARGETS): same line, everything dimmed, map still open.
openConfirm()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(ui._T.open and ui._T.mode == "select" and not node("Confirm").Enable and ui._T.selected == nil, "NO_TARGETS to the map's own relist keeps the map and closes the window")
check(notice() == GONE_ALLY and not node("Message").Enable and calls.close == 0, "with the same line and no message window")
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
check(notice() == GONE_ALLY, "setup: a line is shown")
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
check(notice() == TARGET_GONE and calls.select == 1 and ui._T.relistsOutstanding == 1, "the line names the town and the list is asked for again")
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(notice() == TARGET_GONE and node(rowOf("yancheng") .. "/Pick").Enable and not node(rowOf("gushan") .. "/Pick").Enable, "the relisted answer redraws the list and the line stays while the town is not listed")
openConfirm()
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
ready("zuoying", { gushan }, towns())
check(notice() == TARGET_GONE and node(rowOf("gushan") .. "/Pick").Enable and not node("Confirm").Enable, "a refusal's prompt stays when the new list still has the town: the player must be told the pick was refused")
ui:Pick("gushan")
check(notice() == nil and ui._T.selected == "gushan", "and goes with the next pick")
openConfirm()
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
ready("zuoying", { gushan }, towns())
ui:Close()
check(notice() == nil, "or with closing the map")
openConfirm()
ui:ConfirmAttack()
ui:ShowAttackResult("INVALID")
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(notice() == TARGET_GONE and ui._T.open, "a nothing-to-pick answer to the refusal's relist keeps the prompt")
ready("zuoying", { gushan }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ready("zuoying", { gushan }, towns({}, { yancheng = "A" }))
check(notice() == TARGET_GONE and node(rowOf("gushan") .. "/Pick").Enable, "and so does another list that has the town")
-- The map's own relist drops the pick while the request is on its way: the answer to it still closes the map for the siege panel.
openConfirm()
ui:ConfirmAttack()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(not ui._T.pending and not node("Confirm").Enable and notice() == GONE_ALLY, "a relist answered while waiting also closes the window and says so")
ui:ShowAttackResult("QUEUING")
check(not ui._T.open and not node("Overlay").Enable and calls.close == 1, "and the QUEUING that was already on its way still closes the map")
openConfirm()
ui:ConfirmAttack()
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
ui:ShowAttackResult("INVALID")
check(notice() == GONE_ALLY and not ui._T.pending and ui._T.open, "an INVALID after the relist already dropped the pick keeps the line and does not get stuck")
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

-- Two owner changes in quick succession send two requests; every answer to them is the open map's own.
fresh()
ready("zuoying", { gushan, yancheng }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:ShowBoard(towns({}, { yancheng = "A", gushan = "A" }), links)
check(calls.select == 2 and ui._T.relistsOutstanding == 2, "two owner changes ask twice and are both outstanding")
ready("zuoying", { gushan }, towns({}, { yancheng = "A" }))
check(ui._T.relistsOutstanding == 1 and ui._T.open and not node("Message").Enable, "the first answer leaves one outstanding")
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(ui._T.open and ui._T.mode == "select" and not node("Message").Enable and ui._T.message == nil and calls.close == 0, "the second answer (NO_TARGETS) is handled in the open map: no message window, the map stays")
check(ui._T.relistsOutstanding == 0 and notice() == "目前沒有可進攻的相鄰敵城", "nothing is outstanding and the line says no target is left")
everythingDim("two relists")
fresh()
ready("zuoying", { gushan, yancheng }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:ShowBoard(towns({}, { yancheng = "A", zuoying = "B" }), links)
ready("zuoying", { gushan }, towns({}, { yancheng = "A" }))
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(ui._T.open and ui._T.mode == "select" and not node("Message").Enable and notice() == ORIGIN_GONE and calls.close == 0, "the second answer (NOT_OWNED) is handled in the open map too")
-- An NPC press discards the outstanding relists: its answer is the one the player waits for.
fresh()
ready("zuoying", { gushan, yancheng }, towns())
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:ShowBoard(towns({}, { yancheng = "A", gushan = "A" }), links)
ui:BeginSelect()
check(ui._T.relistsOutstanding == 0, "a new NPC press forgets the earlier relists")
ui:Close()
check(ui._T.relistsOutstanding == 0, "and a closed map has none outstanding")

-- The departure town fell and the player was moved to the capital: a later READY relist is for another town, and the view goes there; the
-- same departure town keeps the player's own zoom and pan.
fresh()
ready("zuoying", { gushan }, towns())
ui:ShowBoard(towns({}, { zuoying = "B" }), links)
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(ui._T.open and ui._T.origin == "zuoying", "setup: the open map shows the fallen departure town")
_UserService.LocalPlayer.CurrentMapName = "nanzih"
ui._T.mapName = "nanzih"
ui:ShowBoard(towns({}, { yancheng = "A" }), links)
ui:ShowSelect("nanzih", "READY", { town = "nanzih", strength = 100, owner = "A", faction = "A" }, { gushan }, { towns = towns(), links = links })
local newOrigin = ui:TownViewPoint(node("Overlay/Window/Map/Content/Towns/nanzih").UITransformComponent.anchoredPosition, ui._T.zoom, ui._T.mapOffset)
check(ui._T.origin == "nanzih" and ui._T.zoom == ui.SelectZoom and math.abs(newOrigin.x) < 1e-6 and math.abs(newOrigin.y) < 1e-6, "a READY relist for another town centres the view on it")
ui:SetMapView(2, Vector2(30, 20))
ui:ShowSelect("nanzih", "READY", { town = "nanzih", strength = 100, owner = "A", faction = "A" }, { gushan }, { towns = towns(), links = links })
check(ui._T.zoom == 2 and ui._T.mapOffset.x == 30 and ui._T.mapOffset.y == 20, "and the same town afterwards keeps the player's view")
_UserService.LocalPlayer.CurrentMapName = "zuoying"
ui._T.mapName = "zuoying"

-- ---- #129: the selection opens zoomed on the departure town, and a town is picked by clicking its crest -------------------------------------
local function near(a, b) return math.abs(a - b) < 1e-6 end
local TOWN = "Overlay/Window/Map/Content/Towns/"
local function anchored(id) return node(TOWN .. id).UITransformComponent.anchoredPosition end
local function viewPointOf(id) return ui:TownViewPoint(anchored(id), ui._T.zoom, ui._T.mapOffset) end
local function screenOf(point) return Vector2(point.x / unitsPerPixel, point.y / unitsPerPixel) end
local function press(point) ui:BeginMapDrag({ TouchId = -1, TouchPoint = point }) end
local function release(point) ui:EndMapDrag({ TouchId = -1, TouchPoint = point }) end
local function click(point) press(point) release(point) end
local function markOn(id, name) return node(TOWN .. id .. "/" .. name).Enable end
local function confirmTexts()
    local parts = {}
    for _, part in ipairs({ "Title", "Origin", "Target", "Note", "Status" }) do table.insert(parts, text("Confirm/Window/" .. part)) end
    return table.concat(parts, "|")
end
local function focus(id, zoom) ui:SetMapView(zoom, ui:CenterOffset(anchored(id), zoom)) end
local yanchengTarget = { town = "yancheng", name = "鹽埕", capital = true, strength = 100, owner = "B" }

-- The pure decisions.
check(ui.MinHitPx >= 24 and ui.SelectZoom >= 4, "the hit reach is at least 24 screen pixels and the selection starts at 4x")
check(ui:IsClick(0) and ui:IsClick(ui.ClickSlopPx) and not ui:IsClick(ui.ClickSlopPx + 1), "a press that stays within the slop is a click, one that travelled further is a drag")
check(near(ui:IconScale(1), 0.25) and near(ui:IconScale(4), 0.64) and ui:IconScale(12) == 1, "the crest scale: small in the overview, full size from 7x")
for _, zoom in ipairs({ 1, 2, 4, 8, 12 }) do
    for _, pxPerUnit in ipairs({ 0.5, 1, 2, 4 }) do
        local radius = ui:HitRadius(zoom, pxPerUnit)
        check(radius * pxPerUnit >= ui.MinHitPx - 1e-9 and radius >= ui.CrestHitReach * ui:IconScale(zoom) - 1e-9, "the hit radius is at least 24 screen px and at least the crest at zoom " .. zoom .. " density " .. pxPerUnit)
    end
end
local views = { nanzih = Vector2(0, 0), zuoying = Vector2(10, 0), gushan = Vector2(100, 0), yancheng = Vector2(300, 300) }
check(ui:TownAt(Vector2(98, 0), views, 24) == "gushan" and ui:TownAt(Vector2(124, 0), views, 24) == "gushan", "a point within the radius (the edge included) is on the town")
check(ui:TownAt(Vector2(125, 0), views, 24) == "" and ui:TownAt(Vector2(0, 50), views, 24) == "", "a point outside every radius is on no town")
check(ui:TownAt(Vector2(7, 0), views, 24) == "zuoying" and ui:TownAt(Vector2(3, 0), views, 24) == "nanzih", "where two crests overlap the nearer one wins")
check(ui:TownAt(Vector2(5, 0), views, 24) == "nanzih", "and a tie goes to the first town of the map order")
check(ui:TownAt(Vector2(0, 0), {}, 24) == "", "no towns, no hit")
local centre = ui:CenterOffset(Vector2(-210.5, -197.5), 4)
check(near(centre.x, 842) and near(centre.y, 790), "centring on a town moves the content by minus its position times the zoom")
local centred = ui:TownViewPoint(Vector2(-210.5, -197.5), 4, centre)
check(near(centred.x, 0) and near(centred.y, 0), "and the town is then at the middle of the viewport")
fresh()
check(ui:CrestState("gushan") == "plain", "in the view no crest is marked")
ready("zuoying", { gushan }, towns())
check(ui:CrestState("gushan") == "selectable" and ui:CrestState("zuoying") == "dimmed" and ui:CrestState("nanzih") == "dimmed" and ui:CrestState("yancheng") == "dimmed", "in the selection only the listed town is selectable, the rest dimmed")
ui:Pick("gushan")
check(ui:CrestState("gushan") == "selected" and ui:CrestState("yancheng") == "dimmed", "the picked town is selected")

-- The selection opens zoomed on the departure town; the view opens at the full overview.
fresh()
ready("zuoying", { gushan }, towns())
check(ui._T.zoom == ui.SelectZoom and near(node("Overlay/Window/Map/Content").UITransformComponent.UIScale.x, ui.SelectZoom), "the selection opens at 4x")
local at = viewPointOf("zuoying")
check(near(at.x, 0) and near(at.y, 0), "centred on the departure town")
check(ui:Ui(TOWN .. "zuoying/Name").Visible == true, "at 4x the town names are shown")
fresh()
_UserService.LocalPlayer.CurrentMapName = "gushan"
ui._T.mapName = "gushan"
ui:ShowSelect("gushan", "READY", { town = "gushan", strength = 100, owner = "A", faction = "A" }, { yanchengTarget }, { towns = towns({}, { gushan = "A" }), links = links })
at = viewPointOf("gushan")
check(ui._T.zoom == ui.SelectZoom and near(at.x, 0) and near(at.y, 0), "the departure town is the one the answer names, whichever town it is")
_UserService.LocalPlayer.CurrentMapName = "zuoying"
fresh()
ui:Open()
check(ui._T.zoom == 1 and near(ui._T.mapOffset.x, 0) and near(ui._T.mapOffset.y, 0), "the view opens at the full overview")
ui:ShowBoard(towns({ gushan = 40 }), links)
check(ui._T.zoom == 1, "and a pushed board keeps it")
ui:SetMapView(2, Vector2(30, 20))
ui:ShowSelect("zuoying", "READY", header, { gushan }, { towns = towns(), links = links })
at = viewPointOf("zuoying")
check(ui._T.zoom == ui.SelectZoom and near(at.x, 0) and near(at.y, 0), "the NPC press while the view is open switches to the selection zoomed on the departure town")
ui:SetMapView(2, Vector2(30, 20))
ui:ShowSelect("zuoying", "READY", header, { gushan }, { towns = towns(), links = links })
check(ui._T.zoom == 2 and near(ui._T.mapOffset.x, 30) and near(ui._T.mapOffset.y, 20), "a refreshed list while the selection is open does not take the view back")
ui:Close()
ready("zuoying", { gushan }, towns())
check(ui._T.zoom == ui.SelectZoom, "reopening the selection zooms again")

-- Wheel zoom and drag pan are what they were.
fresh()
ready("zuoying", { gushan }, towns())
ui:HandleWheel({ ScrollDelta = 1 })
check(near(ui._T.zoom, ui.SelectZoom * ui.WheelZoomFactor), "the wheel still zooms in the selection")
ui:SetMapView(4, ui:CenterOffset(anchored("zuoying"), 4))
local before = ui._T.mapOffset
press(Vector2(0, 0))
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(30, -20) })
release(Vector2(30, -20))
check(near(ui._T.mapOffset.x, before.x + 30 / ui.BaseScale) and near(ui._T.mapOffset.y, before.y - 20 / ui.BaseScale), "a drag still pans the map at screen speed (a unit of the viewport is BaseScale screen pixels, #132)")
ui:SetMapView(4, Vector2(1e6, 1e6))
check(near(ui._T.mapOffset.x, (740 * 4 - 740) / 2) and near(ui._T.mapOffset.y, (810 * 4 - 810) / 2), "and the edges still clamp")
for _ = 1, 10 do ui:HandleWheel({ ScrollDelta = -3 }) end
check(ui._T.zoom == 1 and near(ui._T.mapOffset.x, 0) and near(ui._T.mapOffset.y, 0), "zooming out still restores the overview")

-- (#132) The town list floats over part of the viewport and takes the touches that land on it: the wheel on it does nothing, beside it the wheel zooms as before.
fresh()
ready("zuoying", { gushan }, towns())
local zoomOnOpen = ui._T.zoom
cursorAt = Vector2(300, 0)
check(ui:IsOverTownList(cursorAt) and not ui:IsOverTownList(Vector2(-200, 0)) and not ui:IsOverTownList(Vector2(300, 450)), "a point is on the list inside its rectangle, measured from its pivot")
ui:HandleWheel({ ScrollDelta = 1 })
check(ui._T.zoom == zoomOnOpen, "the wheel over the town list does nothing")
cursorAt = Vector2(-200, 0)
ui:HandleWheel({ ScrollDelta = 1 })
check(near(ui._T.zoom, zoomOnOpen * ui.WheelZoomFactor), "and on the map beside it the wheel zooms")
cursorAt = Vector2(0, 0)

-- The view is remembered by this client: reopening restores the zoom and offset the player left with.
fresh()
ui:Open()
check(ui._T.zoom == 1, "the first opening shows the whole map")
ui:SetMapView(5, Vector2(40, -30))
ui:Close()
ui:Open()
check(ui._T.zoom == 5 and near(ui._T.mapOffset.x, 40) and near(ui._T.mapOffset.y, -30), "the view reopens where it was left")
ui:Close()
fresh()
check(ui._T.hasMemory == false, "nothing is remembered by a new client")
ready("zuoying", { gushan }, towns())
check(ui._T.zoom == ui.SelectZoom and near(viewPointOf("zuoying").x, 0), "a first selection focuses the departure town")
ui:SetMapView(2, Vector2(250, 200))
ui:Close()
ready("zuoying", { gushan }, towns())
check(ui._T.zoom == 2 and near(ui._T.mapOffset.y, 200), "a later selection keeps the remembered view when it still shows the departure town")
ui:Close()
ui:Open()
ui:SetMapView(12, Vector2(1e6, 1e6))
ui:Close()
ready("zuoying", { gushan }, towns())
check(ui._T.zoom == ui.SelectZoom and near(viewPointOf("zuoying").x, 0), "and focuses it when the remembered view does not show it")

-- Town names take the stance colour: ally blue, enemy red (the faction is A here: zuoying is ally, gushan enemy); white while the faction is unknown.
fresh()
ready("zuoying", { gushan }, towns())
local function nameColor(path) return node(path).TextGUIRendererComponent.FontColor end
local ally, enemy = nameColor("Overlay/Window/Map/Content/Towns/zuoying/Name"), nameColor("Overlay/Window/Map/Content/Towns/gushan/Name")
check(ally.b > ally.r and enemy.r > enemy.b, "an ally town's name is blue and an enemy town's red on the map")
local rowAlly, rowEnemy = nameColor("Overlay/Window/Side/Rows/zuoying/Name"), nameColor("Overlay/Window/Side/Rows/gushan/Name")
check(rowAlly.b > rowAlly.r and rowEnemy.r > rowEnemy.b, "and in the list")
fresh()
ui:ShowBoard(towns(), links)
ui:ShowFaction("LOADING")
ui:Open()
local unknownName = nameColor("Overlay/Window/Map/Content/Towns/gushan/Name")
check(unknownName.r == 1 and unknownName.g == 1 and unknownName.b == 1, "a name stays white until the viewer's faction is known")

-- Hover: the pickable crest under the pointer is drawn larger, nothing else is.
fresh()
ready("zuoying", { gushan }, towns())
local function crestScale(id) return node("Overlay/Window/Map/Content/Towns/" .. id).UITransformComponent.UIScale.x end
local baseSize = crestScale("gushan")
cursorAt = ui:TownViewPoint(node("Overlay/Window/Map/Content/Towns/gushan").UITransformComponent.anchoredPosition, ui._T.zoom, ui._T.mapOffset)
ui:UpdateHover()
check(ui._T.hover == "gushan" and near(crestScale("gushan"), baseSize * ui.HoverScale), "the pickable crest under the pointer is enlarged")
cursorAt = Vector2(-300, 300)
ui:UpdateHover()
check(ui._T.hover == "" and near(crestScale("gushan"), baseSize), "and back to its size when the pointer leaves")
cursorAt = ui:TownViewPoint(node("Overlay/Window/Map/Content/Towns/zuoying").UITransformComponent.anchoredPosition, ui._T.zoom, ui._T.mapOffset)
ui:UpdateHover()
check(ui._T.hover == "", "a crest that cannot be picked is not enlarged")
cursorAt = Vector2(0, 0)

-- (#132) The viewport is drawn at the base scale: its own unit is that many canvas units, so a click reaches as many screen pixels as before.
fresh()
node(ui.ViewPath).UITransformComponent.UIScale = Vector3(1.2, 1.2, 1)
check(near(ui:ScreenPixelsPerUnit(), 1.2), "a unit of the viewport is 1.2 screen pixels")
check(near(ui:HitRadius(1, ui:ScreenPixelsPerUnit()) * ui:ScreenPixelsPerUnit(), ui.MinHitPx), "the minimum reach is still MinHitPx screen pixels")
node(ui.ViewPath).UITransformComponent.UIScale = nil
check(near(ui:ScreenPixelsPerUnit(), 1), "and an unscaled viewport is what it was")

-- (#132) At the base scale every distance in the viewport is in its own units: 1.2 screen pixels to a unit. Opening the map draws the viewport at that scale, a drag
-- of 30 screen pixels moves the map 25 units, and the reach of a click is the same number of screen pixels as before.
fresh()
ui.BaseScale = 1.2
ready("zuoying", { gushan }, towns())
check(near(node(ui.ViewPath).UITransformComponent.UIScale.x, 1.2) and near(node(ui.ViewPath).UITransformComponent.UIScale.y, 1.2), "opening the map draws the viewport at the base scale")
check(near(ui:ScreenPixelsPerUnit(), 1.2), "so a unit of the viewport is 1.2 screen pixels")
ui:SetMapView(4, ui:CenterOffset(anchored("zuoying"), 4))
local scaledBefore = ui._T.mapOffset
press(Vector2(0, 0))
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(30, -12) })
release(Vector2(30, -12))
check(near(ui._T.mapOffset.x, scaledBefore.x + 25) and near(ui._T.mapOffset.y, scaledBefore.y - 10), "a drag of 30 x 12 screen pixels moves the map 25 x 10 units")
focus("gushan", 4)
local crest = viewPointOf("gushan")
local crestOnScreen = Vector2(crest.x * 1.2, crest.y * 1.2)
click(Vector2(crestOnScreen.x - 20, crestOnScreen.y))
check(ui._T.selected == "gushan", "a click 20 screen pixels from the crest picks it")
ui:Decline()
click(Vector2(crestOnScreen.x - 40, crestOnScreen.y))
check(ui._T.selected == nil, "one 40 screen pixels away picks nothing")
ui.BaseScale = 1

-- A click on the selectable crest opens the same confirmation as the row, and nothing was asked of the server.
fresh()
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
local rowTexts = confirmTexts()
fresh()
ready("zuoying", { gushan }, towns())
local gushanAt = viewPointOf("gushan")
click(gushanAt)
check(ui._T.selected == "gushan" and node("Confirm").Enable, "a click on the selectable crest opens the confirmation")
check(confirmTexts() == rowTexts and node("Confirm/Window/Yes").ButtonComponent.Enable, "with exactly the texts the row opens")
check(calls.select == 0 and calls.open == 0 and #calls.attack == 0, "a click only opens the window: nothing is sent")
ui:ConfirmAttack()
check(#calls.attack == 1 and calls.attack[1] == "gushan", "and 是 sends the request as for the row")

-- The hit reach holds at every zoom, on screens of every density, and a click far from a crest is nothing.
for _, zoom in ipairs({ 1, 2, 4, 8, 12 }) do
    fresh()
    ready("zuoying", { gushan }, towns())
    focus("gushan", zoom)
    local p = viewPointOf("gushan")
    click(Vector2(p.x - 20, p.y))
    check(ui._T.selected == "gushan", "20 px from the crest picks it at " .. zoom .. "x")
    ui:Decline()
    click(Vector2(p.x - 60, p.y))
    check(ui._T.selected == nil, "60 px from it picks nothing at " .. zoom .. "x")
end
for _, density in ipairs({ 0.5, 2 }) do
    unitsPerPixel = density
    fresh()
    ready("zuoying", { gushan }, towns())
    ui:SetMapView(1, Vector2(0, 0))
    local p = viewPointOf("gushan")
    local inside = ui.MinHitPx * density * 0.9
    local outside = ui.MinHitPx * density * 1.3
    click(screenOf(Vector2(p.x - inside, p.y)))
    check(ui._T.selected == "gushan", "90% of 24 screen px picks it where one pixel is " .. density .. " units")
    ui:Decline()
    click(screenOf(Vector2(p.x - outside, p.y)))
    check(ui._T.selected == nil, "130% of 24 screen px does not")
end
unitsPerPixel = 1

-- A town that cannot be picked reacts to nothing.
fresh()
ready("zuoying", { gushan }, towns())
for _, id in ipairs({ "zuoying", "nanzih", "yancheng" }) do
    click(viewPointOf(id))
    check(ui._T.selected == nil and not node("Confirm").Enable and #calls.attack == 0, id .. ": a click on a town the server did not list does nothing")
end
ready("zuoying", { gushan, yanchengTarget }, towns())
click(viewPointOf("gushan"))
click(viewPointOf("yancheng"))
check(ui._T.selected == "gushan", "a second click cannot replace the town being confirmed")
ui:Decline()
click(viewPointOf("yancheng"))
check(ui._T.selected == "yancheng", "a listed capital is picked like any other target")

-- A drag is not a click, wherever it starts or ends.
fresh()
ready("zuoying", { gushan }, towns())
local p = viewPointOf("gushan")
local start = ui._T.mapOffset
press(p)
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 40, p.y) })
release(Vector2(p.x + 40, p.y))
check(ui._T.selected == nil and near(ui._T.mapOffset.x, start.x + 40), "a drag that starts on the crest picks nothing, and pans")
p = viewPointOf("gushan")
press(Vector2(p.x - 40, p.y))
ui:DragMap({ TouchId = -1, TouchPoint = p })
release(p)
check(ui._T.selected == nil, "a drag that ends on the crest picks nothing")
p = viewPointOf("gushan")
press(p)
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 50, p.y) })
ui:DragMap({ TouchId = -1, TouchPoint = p })
release(p)
check(ui._T.selected == nil, "a drag that returns to where it started is still a drag")
p = viewPointOf("gushan")
press(p)
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 6, p.y + 8) })
release(Vector2(p.x + 6, p.y + 8))
check(ui._T.selected == "gushan", "a press that moved exactly the slop (10 px) is still a click")
ui:Decline()
p = viewPointOf("gushan")
press(p)
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 8, p.y + 6) })
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 7, p.y + 5) })
release(Vector2(p.x + 7, p.y + 5))
check(ui._T.selected == "gushan", "a jitter within the slop picks the crest under the pointer")
ui:Decline()
p = viewPointOf("gushan")
press(p)
ui:DragMap({ TouchId = -1, TouchPoint = Vector2(p.x + 7, p.y + 8) })
release(Vector2(p.x + 7, p.y + 8))
check(ui._T.selected == nil, "a press that moved 10.6 px is a drag")
ui:EndMapDrag({ TouchId = 5, TouchPoint = p })
check(ui._T.selected == nil, "a release of another pointer is nothing")

-- No reaction where no selection is under way or the click is outside the map.
fresh()
ui:Open()
focus("gushan", 4)
click(viewPointOf("gushan"))
check(ui._T.selected == nil and not node("Confirm").Enable, "the view cannot pick by clicking")
fresh()
ready("zuoying", { gushan }, towns())
local mapView = node("Overlay/Window/Map").UITransformComponent
mapView.RectSize = Vector2(100, 100)
click(viewPointOf("gushan"))
check(ui._T.selected == nil, "a click outside the viewport rectangle picks nothing (a crest scrolled out of sight stays out)")
mapView.RectSize = Vector2(740, 810)
ui._T.message = "text"
click(viewPointOf("gushan"))
check(ui._T.selected == nil, "behind a message window a click picks nothing")
ui._T.message = nil
ui:Close()
click(viewPointOf("gushan"))
check(ui._T.selected == nil and ui._T.dragId == nil, "a closed map takes no click")

-- The look: a mark on every selectable crest, a frame on the selected one, nothing in the view.
fresh()
ready("zuoying", { gushan }, towns())
for _, id in ipairs(doc.TownOrder) do
    check(markOn(id, "Mark") == (id == "gushan") and not markOn(id, "Frame"), id .. ": only the selectable crest is marked, none is framed yet")
end
click(viewPointOf("gushan"))
check(markOn("gushan", "Mark") and markOn("gushan", "Frame") and not markOn("zuoying", "Frame") and not markOn("yancheng", "Mark"), "the picked crest is framed and stays marked")
ui:Decline()
check(markOn("gushan", "Mark") and not markOn("gushan", "Frame"), "No takes the frame off")
ui:Pick("gushan")
ready("zuoying", {}, towns())
check(not markOn("gushan", "Mark") and not markOn("gushan", "Frame"), "a refreshed list without the town takes both off")
ready("zuoying", { gushan }, towns())
ui:Pick("gushan")
ui:Close()
for _, id in ipairs(doc.TownOrder) do check(not markOn(id, "Mark") and not markOn(id, "Frame"), id .. ": closing the map clears the marks") end
ui:Open()
for _, id in ipairs(doc.TownOrder) do check(not markOn(id, "Mark") and not markOn(id, "Frame"), id .. ": the view has no marks") end
for _, id in ipairs(doc.TownOrder) do
    check(node(TOWN .. id .. "/Crest").SpriteGUIRendererComponent.Color.a == 1 and node("Overlay/Window/Map/Content/Districts/" .. id).SpriteGUIRendererComponent.Color.a == ui.DistrictAlpha, id .. ": and no town is dimmed")
end

-- ---- #128 with #129: the invalidation handling and the crest clicks share one state ------------------------------------------------------
local function crestDim(id) return node(TOWN .. id .. "/Crest").SpriteGUIRendererComponent.Color.a == ui.DimCrestAlpha end
local function allCrestsDim(label)
    for _, id in ipairs(doc.TownOrder) do
        check(ui:CrestState(id) == "dimmed" and crestDim(id) and not markOn(id, "Mark") and not markOn(id, "Frame"), label .. ": " .. id .. " is dimmed, unmarked and unframed")
    end
end
local function openCrestConfirm()
    fresh()
    ready("zuoying", { gushan, yancheng }, towns())
    focus("gushan", 4)
    local p = viewPointOf("gushan")
    click(p)
    check(node("Confirm").Enable and ui._T.selected == "gushan" and markOn("gushan", "Frame") and markOn("yancheng", "Mark") and not crestDim("gushan"), "setup: a crest click is being confirmed, its crest framed")
    return p
end

-- Ownership changes while a crest-clicked confirmation is open and the pick is gone: the window closes, the line names the town, the crest dims.
local p = openCrestConfirm()
local zoomBefore = ui._T.zoom
ui:ShowBoard(towns({}, { gushan = "A" }), links)
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(not node("Confirm").Enable and ui._T.selected == nil and notice() == GONE_ALLY, "an owner change closes the crest-clicked window and says why")
check(ui:CrestState("gushan") == "dimmed" and crestDim("gushan") and not markOn("gushan", "Frame") and not markOn("gushan", "Mark"), "the town's crest dims and loses its frame and mark")
check(ui:CrestState("yancheng") == "selectable" and markOn("yancheng", "Mark") and not crestDim("yancheng"), "the remaining target keeps its mark")
check(ui._T.zoom == zoomBefore, "and the player's view is not pulled back")
click(p)
check(ui._T.selected == nil and not node("Confirm").Enable and #calls.attack == 0, "a click on the dimmed crest does nothing")
click(viewPointOf("yancheng"))
check(ui._T.selected == "yancheng" and notice() == nil and markOn("yancheng", "Frame"), "a click on the target that is left opens its window and clears the line")

-- Strength only: the crest-clicked window follows the numbers, the crest keeps its frame.
openCrestConfirm()
ui:ShowBoard(towns({ gushan = 20 }), links)
check(node("Confirm").Enable and markOn("gushan", "Frame") and text("Confirm/Window/Target") == "目標城 <color=#D64A3D>鼓山</color>　兵力 20 / 100" and notice() == nil, "a strength change keeps the window, its numbers and the frame")

-- The departure town falls (NOT_OWNED to the map's own relist): window closed, one line, every crest and row dimmed, nothing can be clicked.
p = openCrestConfirm()
ui._T.relistsOutstanding = 1
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
check(ui._T.open and not node("Confirm").Enable and notice() == ORIGIN_GONE and not node("Message").Enable, "the departure town falling closes the window and says so, the map stays")
allCrestsDim("NOT_OWNED")
everythingDim("NOT_OWNED")
click(p)
click(viewPointOf("yancheng"))
check(ui._T.selected == nil and #calls.attack == 0 and not node("Confirm").Enable, "no crest reacts to a click")
check(ui._T.zoom == 4, "the zoom stays")

-- Nothing left to attack (NO_TARGETS) with a crest pick open: same state as above, with the town named.
p = openCrestConfirm()
ui._T.relistsOutstanding = 1
ui:ShowSelect("zuoying", "NO_TARGETS", {}, {}, {})
check(notice() == TARGET_GONE and not node("Confirm").Enable, "NO_TARGETS closes the crest-clicked window with the town named")
allCrestsDim("NO_TARGETS")
click(p)
check(ui._T.selected == nil and #calls.attack == 0, "and the crest does not react")

-- 是 on a crest-clicked window answered INVALID: the waiting ends, the frame goes, the list is asked for again.
openCrestConfirm()
ui:ConfirmAttack()
check(ui._T.pending and calls.attack[1] == "gushan", "setup: the attack was sent for the crest's town")
ui:ShowAttackResult("INVALID")
check(not ui._T.pending and not node("Confirm").Enable and notice() == TARGET_GONE and calls.select == 1, "INVALID ends the waiting, closes the window and names the town")
check(not markOn("gushan", "Frame"), "the frame is gone with it")
ready("zuoying", { yancheng }, towns({}, { gushan = "A" }))
check(ui:CrestState("gushan") == "dimmed" and crestDim("gushan") and ui:CrestState("yancheng") == "selectable", "the relisted answer dims the town's crest and leaves the other selectable")

-- Closing the map clears the crest states and the line together.
openCrestConfirm()
ui._T.relistsOutstanding = 1
ui:ShowSelect("zuoying", "NOT_OWNED", {}, {}, {})
ui:Close()
check(notice() == nil and ui._T.mode == "view" and not markOn("gushan", "Frame") and not markOn("yancheng", "Mark"), "closing the map clears the line, the marks and the frame")

print("[VRF][TargetSelect] target selection rules PASS checks=" .. tostring(checks))
