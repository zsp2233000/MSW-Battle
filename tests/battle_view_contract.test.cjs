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
