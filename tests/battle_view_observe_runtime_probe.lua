-- Run in client while the server's natural battle is active. No client simulation or private fields.
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
local view = map:GetComponent('script.BattleViewPrototype')
local session = map:GetComponent('script.BattleSession')
local moved, attacked, hurt, dead = false, false, false, false
local maximumFrameDifference = 0
local initial = {}
local deadline = _UtilLogic.ElapsedSeconds + 100
while session.Phase ~= 'RESULT' and _UtilLogic.ElapsedSeconds < deadline do
    local mine = view:GetLocalFaction()
    local sign = mine == 'PLAYER' and 1 or -1
    for _, unit in ipairs(map:GetChildComponentsByTypeName('script.BattleUnit', false)) do
        local source = unit.Entity
        local visual = view:GetVisual(source)
        assert(isvalid(visual), 'render target disappeared')
        local p = source.TransformComponent.WorldPosition
        local v = visual.TransformComponent.WorldPosition
        -- Read after a frame: rendering follows the same interpolated client source, within a frame's travel.
        local difference = math.max(math.abs(v.x-sign*p.x), math.abs(v.y-p.y))
        maximumFrameDifference = math.max(maximumFrameDifference, difference)
        assert(difference < 0.35,
            'display/source position diverged '..source.Name..' source='..tostring(p)..' display='..tostring(v)..' sign='..tostring(sign))
        if initial[source.Name] == nil then initial[source.Name] = p end
        local start = initial[source.Name]
        moved = moved or math.abs(p.x-start.x) + math.abs(p.y-start.y) > 0.3
        attacked = attacked or unit.AttackSerial > 0
        hurt = hurt or unit.DamageTakenSerial > 0
        dead = dead or unit.IsDead
        assert(not isvalid(visual.MovementComponent) and not isvalid(visual.TriggerComponent), 'visual participates in combat')
        assert(source.SpriteRendererComponent.Color.a == 0, 'original sprite is duplicated')
        assert(not source.KinematicbodyComponent.EnableShadow, 'original shadow is duplicated')
        assert(not source.DamageSkinSpawnerComponent.Enable, 'original damage skin is duplicated')
        local fill = visual:GetChildByName('HPBarFill')
        if unit.Hp > 0 then
            local ratio = unit.Hp / unit.MaxHp
            assert(math.abs(fill.TransformComponent.Scale.x / 1.45402253 - ratio) < 0.3, 'HP proportion diverged')
        end
    end
    wait(0.05)
end
assert(session.Phase == 'RESULT', 'natural battle timed out')
assert(moved and attacked and hurt and dead, 'movement/attack/damage/death evidence missing')
assert(session.Result == 'WIN' or session.Result == 'LOSE' or session.Result == 'DRAW')
local result = session.Result
local serial = session.EventSerial
wait(1)
assert(session.Result == result and session.EventSerial == serial, 'terminal state changed')
log('[VRF][BattleView] NATURAL_PASS result='..result..' localFaction='..view:GetLocalFaction()..' events='..tostring(serial)..' maxFrameDifference='..tostring(maximumFrameDifference))
