-- #109 rules probe (P1). Run in Maker's server_main after refresh and a fresh Play; no virtual player is needed.
-- Uses an isolated global storage name ("CountryWarProbe109V1"), an isolated last-town key and the made-up profile code wp2621 for that key only.
-- Keep every real player in formationlobby. Final line: [VRF][FactionWarReconnect] PROBE PASS (or PROBE FAIL <reason>).
-- Covers (no player needed):
--   * OutcomeFrom rebuilds a match's outcome from the stored record: a flip, a non-flip, a legacy bare key, an absent record, a record pushed out of the
--     capped history; it never writes (the document bytes are the same before and after), and Settle's repeat answer (DUPLICATE) says the same thing
--   * NoticeText wording (never a win or loss claim), Landing for a login: friendly, fallen, fallen then retaken, no faction
--   * the last-town key: absent / stored / unchanged (no write) / coalesced newest / corrupt value / failed write / failed read
--   * Depart on a ticket whose reservation never filled in (the final log no longer errors), the room lookup behind the transfer adapter
--     and its fault switch, and the one-shot placement slot of a login
-- The player scenes are faction_war_reconnect_login_runtime_probe.lua (P5) and the e2e probes next to it.
local STORAGE = "CountryWarProbe109V1"
local TOWN_KEY = "CountryWarProbe109TownV1"
local PROFILE = "wp2621"
local originalStorage, originalKey, originalReady = _FactionWar.TownStorageName, _FactionWar.TownKey, _FactionWar.LoginReadySeconds
local function await(predicate, tries)
    for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function readRaw()
    local towns, raw, done = nil, nil, false
    _FactionWar:ReadTownsRaw(function(t, r) towns, raw, done = t, r, true end)
    assert(await(function() return done end), "town read answered")
    return towns, raw
end
local function write(towns)
    local saved = false
    _FactionWar:WriteTowns(towns, function(ok) saved = ok end)
    assert(await(function() return saved end), "town write confirmed")
end
local function seed(owners, strengths, settled)
    local towns = _FactionWar:InitialTowns()
    for id, owner in pairs(owners or {}) do towns[id].owner = owner end
    for id, strength in pairs(strengths or {}) do towns[id].strength = strength end
    -- The engine's JSONEncode rejects an empty table, so an empty history is stored as no field at all.
    if settled ~= nil and #settled > 0 then towns.settled = settled end
    write(towns)
end
local function settle(matchKey, home, away, homeResult)
    local status, detail, outcome, done = nil, nil, nil, false
    _FactionWarAttack:Settle(matchKey, home, away, homeResult, "HUMAN", function(s, d, o) status, detail, outcome, done = s, d, o, true end)
    assert(await(function() return done end, 80), "settlement completed " .. matchKey)
    return status, detail, outcome
end
local function readTown()
    local result, done = nil, false
    _FactionWar:ReadTown(PROFILE, function(town) result, done = town, true end)
    assert(await(function() return done end), "last town read answered")
    return result
end
local function has(text, part) return string.find(text, part, 1, true) ~= nil end

