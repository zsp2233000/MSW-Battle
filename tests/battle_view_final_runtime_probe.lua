-- Run in client after NATURAL_PASS, then run the server departure snippet from the evidence document.
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
local view = map:GetComponent('script.BattleViewPrototype')
local session = map:GetComponent('script.BattleSession')
assert(session.Phase == 'RESULT')
local sign = view:GetLocalFaction() == 'PLAYER' and 1 or -1
for _, unit in ipairs(map:GetChildComponentsByTypeName('script.BattleUnit', false)) do
    local visual = view:GetVisual(unit.Entity)
    local p = visual.TransformComponent.WorldPosition
    local q = unit.Entity.TransformComponent.WorldPosition
    assert(math.abs(p.x-sign*q.x) < 0.001 and math.abs(p.y-q.y) < 0.001, 'settled position mismatched')
    local fill = visual:GetChildByName('HPBarFill')
    assert(math.abs(fill.TransformComponent.Scale.x / 1.45402253 - unit.Hp/unit.MaxHp) < 0.0001, 'settled HP mismatched')
end
for index=1,2 do
    local avatar = map:GetChildByName('ViewAvatar_'..tostring(index))
    assert(isvalid(avatar) and not isvalid(avatar.KinematicbodyComponent) and not isvalid(avatar.TriggerComponent), 'avatar has physics')
    local p = avatar.TransformComponent.WorldPosition
    assert(p.y == 3 and math.abs(p.x) == 5, 'avatar symmetry changed')
    assert((p.x < 0 and avatar.TransformComponent.Scale.x < 0) or (p.x > 0 and avatar.TransformComponent.Scale.x > 0), 'avatar faces outward')
end
log('[VRF][BattleView] FINAL_GEOMETRY_HP_AVATARS_PASS')
