-- Server context. The centered V2 contract supersedes the former legacy-position repair policy.
local failures = 0
local function check(value, label)
    if not value then failures = failures + 1 log('[VRF][FormationTerrain] FAIL ' .. label) end
end
local ok, detail = pcall(function()
    local catalog = _FormationService:GetCatalog()
    local bounds = _FormationMapLayout:Bounds()
    check(bounds.minX == -15 and bounds.maxX == 15 and bounds.minY == -8 and bounds.maxY == 8, '30 by 16 combat footprint')
    check(_FormationMapLayout:IsWalkable(-5.25, -0.35), 'fractional floor position outside former UI grid')
    check(not _FormationMapLayout:IsWalkable(-16, 0), 'outer wall rejected')
    check(not _FormationMapLayout:IsWalkable(15, 0), 'exclusive far edge rejected')
    local document = _FormationSchema:EmptyDocument()
    local old = {{monsterId='monster_tank',x=0,y=0},{monsterId='monster_tank',x=-2,y=2}}
    document.slots['1'].units = old
    check(_FormationSchema:ValidateDocument(document, catalog) == nil, 'invalid positions cannot load into V2')
    check(_FormationSchema:ValidateUnits(old, catalog, false) == nil, 'centre cannot be saved')
    check(_FormationSchema:ValidateEdit(old, catalog, old) == nil, 'retaining an invalid point grants no exemption')
    check(_FormationSchema:ValidateEdit({{monsterId='monster_tank',x=-16,y=0}}, catalog, old) == nil, 'cannot introduce a wall position')
    local repaired = {{monsterId='monster_tank',x=-5.25,y=-0.35},{monsterId='monster_tank',x=-3.45,y=0.65}}
    local clean = _FormationSchema:ValidateUnits(repaired, catalog, false)
    check(clean ~= nil and clean[1].x == -5.25 and clean[1].y == -0.35, 'fully repaired positions retain exact fractions')
    document.slots['1'].units = repaired
    document.schema = 1
    check(_FormationSchema:ValidateDocument(document, catalog) == nil, 'old schema rejected even with legal coordinates')
end)
if not ok then failures = failures + 1 log('[VRF][FormationTerrain] exception=' .. tostring(detail)) end
log(failures == 0 and '[VRF][FormationTerrain] PASS' or '[VRF][FormationTerrain] FAILURES=' .. failures)
