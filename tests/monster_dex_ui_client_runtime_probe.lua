-- Run in a fresh Maker Play test with context=client, after the lobby is ready (formationlobby, idle, formation loaded).
-- Drives the monster dex only through the connected buttons' native click events and reads the public snapshot plus the
-- authored UI. Matchmaking states are synthetic observations of the lobby's own receiver; nothing is queued or stored.
-- Stop Play afterwards to discard those observations.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][MonsterDexUIProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][MonsterDexUIProbe][FAIL] " .. message) end
end

local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) / 0.1) do
        if predicate() then return true end
        wait(0.1)
    end
    return predicate()
end

local BOOK_RUID = "0a782ef3897543b593bda6bd1763f978"
local EXPECTED_NAMES = { "菇菇寶貝", "短刃龍戰士", "血腥哈維", "月光精靈", "日光精靈", "星光精靈", "猴子", "金屬甲蟲", "橡木甲蟲", "暗黑半人馬" }

local dex = _MonsterDex
local function click(entity) entity:SendEvent(ButtonClickEvent()) end
local function sameColor(a, b) return math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01 and math.abs(a.a - b.a) < 0.01 end
local function uiRows()
    local rows = {}
    for _, child in ipairs(dex.listLayout.Entity.Children:ToTable()) do
        if string.sub(child.Name, 1, 4) == "Row_" and child.Enable then table.insert(rows, child) end
    end
    return rows
