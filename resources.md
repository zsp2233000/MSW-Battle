# MapleStory Worlds UI Resources

## Knowledge

- [UI Editor — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/docs/?postId=120)
  Official Maker guide to the UI Editor, UIGroup, canvas, UI entities, and hierarchy. Use when navigating and composing the existing BattleGroup.
- [Basic UI Components — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/docs?postId=744)
  Official overview of UITransformComponent, SpriteGUIRendererComponent, ButtonComponent, and text. Use when choosing the parts of a monster card.
- [GridViewComponent — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/apiReference?postId=773)
  Official component reference for template cloning, cell layout, and reuse. Use when connecting the option template to data-driven cards.
- [SpriteGUIRendererComponent — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/apiReference/Components/SpriteGUIRendererComponent)
  Official reference for UI image resources, including sprite and animation-clip display. Use when showing each monster's stand art.
- [ButtonComponent — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/apiReference/Components/ButtonComponent)
  Official reference for button input and visual transitions. Use when making the whole card clickable and styling its states.
- [ImageComponent — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/apiReference?postId=939)
  The shared UI image settings, including image tint/color, alpha, and ImageRUID.
- [Controlling UI Entities — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/docs/?postId=1154)
  Official examples for enabling and disabling UI entities individually or by hierarchy.
- [Searching for Effects — MapleStory Worlds Creator Center](https://maplestoryworlds-creators.nexon.com/en/docs?postId=538)
  Official instructions for assigning a resource RUID to SpriteGUIRendererComponent.ImageRUID.

## Gaps

- Official docs explain component behavior but do not define this project's naming contract or the MonsterId-to-card mapping. Use [issue #6](https://github.com/zsp2233000/MSW-Battle/issues/6), [issue #7](https://github.com/zsp2233000/MSW-Battle/issues/7), and the local MonsterData CSV for those decisions.
