-- Maker matched server instance: pause the session clock while inspecting both viewer directions.
local battle = _EntityService:GetEntityByPath("/maps/matchprobe"):GetComponent("script.BattleSession")
local home, away = battle.HomeProfile, battle.AwayProfile
local acquired = false
local ok, detail = pcall(function()
    assert(battle.Phase == "BATTLE", "swap only during battle")
    acquired = battle:BeginManualSimulation()
    assert(acquired, "another probe already owns the session clock")
    local before = battle:GetUnitSnapshots()
    battle.HomeProfile, battle.AwayProfile = away, home
    wait(1.5)
    assert(battle:GetUnitSnapshots() == before, "presentation identity changed authority")
    log("[VRF][BattleView] SWAP_READY generation=" .. tostring(battle.SessionGeneration))
    wait(3)
end)
-- Restore even if an assertion or runtime call failed while the identities were swapped.
battle.HomeProfile, battle.AwayProfile = home, away
if acquired then battle:EndManualSimulation() end
if ok then log("[VRF][BattleView] SWAP_RESTORED")
else log("[VRF][BattleView] SWAP_FAIL " .. tostring(detail)) end