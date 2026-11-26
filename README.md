# Hollowmoth

**Play in the browser: https://joshuamrumack-collab.github.io/hollowmoth/**

A pixel-art action RPG in the spirit of Diablo 2 and Dark Souls, with Pathfinder 1e dice and a four-hero party.
Three acts: the Hollowmarch Outskirts, the Cinderveil and the Starfall Mere. A game by **DorkTeach**, made in Godot 4.7.

- Desktop browser with a keyboard (or a gamepad). The first load is about 40 MB, so give it a moment.
- Progress is saved in your browser.
- WASD to move, mouse/keys to fight, **I** for the party and inventory, **R** in the inventory to socket sigils, **Esc** for the menu (Controls are listed there).

This repository is the web edition: the same game with smaller ground textures and the browser-friendly renderer.
The playable build lives in `docs/` (served by GitHub Pages). To build it yourself: open `project.godot` in Godot 4.7.2 and export the "Web" preset.

---

# Hollowmoth — Act I prototype

By DorkTeach. Godot 4.7. Open `project.godot` and press F5.

A slow, Souls-paced, Hades-style action RPG with Pathfinder 1e dice. The look follows Drova: a top-down 3/4 view, a night-time bog, teal pines and warm firelight. The game starts in fullscreen; press F11 to switch to a window.

**You play one hero.** On the select screen you pick Average, Puck, Brokk or Eowilas. Every bit of Starlight and every item you find goes to that hero. The other three follow you and fight on their own, and they level up as you clear areas (never above your level). If your hero falls, it's YOU DIED.

## The act: the Hollowmarch Outskirts

1. **Moth Shrine Camp** — rest (F), level up (L), campfire
2. **The Gallows Glade** — Mire Ghouls
3. **The Drowned Chapel** — ghouls and Hush Cultists among the ruins
4. **Brute Hollow** — two Bog Brutes and their pack
5. **The Iron Brother's Pit** — the boss (enrages at half HP)

When you step into an area its exits seal with thorns until every enemy is dead. Past the chapel there is a southern path back to camp: open the iron gate from the chapel side for a **shortcut**.

## The Souls loop

- **Rest** at the Moth Shrine to heal and refill spell slots, herbs, arcane pool and five draughts. Every enemy except the Iron Brother comes back.
- **Starlight** is both your XP and your currency. Spend it at the shrine (L) to level your hero: more HP, attack, saves, AC and damage. Puck also gets more sneak-attack dice, and Eowilas bigger heals.
- **Death:** if your hero falls, you wake at the shrine and your Starlight is left as a glowing moth where you died. Walk over it to get it back. Die again before then and it's gone. Fallen companions get back up when you rest, and Eowilas (if she's a companion) revives them mid-fight.

## Loot

Enemies and cleared areas drop bags. Walk over one, or press F, to pick it up. If an item beats what your hero has, it's equipped. If not, it's turned into Starlight.

- **Rarities:** normal, magic (blue), rare (yellow), unique (orange)
- **Properties** use Pathfinder 1e names: +1 to +3 enhancement, *flaming*, *keen*, *vicious*, *of the Bear*, *of the Leech*, *of Fortitude*, *of Protection* and more

Press I to see the party, their stats and their gear.

## Controls

| Action | Keyboard + mouse | Gamepad |
| --- | --- | --- |
| Move / aim | WASD / mouse | Left stick / right stick (soft auto-aim) |
| Attack (press again to combo) | Left click | X |
| Special | Right click | Y |
| Cast | Q | RT |
| Dash (i-frames, max 2 in a row) | Space | A |
| Parry (tap) / block (hold) | Shift | LB |
| Abilities | 1, 2, 3 | — |
| Healing draught | E | B |
| Interact (rest, gate, loot) | F | Back |
| Level up at the shrine | L | — |
| Party & gear | I | Pause menu → The Party |
| Pause menu | Esc | Start |
| Fullscreen / window | F11 | — |

