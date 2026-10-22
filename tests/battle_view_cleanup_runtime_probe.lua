-- Run in client BEFORE the server teleports the player out; also works when the map unloads.
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
local player = _UserService.LocalPlayer
assert(isvalid(map) and player.CurrentMap == map)
local visuals = {}
for _, entity in ipairs(map.Children:ToTable()) do
    if string.sub(entity.Name,1,5) == 'View_' or string.sub(entity.Name,1,11) == 'ViewAvatar_' then
        table.insert(visuals, entity)
    end
end
assert(#visuals == 6, 'four units and two avatars must exist before departure')
local deadline = _UtilLogic.ElapsedSeconds + 20
while player.CurrentMap == map and _UtilLogic.ElapsedSeconds < deadline do wait(0.05) end
assert(player.CurrentMap ~= map, 'departure timed out')
wait(0.5)
for _, entity in ipairs(visuals) do assert(not isvalid(entity), 'local prototype entity survived departure') end
if isvalid(map) then
    for _, unit in ipairs(map:GetChildComponentsByTypeName('script.BattleUnit', false)) do
        assert(unit.Entity.SpriteRendererComponent.Color.a == 1, 'source tint not restored')
        assert(unit.Entity.DamageSkinSpawnerComponent.Enable, 'source damage skin not restored')
    end
end
log('[VRF][BattleView] DEPARTURE_CLEANUP_PASS destroyed='..tostring(#visuals))
