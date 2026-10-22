-- Run in client after the server probe prepared an opening and before StartBattle.
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
assert(isvalid(map), 'isolated prototype map missing')
local view = map:GetComponent('script.BattleViewPrototype')
assert(isvalid(view), 'view adapter missing')
local session = map:GetComponent('script.BattleSession')
local player = _UserService.LocalPlayer
assert(isvalid(player) and player.CurrentMap == map, 'local viewer must enter prototype')
local mine = view:GetLocalFaction()
assert(mine == 'PLAYER' or mine == 'ENEMY', 'participant identity not resolved')
local count = 0
for _, unit in ipairs(map:GetChildComponentsByTypeName('script.BattleUnit', false)) do
    local source = unit.Entity
    local visual = view:GetVisual(source)
    assert(isvalid(visual), 'visual missing for '..source.Name)
    assert(not isvalid(visual.KinematicbodyComponent) and not isvalid(visual.HitComponent), 'visual has physics')
    assert(source.SpriteRendererComponent.Color.a == 0 and not source.DamageSkinSpawnerComponent.Enable, 'original presentation duplicated')
    assert(not source.KinematicbodyComponent.EnableShadow, 'original shadow duplicated')
    local p = visual.TransformComponent.WorldPosition
    if unit.Faction == mine then assert(p.x < 0, 'own opening must be left')
    else assert(p.x > 0, 'enemy opening must be right') end
    assert(math.abs(p.y - source.TransformComponent.WorldPosition.y) < 0.001, 'height changed')
    local fill = visual:GetChildByName('HPBarFill')
    assert(fill.VisibleInHierarchy, 'full HP bar hidden')
    assert(math.abs(fill.TransformComponent.Scale.x - 1.45402253) < 0.0001, 'full gauge is not full')
    local expectedFlip = (source.TransformComponent.Scale.x * (mine == 'PLAYER' and 1 or -1) < 0) ~= source.SpriteRendererComponent.FlipX
    assert(visual.SpriteRendererComponent.FlipX == expectedFlip, 'facing did not follow position mapping')
    assert(visual.SpriteRendererComponent.SpriteRUID == source.SpriteRendererComponent.SpriteRUID, 'opening clip mismatched')
    local color = fill.SpriteRendererComponent.Color
    if unit.Faction ~= mine then assert(color.r > 0.9 and color.g < 0.2, 'enemy bar not red') end
    count = count + 1
    log('[VRF][BattleView] OPEN '..source.Name..' faction='..unit.Faction..' display='..tostring(p)..' source='..tostring(source.TransformComponent.WorldPosition))
end
assert(count == 4, 'expected four catalog units')
log('[VRF][BattleView] OPENING_PASS localFaction='..mine..' generation='..tostring(session.SessionGeneration))
