-- Client context in a fresh Play after formation_flow_runtime_probe.lua.
wait(2)
local s = _FormationLobby.Snapshot
local pass = s.loadState == 'READY' and s.saveState == 'SAVED'
    and #s.draft == 2 and #s.saved.slots['1'].units == 2
    and s.saved.activeSlot == 1 and math.abs(s.draft[1].x + 5.25) < 0.001 and math.abs(s.draft[1].y + 0.35) < 0.001
log(pass and '[VRF][FormationRelogin] PASS' or '[VRF][FormationRelogin] FAIL')
