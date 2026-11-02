-- Client, fresh Play. No UI clicks, no server round trips, no storage: it drives _FormationEditSession with
-- synthetic snapshots and never carries out the commands it returns, so nothing is saved.
-- Sequences start very high so any real server snapshot that arrives later is ignored as stale.
local s = _FormationEditSession
local function await(predicate, tries)
    for _ = 1, tries or 120 do if predicate() then return true end wait(0.1) end
    return false
end
local function has(text, part) return string.find(text, part, 1, true) ~= nil end
local OPTIONS = { { 'monster_tank', 'Tank', '', 'TANK', 1, 1, 1, 1 } }
local seq = 1000000

local function snapshot(fields)
    local saved, info = { schema = 2, revision = 0, activeSlot = 0, slots = {}, writeId = '' }, {}
    for index = 1, 5 do
        saved.slots[tostring(index)] = { units = {}, revision = 0 }
        info[tostring(index)] = { revision = 0, savedValid = true }
    end
    local value = { loadState = 'READY', editSlot = 1, slots = info, saved = saved, message = '', options = OPTIONS,
        pending = false, pendingSlot = 0, pendingKind = '', uncertain = false, result = nil }
    for key, v in pairs(fields or {}) do value[key] = v end
    return value
end
local function savedWith(slotId, units, activeSlot)
    local value = snapshot({ editSlot = slotId })
    value.saved.activeSlot = activeSlot or 0
    value.saved.slots[tostring(slotId)] = { units = units, revision = 1 }
    return value
end
local function observe(value) seq = seq + 1 return s:Observe(value, seq) end
local function kinds(commands)
    local names = {}
    for _, command in ipairs(commands or {}) do table.insert(names, command.kind) end
    return table.concat(names, ',')
end

