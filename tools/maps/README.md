# Drawing Hollowmoth levels in Tiled

Tiled (free): https://www.mapeditor.org. Open `example.tmj` here to see a full level.

## The layers (object layers; the names matter)
1 Tiled pixel = 1 game unit. The faded picture underneath (`preview`) is the painted
result of the last import, so you can draw over it.

| Layer | What to draw | Settings (Custom Properties) |
|---|---|---|
| `clearings` | Polygons (or rectangles/ellipses) where you can walk. The **Name** is the area id. | `title` (text shown on entry), `enemies` (e.g. `ghoul, ghoul, cultist`), `boss` (bool), `seal` (bool: the way closes until the fight is won), `floor` (`flag`, `bones` or `mud`) |
| `roads` | Polylines between clearings. | `width` (default 70) |
| `water` | Polylines for rivers and streams. You can't walk through them. | `width` (default 70) |
| `crossings` | A point on the water. **Class** = `bridge` or `ford`. | |
| `markers` | Points named `shrine` (required), `campfire`, `gate`; optional polyline named `route` (the path the test bot walks). | gate: `open_from` = `0,-1` (the side it opens from) |
| `props` | Points whose **Class** is a prop name: `brazier`, `ruin_wall_0..2`, `gibbet`, `standing_stone`, `rock_0`, `bones`, `corpse_0`... | |

The forest, grass and rocks fill themselves in around what you draw.

Enemy types: `ghoul`, `cultist`, `brute`, `iron_brother` (Act I);
`mirror_wraith`, `shadow_moth`, `dragon` (Act II bosses).

## Making it playable
Save the map in this folder, then either ask Claude to import it, or run (needs Python with
numpy, pillow and scipy: `pip install numpy pillow scipy`):

    python tools/artgen/tiled_import.py tools/maps/mylevel.tmj

In the game, the title screen shows **Try: mylevel** (editor/debug runs only).
Test levels never touch your save.
