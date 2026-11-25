-- Run in Maker's server_main after refresh and Play. Uses no player or world save data.
local war = _FactionWar
local towns = _FactionWarTownDocument:InitialTowns()

assert(towns.nanzih.owner == "RED" and towns.yancheng.owner == "BLUE", "capital owners")
assert(towns.zuoying.strength == 100 and towns.gushan.strength == 100, "initial town strength")
assert(war:FindFrontline("RED", towns) == "zuoying", "red must start at Zuoying")
assert(war:FindFrontline("BLUE", towns) == "gushan", "blue must start at Gushan")
assert(isvalid(war:FindGate("zuoying", "nanzih")), "Zuoying to Nanzih gate")
assert(not isvalid(war:FindGate("zuoying", "yancheng")), "no gate that skips Gushan")

towns.gushan.owner = "RED"
assert(war:FindFrontline("RED", towns) == "gushan", "red must follow the changed front")
assert(war:FindFrontline("BLUE", towns) == "yancheng", "blue can start from its capital")

towns = _FactionWarTownDocument:InitialTowns()
towns.zuoying.owner = "BLUE"
assert(war:FindFrontline("RED", towns) == "nanzih", "red can start from its capital")
assert(war:FindFrontline("BLUE", towns) == "zuoying", "blue must follow the changed front")
log("[VRF][FactionWarFrontline] PASS")
