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
    -- ShowGhost reports what it applied in the same call; the per-frame cursor update would otherwise race a probe's reads.
    input:ShowGhost('PLACE', -5, 2)
    wait(0.1) -- a freshly spawned preview takes its colour on the next frame; the game re-applies it every frame
    local info = input:ShowGhost('PLACE', -5, 2)
    assert(info.visible and info.legal and info.mode == 'PLACE', 'legal spot')
    assert(near(info.r, 1) and near(info.g, 1) and near(info.b, 1) and near(info.a, 0.55), 'legal keeps the original colour, semi-transparent')
    info = input:ShowGhost('PLACE', 5, 2)
    assert(info.visible and not info.legal and near(info.r, 1) and near(info.g, 0.25) and near(info.b, 0.25) and near(info.a, 0.55), 'illegal turns red')
    assert(#_FormationEditSession.Draft == 0 and not _FormationEditSession:IsDirty() and #input._T.previews == 0, 'the preview is not a unit, collider or edit')
    log('[VRF][Preview50] ghost colours ok')

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
    input:RightClick(-5, 0)
    assert(_FormationEditSession.SelectedMonsterId == '' and #_FormationEditSession.Draft == 1 and _FormationEditSession:PreviewMode() == '', 'the same right-click cancels the preview and removes nothing')
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(_FormationEditSession.SelectedUnit == 1 and _FormationEditSession:PreviewMode() == 'MOVE', 'without a preview a click selects the unit')
    info = input:ShowGhost('MOVE', -3, 1)
    assert(info.visible and info.legal and info.mode == 'MOVE', 'a move previews at the cursor')
    input:RightClick(-3, 1)
    assert(_FormationEditSession.SelectedUnit == 0 and #_FormationEditSession.Draft == 1 and near(_FormationEditSession.Draft[1].x, -5) and near(_FormationEditSession.Draft[1].y, 0), 'cancelling a move keeps content and original spot')
    input:RightClick(-5, 0)
    assert(#_FormationEditSession.Draft == 0, 'with no preview a right-click removes the unit')
    log('[VRF][Preview50] right-click rules ok')
end)
log(ok and '[VRF][Preview50] PASS' or '[VRF][Preview50] FAIL ' .. tostring(detail))
