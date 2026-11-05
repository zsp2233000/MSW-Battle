const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const { MapBuilder } = require("../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs");
const { ModelBuilder } = require("../.agents/skills/msw-general/scripts/model/msw_model_builder.cjs");
const { UIBuilder } = require("../.agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs");

test("battle health bars are authored under the unit without a screen UI template", () => {
  const model = ModelBuilder.read("RootDesk/MyDesk/Models/Monsters/BattleUnit.model");
  assert.deepEqual(model.validate(), []);
  const anchor = model.getChild("HPAnchor");
  const bar = model.getChild("HealthBar");
  assert.equal(bar.ParentId, anchor.Id);
  assert.ok(bar.Model.Components.includes("MOD.Core.PixelRendererComponent"));
  for (const child of model.listChildren()) {
    assert.ok(child.Model.Components.every((type) => [
      "MOD.Core.TransformComponent", "MOD.Core.PixelRendererComponent", "MOD.Core.SpriteRendererComponent",
    ].includes(type)), `${child.Name} must not fight or intercept input`);
  }
  const ui = UIBuilder.read("ui/BattleGroup.ui");
  assert.equal(ui.find("HealthBars"), null);
  assert.ok(ui.find("BattleHud"));
  assert.ok(ui.find("DeploymentPanel"));
  assert.ok(ui.find("BattleResultPanel"));
});

const SPRITE = "MOD.Core.SpriteGUIRendererComponent";
const BROWN_BASE = "2860136c06ab075439721c027de365af";
const CARD_FRAME = "ac319875b43f40ea86a069c468a1a26e";
const CARD_POPUP = "a21e588b";

test("#51 battle HUD uses the brown Cardgame panel and never intercepts the battlefield", () => {
  const ui = UIBuilder.read("ui/BattleGroup.ui");
  assert.equal(ui.getComponent("BattleHud", SPRITE).RaycastTarget, false);
  assert.equal(ui.getComponent("BattleHud", SPRITE).Color.a, 0);
  assert.equal(ui.getComponent("BattleHud/Surface", SPRITE).ImageRUID.DataId, BROWN_BASE);
  assert.ok(ui.getComponent("BattleHud/Surface", SPRITE).Color.a < 1, "only the background is translucent");
  const frame = ui.getComponent("BattleHud/PackageFrame", SPRITE);
  assert.equal(frame.ImageRUID.DataId, CARD_FRAME);
  assert.equal(frame.FillCenter, false);
  assert.equal(frame.RaycastTarget, false);
});

test("#51 result and configuration messages share the Cardgame popup; stats sit on brown", () => {
  const ui = UIBuilder.read("ui/BattleGroup.ui");
  assert.ok(ui.getComponent("BattleResultPanel/Window", SPRITE).ImageRUID.DataId.startsWith(CARD_POPUP));
  for (const stat of ["PlayerStat", "EnemyStat"]) {
    assert.equal(ui.getComponent(`BattleResultPanel/Window/${stat}`, SPRITE).ImageRUID.DataId, BROWN_BASE, stat);
  }
  const config = UIBuilder.read("ui/BattleConfigErrorGroup.ui");
  assert.ok(config.getComponent("ConfigErrorPanel/ConfigErrorFrame", SPRITE).ImageRUID.DataId.startsWith(CARD_POPUP));
});

test("#51 the result screen has one return action with the Cardgame button states", () => {
  const match = UIBuilder.read("ui/MatchGroup.ui");
  assert.equal(match.find("BattleResult").jsonString.enable, false, "hidden until a result exists");
  assert.ok(match.find("BattleResult/Status"));
  const action = match.getComponent("BattleResult/Action", "MOD.Core.ButtonComponent");
  assert.deepEqual(action, match.getComponent("BattleMatch/Action", "MOD.Core.ButtonComponent"), "same SpriteSwap states");
  assert.equal(match.getComponent("BattleResult/Action", SPRITE).RaycastTarget, true);
});

test("#51 one owner resolves the viewer's result and the battle screen leaves the field clear", () => {
  const controller = fs.readFileSync("RootDesk/MyDesk/Combat/BattleUIController.mlua", "utf8");
  assert.match(controller, /session:ResultForProfile\(profile\)/);
  assert.match(controller, /initialPlayer, initialEnemy = initialEnemy, initialPlayer/);
  const input = fs.readFileSync("RootDesk/MyDesk/Combat/BattleDeploymentInput.mlua", "utf8");
  assert.doesNotMatch(input, /SetResultEntities|resultPlayerText/, "the POC adapter no longer draws results");
  const match = fs.readFileSync("RootDesk/MyDesk/Matchmaking/MatchFlowInput.mlua", "utf8");
  assert.match(match, /_BattleUIController\.OwnResult/);
  assert.match(match, /self\.Snapshot\.state == "BATTLE"/);
  assert.match(match, /_MatchFlow:RequestReturn\(self\.Snapshot\.attempt\)/, "the formal return request stays");
});

test("matched battlefield owns the formal viewer presentation", () => {
  const map = MapBuilder.read("map/matchprobe.map");
  const root = map.listEntities().find((entity) => entity.name === "matchprobe");
  assert.ok(root.componentNames.includes("script.BattleView"));
  assert.equal(map.component("matchprobe", "script.BattleSession").RequireMatchedFormations, true);
  assert.equal(map.getTileMapMode(), 1);

  const source = fs.readFileSync("RootDesk/MyDesk/Combat/BattleView.mlua", "utf8");
  assert.match(source, /session\.HomeProfile/);
  assert.match(source, /session\.AwayProfile/);
  assert.doesNotMatch(source, /BattleViewPrototype|battleviewprototype|IsPrototype/);
  assert.match(source, /SpawnByModelId\("battleviewvisual"/);
  assert.match(source, /SpawnByModelId\("battleviewavatar"/);
  assert.doesNotMatch(source, /Color\(1, 0, 0, 1\)[\s\S]*unit\.Faction == "ENEMY"/);

  for (const file of [
    "RootDesk/MyDesk/Combat/BattleUnit.mlua",
    "RootDesk/MyDesk/Combat/BattleHitEffectPresentation.mlua",
    "RootDesk/MyDesk/Combat/BattleUIController.mlua",
  ]) {
    assert.doesNotMatch(fs.readFileSync(file, "utf8"), /BattleViewPrototype/, file);
  }
});