local ok, detail = pcall(function()
    if _UserService.LocalPlayer.CurrentMapName ~= 'formationsim' then _FormationLobby:Travel('formationsim') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'editor map entered')
    wait(0.6)
    s:Reset()

    -- S1: a first snapshot opens the group from its saved (empty) version.
    assert(observe(snapshot()) ~= nil, 'a fresh snapshot is accepted')
    assert(s.DraftSlot == 1 and #s.Draft == 0 and not s:IsDirty(), 'opens clean from the saved version')
    assert(s:SaveBlockReason() == '沒有變更', 'nothing to save yet')
    assert(s:Observe(snapshot(), seq - 5) == nil, 'an out-of-order snapshot is ignored')

    -- S2: edits stay local; dirty follows content, not history.
    s.SelectedMonsterId = 'monster_tank'
    assert(s:PreviewMode() == 'PLACE', 'an armed card previews placement')
    assert(s:Place(-5, 0) and #s.Draft == 1 and s:IsDirty(), 'placed locally')
    assert(s:SaveBlockReason() == '' and s:View().dirty, 'a valid change is saveable')
    s.SelectedUnit = 1
    assert(s:RemoveSelected() and #s.Draft == 0 and not s:IsDirty(), 'exact restoration clears the change')
    assert(s:SaveBlockReason() == '沒有變更', 'and save is blocked again')

    -- S3: an empty group that differs from a saved one cannot be saved.
    observe(savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 } }))
    assert(#s.Draft == 1 and not s:IsDirty(), 'confirmed content is followed while clean')
    s.SelectedUnit = 1
    s:RemoveSelected()
    assert(s:IsDirty() and has(s:SaveBlockReason(), '空隊伍'), 'an emptied group is dirty but not saveable')
    s:ResetForMap()
    assert(#s.Draft == 1 and not s:IsDirty(), 'a map change reopens the saved version')

    -- S4: switching with changes asks first; a stale reply never runs the deferred switch.
    s.SelectedMonsterId = 'monster_tank'
    assert(s:Place(-3, 0), 'second unit placed')
    local commands = s:RequestSwitchSlot(2)
    assert(commands ~= nil and #commands == 0 and s.ConfirmKind == 'SWITCH' and s.ConfirmTarget == 2, 'switch asks for a decision')
    assert(s:RequestSwitchSlot(3) == nil, 'no second request while one is open')
    commands = s:ConfirmSave()
    assert(kinds(commands) == 'SAVE' and commands[1].slotId == 1 and #commands[1].units == 2 and commands[1].revision == 1, 'save command carries one group')
    local requestId = commands[1].requestId
    assert(type(requestId) == 'string' and s:Busy() and s:Saving(), 'busy while the reply is outstanding')
    assert(s:ContinueEditing() == nil and s:ConfirmDiscard() == nil, 'no leaving the dialog while a save is outstanding')
    local stale = savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 }, { monsterId = 'monster_tank', x = -3, y = 0 } })
    stale.result = { requestId = 'someone-else', kind = 'SAVE', slotId = 1, status = 'OK', code = 0 }
    assert(#observe(stale) == 0 and s.ConfirmKind == 'SWITCH' and s:Busy(), 'a reply for another request settles nothing')
    local reply = savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 }, { monsterId = 'monster_tank', x = -3, y = 0 } })
    reply.result = { requestId = requestId, kind = 'SAVE', slotId = 1, status = 'OK', code = 0 }
    commands = observe(reply)
    assert(kinds(commands) == 'SELECT_SLOT' and commands[1].slotId == 2, 'the confirmed reply continues to the chosen group')
    assert(s.ConfirmKind == '' and not s:Busy() and not s:IsDirty(), 'dialog closed and the saved content is the new baseline')

    -- S5: a reply that never arrives leaves the result unconfirmed until a read settles it.
    s.SelectedMonsterId = 'monster_tank'
    assert(s:Place(-1, 0), 'third unit placed')
    commands = s:RequestSaveCurrent()
    assert(kinds(commands) == 'SAVE', 'plain save requested')
    assert(s:Tick(1) == nil, 'nothing happens before the timeout')
    assert(s:Tick(16) ~= nil and s:Unconfirmed() and not s:Writable(), 'timeout locks writes as unconfirmed')
    assert(s:IsDirty() and #s.Draft == 3, 'the local change is kept')
    assert(has(s:SaveBlockReason(), '確認結果'), 'the reason names the confirm action')
    assert(kinds(s:RequestSwitchSlot(2)) == 'NOTICE' and kinds(s:RequestReturnToLobby()) == 'NOTICE', 'no switching or leaving while unconfirmed')
    assert(kinds(s:RequestReconcile()) == 'RELOAD' and s:Unconfirmed(), 'reconcile asks for a read')
    observe(savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 }, { monsterId = 'monster_tank', x = -3, y = 0 } }))
    assert(not s:Unconfirmed() and s:Writable() and s:IsDirty() and #s.Draft == 3, 'the read unlocks writes and keeps the change')

    for _, load in ipairs({ 'CONFLICT', 'LOADING', 'ERROR' }) do
        local value = snapshot({ loadState = load, uncertain = true })
        observe(value)
        assert(s:Unconfirmed() and kinds(s:RequestReturnToLobby()) == 'NOTICE', 'unsettled read keeps leaving blocked: ' .. load)
    end
    local reconciled = savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 }, { monsterId = 'monster_tank', x = -3, y = 0 } })
    reconciled.uncertain = true
    observe(reconciled)
    assert(not s:Unconfirmed() and s:Writable(), 'confirmed read permits continuing while the late-write guard remains')

    -- S6: leaving asks; discarding returns to the saved version, continuing keeps everything.
    commands = s:RequestReturnToLobby()
    assert(#commands == 0 and s.ConfirmKind == 'RETURN', 'leaving asks for a decision')
    commands = s:ContinueEditing()
    assert(#commands == 0 and s.ConfirmKind == '' and #s.Draft == 3 and s:IsDirty(), 'continue keeps the change')
    s:RequestReturnToLobby()
    commands = s:ConfirmDiscard()
    assert(kinds(commands) == 'TRAVEL' and commands[1].destination == 'formationlobby', 'discard continues to the lobby')
    assert(#s.Draft == 2 and not s:IsDirty() and s.ConfirmKind == '', 'discard returns to the saved version')
    assert(kinds(s:RequestReturnToLobby()) == 'TRAVEL', 'a clean group leaves directly')

    -- S7: activation applies to saved content of a non-active group only.
    assert(kinds(s:RequestActivate()) == 'ACTIVATE', 'a saved, valid, non-active group can be activated')
    observe(savedWith(1, { { monsterId = 'monster_tank', x = -5, y = 0 }, { monsterId = 'monster_tank', x = -3, y = 0 } }, 1))
    assert(has(s:ActivateBlockReason(), '已是出戰'), 'the active group cannot be activated again')
    assert(s:HasValidActive(), 'a valid active group enables matchmaking')
end)
s:Reset()
log(ok and '[VRF][EditSession] PASS' or '[VRF][EditSession] FAIL ' .. tostring(detail))
