-- Run in a fresh Maker Play test with context=client, after the lobby is ready.
-- Verifies the dex request round trip: the client asks, receives every row, and keeps only the latest reply.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][MonsterDexClientProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][MonsterDexClientProbe][FAIL] " .. message) end
end

local function waitForReply(previous)
    for _ = 1, 100 do
        local latest = _MonsterDexService:GetLatest()
        if latest ~= nil and latest ~= previous then return latest end
        wait(0.1)
    end
    return nil
end

local ok, detail = pcall(function()
    check(_MonsterDexService:GetLatest() == nil, "no reply is cached before the first request")
    _MonsterDexService:RequestRows()
    local first = waitForReply(nil)
    check(first ~= nil, "the server answers a Maker Play request")
    if first == nil then return end
    check(#first == 10, "all 10 data rows arrive (got " .. tostring(#first) .. ")")
    for index, row in ipairs(first) do
        check(row.order == index and type(row.monsterId) == "string" and row.monsterId ~= ""
            and type(row.standRuid) == "string" and row.standRuid ~= "", "row " .. index .. " is complete and ordered")
    end
    _MonsterDexService:RequestRows()
    local second = waitForReply(first)
    check(second ~= nil and second ~= first and #second == #first, "a second request replaces the cached reply")
    check(_MonsterDexService:GetLatest() == second, "only the most recent reply is kept")
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][MonsterDexClientProbe] PASS")
else log_error("[VRF][MonsterDexClientProbe] FAILURES=" .. tostring(failures)) end
