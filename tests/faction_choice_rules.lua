-- Faction choice screen rules (#126): run through faction_choice_local.cjs. Fakes only; the production FactionWarUI bodies run unchanged.
local ui = _FactionWarUI
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

log = function() end
isvalid = function(value) return value ~= nil end

local nodes = {}
local function fakeNode(path)
    if nodes[path] == nil then
        nodes[path] = { Enable = false, ButtonComponent = { Enable = true }, TextGUIRendererComponent = { Text = "" }, SetEnable = function(self, value) self.Enable = value end }
    end
    return nodes[path]
end
_EntityService = { GetEntityByPath = function(_, path) return fakeNode((string.gsub(path, "^/ui/FactionWarGroup/", ""))) end }
_UserService = { LocalPlayer = { CurrentMapName = "formationlobby" } }
local asked = {}
_FactionWar = { RequestEntry = function(_, choice) table.insert(asked, choice) end }

local A, B = "FactionChoice/Window/A", "FactionChoice/Window/B"
ui:OnBeginPlay()
fakeNode("FactionChoice")

-- Opening the screen asks the server what the player is; the buttons wait for the answer.
ui:Open()
check(fakeNode("FactionChoice").Enable and #asked == 1 and asked[1] == "", "opening asks with no choice")
check(not fakeNode(A).Enable and not fakeNode(B).Enable, "no button before the server answers")
check(fakeNode("FactionChoice/Window/Status").TextGUIRendererComponent.Text == "正在讀取國戰資料…", "reading")
ui:Request("A")
check(#asked == 1, "a click while the first request runs sends nothing")

-- CHOOSE: both buttons appear together and either one sends its own faction.
ui:ShowEntryResult("CHOOSE")
check(fakeNode(A).Enable and fakeNode(B).Enable and fakeNode(A).ButtonComponent.Enable and fakeNode(B).ButtonComponent.Enable, "both buttons offered")
check(fakeNode("FactionChoice/Window/Status").TextGUIRendererComponent.Text == "請選擇國戰陣營。", "the prompt names no colour")
ui:Request("A")
check(#asked == 2 and asked[2] == "A", "A sends A")
check(not fakeNode(A).ButtonComponent.Enable and not fakeNode(B).ButtonComponent.Enable, "both buttons are dead while a choice is pending")
ui:Request("B")
check(#asked == 2, "no second choice while one is pending")

-- A failed save offers the same two buttons again; B then sends B.
ui:ShowEntryResult("SAVE_FAILED")
check(fakeNode(A).Enable and fakeNode(B).Enable and fakeNode(A).ButtonComponent.Enable and fakeNode(B).ButtonComponent.Enable, "buttons offered again after a failed save")
ui:Request("B")
check(#asked == 3 and asked[3] == "B", "B sends B")

-- ENTERED closes the screen; nothing but CHOOSE and SAVE_FAILED allows another choice.
ui:ShowEntryResult("ENTERED")
check(not fakeNode("FactionChoice").Enable, "entering closes the screen")
ui:Request("A")
check(#asked == 3, "a faction cannot be chosen again once the answer was ENTERED")
for _, result in ipairs({ "BLOCKED", "UNAVAILABLE" }) do
    ui:Open()
    asked = {}
    ui:ShowEntryResult(result)
    check(not fakeNode(A).Enable and not fakeNode(B).Enable, result .. " offers no faction button")
    ui:Request("A")
    check(#asked == 0, result .. " lets no choice through")
end

-- The converter the server uses accepts the two ids the buttons send, and nothing coloured.
local doc = _FactionWarTownDocument
check(doc:IsFaction("A") and doc:IsFaction("B"), "A and B are factions")
check(doc:FactionName("A") == "A 方" and doc:FactionName("B") == "B 方", "their names")

print("[VRF][FactionChoice] faction choice screen rules PASS checks=" .. tostring(checks))
