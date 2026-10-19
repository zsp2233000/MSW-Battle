-- Server context. Reference terrain and legacy-save repair without mutating storage.
local failures = 0
local function check(value, label)
    if not value then failures = failures + 1 log('[VRF][FormationTerrain] FAIL ' .. label) end
end
local ok, detail = pcall(function()
    local catalog = _FormationService:GetCatalog()
    local bounds = _FormationMapLayout:Bounds()
    check(bounds.minX == -15 and bounds.maxX == 14 and bounds.minY == -5 and bounds.maxY == 3, '29 by 8 reference footprint')
    check(_FormationMapLayout:IsWalkable(-5.25, -0.35), 'fractional floor position outside former UI grid')
    check(not _FormationMapLayout:IsWalkable(-1, 2), 'reference wall rejected')
    check(not _FormationMapLayout:IsWalkable(14, 0), 'exclusive far edge rejected')
    local document = _FormationSchema:EmptyDocument()
    local old = {{monsterId='monster_tank',x=-1,y=2},{monsterId='monster_tank',x=-2,y=2}}
    document.slots['1'].units = old
    check(_FormationSchema:ValidateDocument(document, catalog) ~= nil, 'legacy wall positions remain loadable')
    check(_FormationSchema:ValidateUnits(old, catalog, false) == nil, 'invalid legacy positions cannot be saved again')
    local changed = {{monsterId='monster_tank',x=-5.25,y=-0.35},old[2]}
    check(_FormationSchema:ValidateEdit(changed, catalog, old) ~= nil, 'repair one legacy unit at a time')
    check(_FormationSchema:ValidateEdit({{monsterId='monster_tank',x=-3,y=2}}, catalog, old) == nil, 'cannot introduce a new wall position')
    local repaired = {{monsterId='monster_tank',x=-5.25,y=-0.35},{monsterId='monster_tank',x=-3.45,y=0.65}}
    local clean = _FormationSchema:ValidateUnits(repaired, catalog, false)
    check(clean ~= nil and clean[1].x == -5.25 and clean[1].y == -0.35, 'fully repaired positions retain exact fractions')
end)
if not ok then failures = failures + 1 log('[VRF][FormationTerrain] exception=' .. tostring(detail)) end
log(failures == 0 and '[VRF][FormationTerrain] PASS' or '[VRF][FormationTerrain] FAILURES=' .. failures)