local ok, reason = pcall(function()
    local war, attack, flow = _FactionWar, _FactionWarAttack, _MatchFlow
    war.TownStorageName = STORAGE
    war.TownKey = TOWN_KEY
    war.LoginReadySeconds = 0.5

    -- OutcomeFrom: pure, rebuilt from the record { k, w, l, s, o }.
    local board = war:InitialTowns()
    board.settled = {
        { k = "r109-flip", w = "zuoying", l = "gushan", s = 100, o = "RED" },
        { k = "r109-hit", w = "zuoying", l = "gushan", s = 80, o = "" },
        "r109-legacy",
    }
    local encoded = _HttpService:JSONEncode(board)
    local flip = attack:OutcomeFrom(board, "r109-flip")
    assert(flip ~= nil and flip.flipped == true and flip.owner == "RED" and flip.winner == "zuoying" and flip.loser == "gushan" and flip.strength == 100, "a capture is rebuilt with its winner, loser, owner and refilled strength")
    local hit = attack:OutcomeFrom(board, "r109-hit")
    assert(hit ~= nil and hit.flipped == false and hit.owner == "" and hit.strength == 80 and hit.loser == "gushan", "a deduction is rebuilt without a capture")
    local legacy = attack:OutcomeFrom(board, "r109-legacy")
    assert(legacy ~= nil and legacy.flipped == false and legacy.loser == "" and legacy.status == "DUPLICATE", "a bare key says the match was settled and nothing else")
    assert(attack:OutcomeFrom(board, "r109-absent") == nil, "no record reads as no capture")
    assert(attack:OutcomeFrom(nil, "r109-flip") == nil and attack:OutcomeFrom({}, "r109-flip") == nil and attack:OutcomeFrom(board, "") == nil, "a missing board, history or key rebuilds nothing")
    assert(_HttpService:JSONEncode(board) == encoded, "the reader changed nothing")

    -- NoticeText: what the record says, and no claim about who won.
    local origin = "zuoying"
    assert(has(attack:NoticeText(flip, origin), "奪下") and has(attack:NoticeText(flip, origin), "鼓山"), "the conqueror's town is told the capture")
    assert(has(attack:NoticeText(flip, "gushan"), "易主"), "any other town is told the flag changed")
    assert(has(attack:NoticeText(hit, origin), "80") and has(attack:NoticeText(hit, origin), "鼓山"), "a deduction names the town and its strength")
    assert(has(attack:NoticeText(nil, origin), "已結束") and has(attack:NoticeText(legacy, origin), "已結束"), "no record or a bare key only says the match is over")
    for _, text in ipairs({ attack:NoticeText(flip, origin), attack:NoticeText(hit, origin), attack:NoticeText(nil, origin) }) do
        assert(not has(text, "勝利") and not has(text, "落敗") and not has(text, "平手"), "the notice claims no win or loss")
    end

    -- Landing for a login: home if the faction holds it (again), else the capital; no faction, no landing.
    local rules = war:InitialTowns()
    assert(war:Landing("RED", "zuoying", rules) == "zuoying", "friendly: home")
    rules.zuoying.owner = "BLUE"
    rules.zuoying.e = 1
    assert(war:Landing("RED", "zuoying", rules) == "nanzih", "fallen: the capital")
    rules.zuoying.owner = "RED"
    rules.zuoying.e = 2
    assert(war:Landing("RED", "zuoying", rules) == "zuoying", "fallen and retaken (count +2, same owner): home")
    assert(war:Landing("", "zuoying", rules) == "", "no faction: nowhere")
    assert(war:Landing("BLUE", "zuoying", rules) == "yancheng", "the other faction at a town it does not own: its capital")
    log("[VRF][FactionWarReconnect] rules ok")

    -- OutcomeFrom against stored documents: a repeat answers the same capture, nothing is written, a record falls out of the capped history.
    seed({}, { gushan = 20 })
    local status, strength, outcome = settle("r109-m1", "zuoying", "gushan", "WIN")
    assert(status == "SAVED" and outcome.flipped == true and outcome.owner == "RED" and strength == 100, "the first delivery captures Gushan")
    local towns, before = readRaw()
    local rebuilt = attack:OutcomeFrom(towns, "r109-m1")
    assert(rebuilt ~= nil and rebuilt.flipped == true and rebuilt.winner == "zuoying" and rebuilt.loser == "gushan" and rebuilt.owner == "RED" and rebuilt.strength == 100, "the stored record rebuilds the capture")
    status, strength, outcome = settle("r109-m1", "zuoying", "gushan", "WIN")
    assert(status == "DUPLICATE" and outcome.flipped == true and outcome.owner == "RED" and outcome.strength == 100, "the repeat answer is the same capture, through the shared reader")
    local _, after = readRaw()
    assert(after == before, "reading and repeating wrote nothing")
    local old = {}
    for index = 1, attack.SettledHistory do old[index] = { k = "r109-old" .. index, w = "zuoying", l = "gushan", s = 80, o = "" } end
    seed({}, {}, old)
    assert(settle("r109-new", "zuoying", "gushan", "WIN") == "SAVED", "a new result is stored")
    towns = readRaw()
    assert(#towns.settled == attack.SettledHistory, "the history stays capped")
    assert(attack:OutcomeFrom(towns, "r109-old1") == nil, "the oldest record fell out: it reads as no capture")
    assert(attack:OutcomeFrom(towns, "r109-new") ~= nil, "the newest is there")
    log("[VRF][FactionWarReconnect] outcome ok")

    -- The last-town key.
    assert(readTown() == "", "nothing stored yet reads as no last town")
    war:Remember(PROFILE, "zuoying")
    assert(await(function() return readTown() == "zuoying" end, 80), "a town is stored")
    assert(await(function() return war._T.remembering[PROFILE] == nil end, 50), "the write slot is released")
    war:Remember(PROFILE, "zuoying")
    assert(await(function() return war._T.remembering[PROFILE] == nil end, 50) and readTown() == "zuoying", "an unchanged town is not written again and stays")
    war:Remember(PROFILE, "gushan")
    war:Remember(PROFILE, "yancheng")
    assert(await(function() return readTown() == "yancheng" and war._T.remembering[PROFILE] == nil end, 100), "a town asked for while a write runs is written afterwards: the newest wins")
    war:Remember(PROFILE, "nowhere")
    war:Remember("", "zuoying")
    wait(0.5)
    assert(readTown() == "yancheng" and war._T.remembering[PROFILE] == nil and war._T.remembering[""] == nil, "a name that is no town, or no profile, is never stored")
    -- A corrupt value reads as unreadable (never as a guess), and the next arrival repairs it with the exact bytes it saw.
    local stored = false
    _DataStorageService:GetUserDataStorage(PROFILE):SetAsync(TOWN_KEY, "nowhere", function(code) stored = code == 0 end)
    assert(await(function() return stored end), "corrupt value planted")
    assert(readTown() == nil, "a value that is no town reads as unreadable")
    war:Remember(PROFILE, "zuoying")
    assert(await(function() return readTown() == "zuoying" end, 80), "the next arrival repairs it")
    -- Failures: one failed write leaves the old value and releases the slot (best effort, logged); one failed read reads as unreadable.
    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    war:Remember(PROFILE, "nanzih")
    assert(await(function() return war._T.remembering[PROFILE] == nil end, 80), "a failed write releases the slot")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert(readTown() == "zuoying", "and leaves the old town in place")
    _FormationStorage:ConfigureMakerFaults(1, 0, 0)
    assert(readTown() == nil, "a failed read is unreadable, not empty")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    war:Remember(PROFILE, "nanzih")
    assert(await(function() return readTown() == "nanzih" end, 80), "after the faults the next write goes through")
    log("[VRF][FactionWarReconnect] last town ok")

    -- Depart on a ticket whose reservation has not filled in yet: its final log used to read ticket.data and error.
    flow._T.records["probe-109-early"] = { profile = "probe-109" }
    flow._T.arrival["probe-109-early"] = "WAR"
    local departed, failure = pcall(function() flow:Depart("probe-109-early", "Probe") end)
    assert(departed, "Depart survives a ticket without data: " .. tostring(failure))
    assert(flow._T.records["probe-109-early"] == nil and flow:IsOffline("probe-109-early") and flow._T.arrival["probe-109-early"] == nil, "the record and the hint are gone, the player is offline")
    flow._T.offline["probe-109-early"] = nil

    -- The room lookup lives behind the transfer adapter; the fault adapter can make every room look gone (Maker only).
    assert(flow:TransferAdapter():FindRoom("") == nil and flow:TransferAdapter():FindRoom("probe-109-no-such-room") == nil, "no room, no handle")
    -- A real (empty) instance room; the engine destroys it by itself after the 5 s wait for a first user.
    local room = _RoomService:CreateInstanceRoom("probe-109-room", { "matchprobe" }, 5)
    assert(room ~= nil and room:IsValid(), "a room to look up")
    local found = flow:TransferAdapter():FindRoom("probe-109-room")
    assert(found ~= nil and found.InstanceKey == "probe-109-room", "the real adapter finds a room that runs in this world instance")
    _MatchFaults:ConfigureRooms(true)
    assert(flow:TransferAdapter():FindRoom("probe-109-room") == nil, "an armed fault adapter hides rooms")
    _MatchFaults:Remove()
    assert(flow:TransferAdapter() ~= _MatchFaults, "Remove hands the real adapter back")
    assert(flow:TransferAdapter():FindRoom("probe-109-room") ~= nil, "and the room is found again")

    -- One login, one placement: the enter and the reconnect event both ask; the second finds the first running and leaves it alone.
    war.LoginReadySeconds = 1
    _TimerService:SetTimerOnce(function() war:PlaceAtLogin("probe-109-nobody", "enter", false) end, 0.01)
    wait(0.3)
    local slot = war._T.placing["probe-109-nobody"]
    assert(slot ~= nil and slot.cause == "enter", "the first placement holds the slot while it waits for an entity")
    war:PlaceAtLogin("probe-109-nobody", "reconnect", false)
    assert(war._T.placing["probe-109-nobody"] == slot, "the second ask did not take over")
    assert(await(function() return war._T.placing["probe-109-nobody"] == nil end, 50), "a player who never appears releases the slot after the wait")
    log("[VRF][FactionWarReconnect] flow seams ok")
end)

_FactionWar.TownStorageName, _FactionWar.TownKey, _FactionWar.LoginReadySeconds = originalStorage, originalKey, originalReady
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
_MatchFaults:Remove()
_MatchFlow._T.records["probe-109-early"] = nil
_MatchFlow._T.offline["probe-109-early"] = nil
_MatchFlow._T.arrival["probe-109-early"] = nil
_DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
_DataStorageService:GetUserDataStorage(PROFILE):DeleteAndWait(TOWN_KEY)
if ok then log("[VRF][FactionWarReconnect] PROBE PASS") else log_error("[VRF][FactionWarReconnect] PROBE FAIL " .. tostring(reason)) end
