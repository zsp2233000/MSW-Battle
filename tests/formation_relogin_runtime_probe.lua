-- Client context in a fresh Play after formation_flow_runtime_probe.lua.
wait(2)
local s = _FormationLobby.Snapshot
local pass = s.loadState == 'READY' and s.saveState == 'SAVED'
    and #s.draft == 2 and #s.saved.slots['1'].units == 2
    and s.saved.activeSlot == 1 and s.draft[1].x == -2 and s.draft[1].y == 0
log(pass and '[VRF][FormationRelogin] PASS' or '[VRF][FormationRelogin] FAIL')