end
local function lobbyState()
    -- Everything the dex must leave alone: unsaved changes, selections and the matchmaking lock.
    local formation = _FormationEditSession.Snapshot
    local view = _FormationEditSession:View()
    return table.concat({ tostring(view.dirty), tostring(#_FormationEditSession.Draft), tostring(formation.editSlot),
        tostring(formation.saved ~= nil and formation.saved.activeSlot or "none"), tostring(formation.loadState),
        tostring(formation.pending), _MatchFlowInput.Snapshot.state, tostring(_MatchFlowInput:AllowsFormationActions()) }, "|")
end

local observed = 0
local function observe(state)
    observed = observed + 1
    _MatchFlowInput:Observe({ state = state, eventCode = "STATUS", reasonCode = "STATUS", started = 1000, players = 1, busy = false,
        summary = "dex probe", attempt = "dex-probe", sourceRoom = _RoomService.RoomKey, sequenceKey = "dex-probe", sequence = observed })
end

local ok, detail = pcall(function()
    check(await(function()
        return isvalid(_UserService.LocalPlayer) and _UserService.LocalPlayer.CurrentMapName == "formationlobby"
            and _MatchFlowInput:AllowsFormationActions() and isvalid(dex.lobbyButton) and dex.lobbyButton.Enable
    end, 20), "the lobby is ready and the dex entry is usable")

    -- Closed state and entry.
    local snapshot = dex:GetSnapshot()
    check(snapshot.open == false and snapshot.loadState == "IDLE" and snapshot.action == "IDLE" and #snapshot.events == 0,
        "the dex starts closed, idle and with an empty event log")
    check(not dex.book.Enable and not dex.book.EnabledInHierarchy, "the book is hidden before opening")
    check(dex.lobbyButton.Entity.EnabledInHierarchy, "the Maker Play lobby shows the dex entry")
    check(dex.lobbyButton.Entity.TextGUIRendererComponent.Text == "怪物圖鑑", "the entry is labelled 怪物圖鑑")
    local before = lobbyState()

    -- Open through the connected lobby button.
    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and dex:GetSnapshot().loadState == "READY" end), "the entry opens the book and the rows arrive")
    snapshot = dex:GetSnapshot()
    check(dex.book.EnabledInHierarchy, "the book is shown")
    local dimmer = dex.book:GetChildByName("Dimmer", false)
    check(isvalid(dimmer) and dimmer.EnabledInHierarchy and dimmer.SpriteGUIRendererComponent.RaycastTarget, "a raycast dimmer covers the lobby")
    local page = dex.book:GetChildByName("Page", false)
    local ruid = page.SpriteGUIRendererComponent.ImageRUID
    check(tostring(type(ruid) == "string" and ruid or ruid.DataId) == BOOK_RUID, "the book background uses the specified RUID")
    local size, position = page.UITransformComponent.RectSize, page.UITransformComponent.anchoredPosition
    check(math.abs(size.x / size.y - 1024 / 664) < 0.002 and size.x <= 1920 and size.y <= 1080, "the book keeps the picture's aspect ratio inside the canvas")
    check(position.x == 0 and position.y == 0, "the book is centred")
    check(not dex.statusText.Entity.Enable, "the loading line is hidden once the rows are in")

    -- List content and order.
    local latest = _MonsterDexService:GetLatest()
    check(latest ~= nil and #latest == #EXPECTED_NAMES, "the server published every data row (" .. tostring(latest ~= nil and #latest or 0) .. ")")
    local rows = uiRows()
    check(#rows == #EXPECTED_NAMES, "one list row per monster, and the hidden template is not counted (" .. tostring(#rows) .. ")")
    check(not dex.rowTemplate.Enable, "the row template stays hidden")
    for index, row in ipairs(rows) do
        check(row.TextGUIRendererComponent.Text == EXPECTED_NAMES[index] and snapshot.rows[index].monsterName == EXPECTED_NAMES[index]
            and latest[index].monsterId == snapshot.rows[index].monsterId, "row " .. tostring(index) .. " shows " .. EXPECTED_NAMES[index] .. " in table order")
    end

    -- First opening preselects the first monster; the highlight follows the selection.
    local firstId = snapshot.rows[1].monsterId
    check(snapshot.selectedMonsterId == firstId and snapshot.selectedMonsterName == EXPECTED_NAMES[1], "the first monster is preselected")
    check(snapshot.action == "IDLE" and #snapshot.events == 0, "the selection starts idle with no playback events")
    check(dex:GetSelectedRow().monsterId == firstId and dex:GetSelectedRow().standRuid ~= "", "the full server row of the selection is readable")
    local function highlightCheck(selectedIndex, label)
        local highlighted = 0
        for index, row in ipairs(uiRows()) do
            local color = row.SpriteGUIRendererComponent.Color
            if index == selectedIndex then
                if sameColor(color, dex.SelectedRowColor) then highlighted = highlighted + 1 end
            elseif sameColor(color, dex.RowColor) then highlighted = highlighted + 1 end
        end
        check(highlighted == #EXPECTED_NAMES, label)
    end
    highlightCheck(1, "only the first row is highlighted at first")

    -- Click a name to select it.
    click(rows[3])
    snapshot = dex:GetSnapshot()
    check(snapshot.selectedMonsterId == snapshot.rows[3].monsterId and snapshot.selectedMonsterName == EXPECTED_NAMES[3], "clicking a name selects that monster")
    check(snapshot.rows[3].selected and not snapshot.rows[1].selected, "the snapshot marks only the selected row")
    highlightCheck(3, "only the clicked row is highlighted")
    check(snapshot.action == "IDLE" and #snapshot.events == 0, "selecting leaves the stage idle with an empty event log")
    click(rows[3])
    check(dex:GetSnapshot().selectedMonsterId == snapshot.rows[3].monsterId, "clicking the selected name again keeps it")
    check(dex:Select("no_such_monster") == false and dex:GetSnapshot().selectedMonsterId == snapshot.rows[3].monsterId, "an unknown id is rejected without changing the selection")
    snapshot.rows[1].monsterName = "tampered"
    check(dex:GetSnapshot().rows[1].monsterName == EXPECTED_NAMES[1], "the snapshot is a detached copy")

    -- More monsters than fit: the list scrolls.
    local rowHeight = rows[1].UITransformComponent.RectSize.y
    local viewHeight = dex.listLayout.Entity.UITransformComponent.RectSize.y
    check(rowHeight * #rows > viewHeight, "the rows overflow the list view (" .. tostring(rowHeight * #rows) .. " > " .. tostring(viewHeight) .. ") so it scrolls")
    dex.listLayout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 1)
    check(await(function() return dex.listLayout:GetScrollNormalizedPosition().y > 0.9 end, 3), "the list scrolls to its end")
    dex.listLayout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 0)
    check(await(function() return dex.listLayout:GetScrollNormalizedPosition().y < 0.1 end, 3), "the list scrolls back to the top")

    -- Close, then reopen: the selection is kept.
    click(dex.closeButton.Entity)
    snapshot = dex:GetSnapshot()
    check(not snapshot.open and not dex.book.Enable, "the close button hides the book")
    check(snapshot.action == "IDLE" and #snapshot.events == 0, "closing leaves no playback behind")
    check(lobbyState() == before, "opening, selecting and closing change no unsaved edit, selection or lock")
    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and dex:GetSnapshot().loadState == "READY" end), "the book reopens")
    check(dex:GetSnapshot().selectedMonsterId == snapshot.rows[3].monsterId, "the previous selection is still chosen")
    check(#uiRows() == #EXPECTED_NAMES, "a second reply replaces the rows instead of duplicating them (" .. tostring(#uiRows()) .. ")")

    -- Matchmaking: starting while open closes the book, and while matching the entry is disabled.
    observe("QUEUED")
    check(await(function() return not dex:GetSnapshot().open end, 3), "a match starting while the book is open closes it")
    check(await(function() return not dex.lobbyButton.Enable end, 3), "the entry is disabled while queued")
    click(dex.lobbyButton.Entity)
    check(not dex:GetSnapshot().open and not dex.book.Enable, "a click on the disabled entry does not open the book")
    check(dex:Open() == false, "Open is refused while matching")
    for _, state in ipairs({ "WAITING", "TRANSFER", "COMMITTING" }) do
        observe(state)
        check(await(function() return not dex.lobbyButton.Enable end, 3) and dex:Open() == false, "the dex stays closed while " .. state)
    end
    observe("IDLE")
    check(await(function() return dex.lobbyButton.Enable end, 3), "the entry is usable again once matching is over")
    check(dex:Open() == true and dex:GetSnapshot().open, "the book opens again after matching ends")
    click(dex.closeButton.Entity)
    check(not dex:GetSnapshot().open and lobbyState() == before, "the book closes again and the lobby is as it was before the dex was first opened")
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if isvalid(dex) and dex:GetSnapshot().open then dex:Close() end
if failures == 0 then log("[VRF][MonsterDexUIProbe] PASS")
else log_error("[VRF][MonsterDexUIProbe] FAILURES=" .. tostring(failures)) end
