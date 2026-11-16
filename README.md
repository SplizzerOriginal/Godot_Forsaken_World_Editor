# PWE-Manager – Forsaken World in Godot

A fan project that brings the MMORPG *Forsaken World* (Angelica engine) to **Godot 4.7**:
an editor plugin that reads the original game data, plus a playable client/server game built on top of it.

> **No game assets are included.** You need your own copy of the original game client;
> all data is read from it at import time or at runtime.

## Patch Notes

### 2026-11-16

**Skills**
- Crowd control: stun, root, silence, disarm and immunities; the client locks input and greys out icons.
- Every starting skill of every class works (charge, heals, blessings, town portal).
- Passive skills and toggle skills / auras.
- Skill learning: class skills are learned automatically up to level 20, after that in the skill window for coins.
- Race skills are granted through the original hidden quests (from level 10); Prayer and the race blessings
  use the values from the client texts.
- Combined animations play their effects and sounds (e.g. the priest's heal).

**Quests**
- Monster and gathering objectives are links: a click starts auto-pathing to the nearest spawn;
  finished quests show a "Return to NPC" link.
- Quest EXP is scaled with the original level factor; quest minimum levels come from the server data.
- New quest rules: linked quests, buff requirements, "finish another quest n times", required items.
- Level-up rewards (trial essences), the level-up reward window and usable EXP cocktails.
- Quest log scrolls.

**Items & currency**
- Right-click to use or equip items; items can be destroyed (destroy button or drag out of the bag)
  with the original confirmation dialogs.
- Gathering points that need a tool take it from the bag automatically (e.g. the torch quest).
- Item tooltips run the game's own description scripts: original layout, icons, sell value.
- Soul coins (bound currency) from quests and monsters; skill learning spends them first.

**Character window**
- Two pages like the original (attributes / mastery and resistance) with the base values per level and active buffs.
- The 3D preview in the character window was removed (not in the original).

**World & collision**
- Building and cave collision is read from the building files like the original:
  no more falling through floors in the dwarf city or the Kindred area.
- The character climbs steps up to 0.8 m.
- The server places gathering points and monsters on cave floors instead of the terrain below.
- Auto-pathing walks around obstacles that the navigation map does not know.
- Town points per race; portal and revival use the nearest one.

**Tests**
- New test suites for all race/class combinations, quests, items and collision.

## Future Plans

**Next fixes**
- Werewolf priest / assassin: disconnect on the first login.
- Skill items and the werewolf quest chain.
- Original mouse cursors; the cursor hides and stays in place while turning the camera.
- Separate quest bag in the inventory.
- Combat rules: skills need a weapon, no attacking while running, auto-attack on the hotbar.
- Quest markers (main quests first), class-specific quest rewards, location-bound quest items.
- HUD: EXP numbers, portraits, comparison tooltip for equipment.
- UI scaling with the window size; loading screen, login window, class icons in the character editor.
- Models: monster sizes, player eyes, missing textures, helmets.
- Effects: distortion layers, lightning size, charge effect, loot sparkle, level-up effect, gathering animations.
- Name plates hidden behind buildings; water shader in s31.
- Chat channels and tabs (system, world, whisper).
- Class resource bars (warrior stances, assassin orbs, marksman and bard bars).
- Performance: convert all game data to Godot resources up front ("Create Godot Client / Server"),
  less stutter and memory.

**Skills**
- Monster skills, more skill effects (shields, cleanses, speed …), talents.

**Later**
- Day/night cycle by server time (server clock on the minimap tooltip).
- Terrain generator with paintable roads in the original look; connected maps with dynamic chunk loading.
- Skill editor: class → race → skill / buff / debuff / blessing, adjust values and texts.
- Monster inspection item: shows drops and drop chances (quest items included) from up to 50 m.
- Lighting: one-sided NPC lighting, baked map shadows.

## PWE-Manager (Godot editor plugin)

- **Reads the original client directly**: opens the game's `.pck` archives through a virtual file system,
  with no unpacking needed (including Chinese GBK-encoded file names and texts).
- **Models & animations**: characters, NPCs, monsters and equipment become Godot scenes with
  skeletons, animations, attachment points and animation events.
- **Visual effects**: the game's particle effect files are rebuilt as Godot nodes and shaders,
  with a preview player.
- **Maps**: terrain, buildings, water, lighting, ambient sounds and monster spawns are imported into one scene,
  along with the navigation data for pathfinding.
- **User interface**: the game's dialog layouts are rebuilt as Godot UI (textures, fonts, both UI skins).
- **Game data readers**: item and NPC database, quests, skills and status effects, plus a small
  interpreter for the client's compiled Lua scripts.
- **Data check**: compares client and server data (versions, quests, maps, spawns).

## The game (client + server, written in GDScript)

- **Own server**: encrypted networking, SQLite database, accounts with salted password hashing,
  and a server control panel inside the editor.
- **Login & character creation** in the original look, covering all races and classes, appearance options
  and a 3D preview.
- **Open world**: explore the starting map with other players, NPCs and roaming monsters;
  minimap, chat, and target selection by click or Tab.
- **Original HUD**: character and target frames, hotbars, skill window, inventory, character sheet,
  quest log and quest tracker, with two switchable UI skins.
- **Quests** from the original quest data: NPC dialogues, kill and collect objectives, rewards,
  and auto-pathing to quest NPCs and locations.
- **Inventory & equipment**: equipped weapons and armor appear on the character; gathering; item tooltips.
- **Combat**: auto-attack with the original damage formula, hits, crits and misses, monster AI
  (aggro, chase, return home), death and revival, experience and level-ups.
- **Skills**: cast bar, mana costs, cooldowns and range checks; values come from the original skill
  formulas; skill animations and effects.
- **Status effects**: buffs and debuffs (damage and healing over time, stat changes, stacking rules),
  shown as icons with timers and tooltips plus visual effects on the character.
- **Languages**: German, English and French.

## Getting started

1. Install **Godot 4.7** and the SQLite GDExtension
   [sqlite3.gd](https://github.com/Yeicor/sqlite3.gd) into `addons/sqlite3.gd/`.
2. Copy your original *Forsaken World* client into `Stock-PWE-Client/` (the `.pck` files stay packed),
   and your server files into `Stock-PWE-Server/` (both folders are ignored by Godot and git).
3. Open the project. The **PWE-Manager** docks appear in the editor: import a map (e.g. the starting map `s9`)
   with the ECM-GFX-MAP dock.
4. The game server needs data tables (`addons/PWE-Manager/Server/*.json`) that are generated from your own
   client and server files with the scripts in `addons/PWE-Manager/tools/server_data/`
   (usage is described at the top of each script).
5. Start the server from the SERVER dock, then run the project to log in and play.

## Testing

An automated test suite (bots, UI-driven world tests, class, quest, item and collision tests,
server restart/reconnect tests and a load test with 25 bots) runs headless and with the Vulkan and OpenGL renderers.

## Status

Work in progress, see *Patch Notes* and *Future Plans* at the top.

## Screenshots

<img width="1400" height="600" alt="GFX editor" src="https://github.com/user-attachments/assets/e9de8fd2-4dd6-4667-a52b-757088faa872" />

<img width="1000" height="1200" alt="GFX element properties" src="https://github.com/user-attachments/assets/e21b6dcd-f057-4037-92ab-7afc9e71dd1e" />

<img width="1920" height="1040" alt="Editor overview" src="https://github.com/user-attachments/assets/219eba5d-c5c7-43c4-b38d-44e000333331" />

<img width="895" height="519" alt="UI dialog (XML) view" src="https://github.com/user-attachments/assets/6ee0b583-80fb-4f85-ad94-bb1756ebe38c" />

## Disclaimer

Non-commercial fan project. Not affiliated with or endorsed by Perfect World or its subsidiaries.
*Forsaken World* and all related names are trademarks of their respective owners.
