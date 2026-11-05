-- Client, fresh Play with an isolated FormationService.StorageKey (see editor_save_flow_runtime_probe.lua).
-- Covers the cursor preview colours and rules, right-click cancel versus remove, and the template-driven monster cards.
-- maker_mouse_input cannot move the OS cursor, so cursor following itself stays a human check; ShowGhost and RightClick
-- are the same code the cursor path calls, driven here with explicit world positions.
local l = _FormationLobby
local function await(predicate, tries)
    for _ = 1, tries or 120 do if predicate() then return true end wait(0.1) end
    return false
end
local function node(path) return l:Ui(path) end
local function enabled(path) return node(path).ButtonComponent.Enable end
local function click(path)
    if not enabled(path) then return false end
    node(path):SendEvent(ButtonClickEvent())
    return true
end
local function inEditor() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' and _FormationEditSession.DraftSlot == _FormationEditSession.Snapshot.editSlot end
local function near(a, b) return math.abs(a - b) < 0.0001 end

local ok, detail = pcall(function()
    _FormationService:RequestRetryLoad()
    assert(await(function() return _FormationEditSession.Snapshot.loadState == 'NEW' end), 'isolated new-player fixture')
    assert(click('Lobby/Edit'), 'edit button')
    assert(await(inEditor), 'editor entered')
    wait(0.4)
    -- Cards and the preview only react once editing is allowed; click() skips a disabled button silently.
    assert(await(function() return _FormationEditSession:CanEdit() end), 'editing is available')
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')

    -- Cards: selection follows MonsterId; frames come from the template; hover never selects.
    local cards = _FormationCatalogCards._T.cards
    assert(#cards >= 3, 'formal catalog cards')
    click('Editor/Catalog/Monster1')
    for index, card in ipairs(cards) do
        assert(card.frame.Enable == (index == 1) and card.glow.Enable == (index == 1), 'only the selected card shows the selected frame and check')
    end
    click('Editor/Catalog/Monster2')
    for index, card in ipairs(cards) do assert(card.frame.Enable == (index == 2), 'selection moves between cards') end
    local template = node('Editor/Catalog/Template').SpriteGUIRendererComponent.ImageRUID.DataId
    click('Editor/Catalog/Monster3')
    for _, card in ipairs(cards) do
        assert(card.entity.SpriteGUIRendererComponent.ImageRUID.DataId == template, 'Render never replaces the template frame art')
    end
    local selected = _FormationEditSession.SelectedMonsterId
    cards[1].entity:SendEvent(UITouchEnterEvent())
    wait(0.2)
    assert(node('CardTooltip').Enable and _FormationEditSession.SelectedMonsterId == selected, 'hover shows details without changing the selection')
    cards[1].entity:SendEvent(UITouchExitEvent())
    assert(not node('CardTooltip').Enable, 'leaving hides the tooltip')
    log('[VRF][Preview50] cards ok')

    -- Rebuild: old cards and handlers are gone, selection and frames follow MonsterId, no tooltip is left behind.
    local old = {}
    for index, card in ipairs(cards) do old[index] = card.entity end
    cards[1].entity:SendEvent(UITouchEnterEvent())
    _FormationCatalogCards._T.optionsKey = ''
    _FormationCatalogCards:BuildOptions(_FormationEditSession.Snapshot.options)
    l:Render()
    wait(0.3)
    for index, entity in ipairs(old) do assert(not isvalid(entity), 'old card ' .. index .. ' destroyed') end
    assert(#_FormationCatalogCards._T.cards == #cards and _FormationEditSession.SelectedMonsterId == selected, 'rebuilt cards keep the selection by MonsterId')
    for _, card in ipairs(_FormationCatalogCards._T.cards) do assert(card.frame.Enable == (card.monsterId == selected), 'frames follow MonsterId after a rebuild') end
    assert(not node('CardTooltip').Enable, 'a rebuild clears the hover tooltip')
    log('[VRF][Preview50] rebuild ok')

    -- Preview: shared rules, colours, and it is never a unit.
    assert(_FormationEditSession:PreviewMode() == 'PLACE', 'an armed card previews placement')
    -- ShowGhost reports what it applied in the same call. The per-frame cursor update would otherwise overwrite the preview
    -- between a probe's write and read, so it is paused until the range checks end (restored after the pcall as well).
    input.Enable = false
    input:ShowGhost('PLACE', -5, 2)
    wait(0.1) -- a freshly spawned preview takes its colour on the next frame; the game re-applies it every frame
    local info = input:ShowGhost('PLACE', -5, 2)
    assert(info.visible and info.legal and info.mode == 'PLACE', 'legal spot')
    assert(near(info.r, 1) and near(info.g, 1) and near(info.b, 1) and near(info.a, 0.55), 'legal keeps the original colour, semi-transparent')
    info = input:ShowGhost('PLACE', 5, 2)
    assert(info.visible and not info.legal and near(info.r, 1) and near(info.g, 0.25) and near(info.b, 0.25) and near(info.a, 0.55), 'illegal turns red')
    assert(#_FormationEditSession.Draft == 0 and not _FormationEditSession:IsDirty() and #input._T.previews == 0, 'the preview is not a unit, collider or edit')
    log('[VRF][Preview50] ghost colours ok')

    -- Attack range preview (#60): the combat rectangle, always facing right, from the numbers the catalog publishes.
    -- The rectangle starts at the body centre (foot position minus the hit box offset), reaches AttackRange to the right
    -- and spans AttackRangeY above and below; GhostInfo reads it back from its own entity (updates paused, so nothing races).
    local function rangeMatches(range, option, x, y)
        return range.visible and near(range.w, option.attackRange) and near(range.h, option.attackRangeY * 2)
            and near(range.x - range.w / 2, x - option.bodyOffsetX) and near(range.y, y + option.bodyOffsetY)
    end
    -- A pixel texture may store 8-bit channels, so colours are compared to the nearest 1/100.
    local function tone(a, b) return math.abs(a - b) < 0.01 end
    local function red(range) return tone(range.r, 1) and tone(range.g, 0.25) and tone(range.b, 0.25) and tone(range.a, 0.85) end
    local armedId = _FormationEditSession.SelectedMonsterId
    local armed = _FormationEditSession:Option(armedId)
    assert(armed.attackRangeY ~= nil and armed.bodyOffsetX ~= nil and armed.bodyOffsetY ~= nil, 'the catalog publishes the preview numbers')
    input:ShowGhost('PLACE', -5, 2)
    local range = input:GhostInfo().range
    assert(rangeMatches(range, armed, -5, 2), 'legal: starts at the body centre, reaches AttackRange rightwards, AttackRangeY both ways')
    assert(range.r < range.b and tone(range.a, 0.85), 'legal: a non-red outline')
    -- Outline only: four thin bars inside the rectangle, so the middle stays empty and the monster underneath stays visible.
    assert(#input._T.range == 4 and range.border > 0 and range.border * 2 < math.min(range.w, range.h), 'the range is a thin outline, not a filled rectangle')
    assert(range.gaps >= 1 and range.closed, 'the outline is dashed (it has gaps) and ends on a dash so the corner stays closed')
    input:ShowGhost('PLACE', -3, 1)
    assert(rangeMatches(input:GhostInfo().range, armed, -3, 1), 'the rectangle follows the preview')
    info = input:ShowGhost('PLACE', 5, 2)
    range = input:GhostInfo().range
    assert(not info.legal and rangeMatches(range, armed, 5, 2) and red(range), 'an illegal spot turns the rectangle red with the monster')
    for _, option in ipairs(_FormationEditSession.Snapshot.options) do
        _FormationEditSession:SelectMonster(option.monsterId)
        input:ShowGhost('PLACE', -5, 2)
        assert(rangeMatches(input:GhostInfo().range, option, -5, 2), option.monsterId .. ' draws its own rectangle size')
    end
    -- Without an armed card the per-frame update itself shows nothing (the same gate that hides it over UI).
    _FormationEditSession:SelectMonster('')
    input:UpdateGhost()
    assert(not input:GhostInfo().range.visible, 'no placement or move mode means no rectangle')
    _FormationEditSession:SelectMonster(armedId)
    input:ShowGhost('PLACE', -5, 2)
    for index, bar in ipairs(input._T.range) do
        assert(isvalid(bar) and bar.HitComponent == nil and bar.KinematicbodyComponent == nil and bar.TriggerComponent == nil,
            'outline bar ' .. index .. ' has no collider and is not a target')
    end
    assert(#_FormationEditSession.Draft == 0 and not _FormationEditSession:IsDirty() and #input._T.previews == 0, 'the rectangle is not a unit or an edit')
    input:HideGhost()
    assert(not input:GhostInfo().range.visible, 'hiding the preview hides the rectangle')
    input.Enable = true
    log('[VRF][Preview50] range preview ok')

    -- Right-click: cancels only the preview; with none armed it removes; moving keeps the original spot.
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(#_FormationEditSession.Draft == 1, 'placed')
    assert(await(function() return input.PreviewCount == 1 end), '放置實體已建立')
    -- 暫停逐幀游標更新，讓 hover 斷言不受作業系統游標位置影響；結束一定恢復。
    input.Enable = false
    local hoverOk, hoverDetail = pcall(function()
        local entity = input._T.previews[1]
        local armed = _FormationEditSession.SelectedMonsterId
        input:ApplyHover(1)
        assert(input._T.hoverIndex == 0 and near(entity.TransformComponent.Scale.x, 1), '放置模式不新增 hover')
        _FormationEditSession.SelectedMonsterId = ''
        input:ApplyHover(1)
        assert(input._T.hoverIndex == 1 and near(entity.TransformComponent.Scale.x, 1.12), '取消放置後恢復 hover')
        assert(near(entity.SpriteRendererComponent.Color.b, 0.55), '一般 hover 的醒目色')
        _FormationEditSession.SelectedMonsterId = armed
        input:ApplyHover(1)
        assert(input._T.hoverIndex == 0 and near(entity.TransformComponent.Scale.x, 1), '重新選卡清除既有 hover')
        local tint = entity.SpriteRendererComponent.Color
        assert(near(tint.r, 1) and near(tint.g, 1) and near(tint.b, 1), '清除後恢復原色')
        log('[VRF][Preview50] hover PLACE suppressed; idle restored; existing highlight cleared')
    end)
    input.Enable = true
    assert(hoverOk, tostring(hoverDetail))
    input:ShowGhost('PLACE', -5, 0)
    input:RightClick(-5, 0)
    assert(_FormationEditSession.SelectedMonsterId == '' and #_FormationEditSession.Draft == 1 and _FormationEditSession:PreviewMode() == '', 'the same right-click cancels the preview and removes nothing')
    assert(not input:GhostInfo().range.visible, 'cancelling a placement clears the rectangle')
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(_FormationEditSession.SelectedUnit == 1 and _FormationEditSession:PreviewMode() == 'MOVE', 'without a preview a click selects the unit')
    -- Paused again: the per-frame cursor update would move the rectangle between the write and the read-back.
    input.Enable = false
    info = input:ShowGhost('MOVE', -3, 1)
    assert(info.visible and info.legal and info.mode == 'MOVE', 'a move previews at the cursor')
    assert(rangeMatches(input:GhostInfo().range, _FormationEditSession:Option(_FormationEditSession.Draft[1].monsterId), -3, 1), 'a move shows the moved unit\'s rectangle')
    input.Enable = true
    input:RightClick(-3, 1)
    assert(_FormationEditSession.SelectedUnit == 0 and #_FormationEditSession.Draft == 1 and near(_FormationEditSession.Draft[1].x, -5) and near(_FormationEditSession.Draft[1].y, 0), 'cancelling a move keeps content and original spot')
    assert(not input:GhostInfo().range.visible, 'cancelling a move clears the rectangle')
    input:RightClick(-5, 0)
    assert(#_FormationEditSession.Draft == 0, 'with no preview a right-click removes the unit')
    log('[VRF][Preview50] right-click rules ok')

    -- Leaving the map clears every local preview entity, the rectangle included.
    local leftover = input._T.range
    assert(leftover ~= nil and #leftover == 4 and isvalid(leftover[1]), 'an outline exists to clear')
    input:ClearPreviews()
    wait(0.2)
    for index, bar in ipairs(leftover) do assert(not isvalid(bar), 'outline bar ' .. index .. ' is destroyed') end
    assert(input._T.range == nil, 'clearing previews leaves no rectangle behind')
    log('[VRF][Preview50] range cleared')
end)
local mapInput = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
if isvalid(mapInput) then mapInput.Enable = true end
log(ok and '[VRF][Preview50] PASS' or '[VRF][Preview50] FAIL ' .. tostring(detail))
