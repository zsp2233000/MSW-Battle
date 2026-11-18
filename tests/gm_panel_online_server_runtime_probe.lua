-- server_main. Run before and after adding a virtual player, and again after
-- moving that player to an instance room within the same world instance.
local EXPECT_OTHER = false
local IN_OTHER_ROOM = false
local OTHER = 'GM8802'
assert(Environment:IsMakerPlay(), 'Maker only')

local service = _GMCommandService
local gm
for _, player in ipairs(_UserService.Users.Values) do
    if service:IsGM(player.ProfileCode) then gm = player.ProfileCode break end
end
assert(gm, 'GM account is in the lobby')
local function list(requester)
    local response
    service:Execute(requester, { kind = 'LIST_ONLINE_PLAYERS', profile = '' }, function(result) response = result end)
    for _ = 1, 60 do
        if response ~= nil then return response end
        wait(0.1)
    end
    error('online list did not answer')
end
local denied = list(OTHER)
assert(denied.status == 'FORBIDDEN' and denied.players == nil, 'non-GM sees no player data')
if EXPECT_OTHER and not IN_OTHER_ROOM then
    for _ = 1, 100 do
        if _UserService:GetUserByProfileCode(OTHER) ~= nil then break end
        wait(0.1)
    end
    assert(_UserService:GetUserByProfileCode(OTHER) ~= nil, 'virtual player arrived in the lobby')
end
local result = list(gm)
assert(result.status == 'PLAYERS_READY', 'GM list status: ' .. tostring(result.status))
local seen = {}
for _, player in ipairs(result.players) do
    assert(seen[player.profile] == nil, 'duplicates in online list')
    seen[player.profile] = player
end
assert(seen[gm] ~= nil, 'online list includes the requesting GM')
assert((seen[OTHER] ~= nil) == EXPECT_OTHER, 'refresh reflects virtual player presence')
if IN_OTHER_ROOM then
    assert(_UserService:GetUserByProfileCode(OTHER) == nil and seen[OTHER] ~= nil, 'includes player outside the lobby room')
end
log('[VRF][GMPanelOnlineServerProbe] PASS present=' .. tostring(EXPECT_OTHER) .. ' otherRoom=' .. tostring(IN_OTHER_ROOM))