## Menus and options

The game opens on a title screen (Begin, Options, Controls, Credits, Quit). Esc pauses the game: Resume, The Party, Options, Controls, Credits, Quit to title. The party screen and the shrine's level-up screen also pause the fight.

Options are saved to `user://settings.cfg`: fullscreen, screen shake, hit-stop, hit flash, dice rolls on screen (off by default; the Pathfinder d20 log) and hints (button prompts at the shrine, gate and loot).

## HUD

- Top left: your hero's portrait, HP bar (a pale strip shows damage just taken), stamina bar, and their resource (glory, herbs, arcane pool, spell slots). Your companions sit under it, small, with HP only.
- Bottom left: ability slots with their keys and cooldowns, then your draughts.
- Bottom right: Starlight.
- Bottom centre: the boss bar, and prompts when you can interact.

## Hit feedback

Hits use **Sprite Juice Kit Lite** (`addons/sprite_juice_lite`, MIT, autoload `JuiceLite`): enemies flash white, light enemies are knocked back further and flinch out of their wind-up, and the camera shakes when your hero lands or takes a hit (harder on crits, with a short hit-stop).

## Heroes

| Hero | Attack | Special | Cast (Q) | 1 / 2 / 3 |
| --- | --- | --- | --- | --- |
| **Average** | Greataxe combo | Overhead cleave | Ground Slam | Rage / Look At Me! (full Glory) / – |
| **Puck** | Rapier combo, sneak attack | Lunge | Burn herb as smoke | Next herb / Pass it around / Haze |
| **Brokk** | Bow | Power shot | Spell arrow | Next spell / Dwarven Stand / Many Shot |
| **Eowilas** | Starknife (weak) | Starknife throw | Channel heal | Silence / Break the Chains / Breath of Life |

## Art

All art is original, made by the Python scripts in `tools/artgen/` (needs Pillow and NumPy):

- `render3d.py` — the characters, made the way Diablo 2 made its sprites. Each one is a small 3D puppet (a skeleton dressed in capsules and spheres), posed for every frame and rendered to pixel art with lighting from the upper left, hue-shifted colour ramps, an outline and inner contour lines.
  - Animations: idle (4 frames), walk (8), attack (6, with a motion smear), hurt (2), cast (4) and death (6).
  - Each animation comes in three views: down, side and up.
  - Body proportions, colours and weapons are in the `CHARS` table.
- `props2.py` — trees, rocks, ruins, shrine, campfire and the other props (uses the drawings in `sprites.py`)
- `level.py` — the ground texture and the level layout (`assets/level.json`)

Everything is drawn at twice the game's pixel density and shown at half scale, for finer detail.

To regenerate: run `python3 render3d.py && python3 props2.py && python3 level.py`, then copy `out/*` into `assets/`.

## Files

| File | What it does |
| --- | --- |
| `scripts/main.gd` | Level, areas and seals, gate, shrine, death and Starlight, loot, lighting, rain, lightning, fog, HUD, menus |
| `scripts/combatant.gd` | HP, stamina, poise, PF1e conditions, the action state machine and directional sprite animation |
| `scripts/hero.gd` | The four kits, input, party AI, gear and levelling |
| `scripts/enemy.gd` | Enemy stat blocks and AI with red telegraphs |
| `scripts/rules.gd` | d20 attacks (hit / graze / crit with confirm) and saves |
| `scripts/items.gd` | Loot generation |
| `scripts/art.gd` | Loads the sprite sheets and level data |
| `scripts/settings.gd` | Saved options (autoload `Settings`) |
| `tools/menu_test.gd` | Headless check of the menu flow |

## Automated test

`godot --headless --path . --fixed-fps 60 -- --autotest` — the AI party walks the whole act, uses every system, dies, recovers and kills the boss.

`godot --headless --path . --script res://tools/menu_test.gd` — walks the title, options, pause and party menus with simulated key presses.
