"""Generates the city's tile layout, world/city_layout.txt.

The original hand-made block (tools/city_core.txt) sits in the middle,
untouched, so everything placed around it keeps its position. Around it the
street grid carries on across the whole map, and the blocks between streets
are filled with buildings, parks and vacant lots.

Streets are laid out 3 tiles wide (like the core), then every street is
widened to ROAD_WIDTH by repeating its middle lane, so there's room for cars
both ways.

Run from the project root: python3 tools/make_city_layout.py

Tile characters (see scripts/city_grid.gd):
  . road   = sidewalk   , dirt   g grass   # brick building   B tan building
  c crate   C two stacked crates   w low wall
"""
import random
from pathlib import Path

WIDTH, HEIGHT = 256, 192
# Before widening, streets are 3 tiles wide and repeat every STREET_EVERY
# tiles, lined up with the streets in the core.
STREET_EVERY = (24, 18)
STREET_FIRST = (5, 4)
ROAD_WIDTH = 5
# The player's garage, beside the shop: a lot cut out of the block for the
# garage building (scenes/garage.tscn) to stand on, opening onto the main
# street. World tile coordinates (x0, z0, x1, z1), inclusive, after widening.
GARAGE_LOT = (16, -10, 19, -5)


def widened_lines():
    """The middle column and row of every street, before widening: each is
    repeated so the street ends up ROAD_WIDTH wide."""
    columns = [x for x in range(WIDTH) if (x - STREET_FIRST[0]) % STREET_EVERY[0] == 1]
    rows = [y for y in range(HEIGHT) if (y - STREET_FIRST[1]) % STREET_EVERY[1] == 1]
    return columns, rows


def widen(lines):
    columns, rows = widened_lines()
    extra = ROAD_WIDTH - 3
    out = []
    for y, line in enumerate(lines):
        wide = "".join(c * (1 + extra) if x in columns else c for x, c in enumerate(line))
        out.extend([wide] * (1 + extra if y in rows else 1))
    return out


def main():
    root = Path(__file__).resolve().parent.parent
    core = (root / "tools" / "city_core.txt").read_text().split()
    core_w, core_h = len(core[0]), len(core)
    ox, oy = (WIDTH - core_w) // 2, (HEIGHT - core_h) // 2
    rng = random.Random(1985)

    def is_street(x, y):
        return (x - STREET_FIRST[0]) % STREET_EVERY[0] < 3 or (y - STREET_FIRST[1]) % STREET_EVERY[1] < 3

    def is_sidewalk(x, y):
        if is_street(x, y):
            return False
        return any(0 <= x + dx < WIDTH and 0 <= y + dy < HEIGHT and is_street(x + dx, y + dy)
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    # Every block gets a kind, from its position in the street grid.
    kinds = {}

    def block_kind(x, y):
        key = ((x - STREET_FIRST[0]) // STREET_EVERY[0], (y - STREET_FIRST[1]) // STREET_EVERY[1])
        if key not in kinds:
            roll = rng.random()
            kinds[key] = "#" if roll < 0.32 else "B" if roll < 0.64 else "park" if roll < 0.82 else "lot"
        return kinds[key]

    grid = []
    for y in range(HEIGHT):
        row = []
        for x in range(WIDTH):
            if is_street(x, y):
                row.append(".")
            elif is_sidewalk(x, y):
                row.append("=")
            else:
                kind = block_kind(x, y)
                block_x = (x - STREET_FIRST[0]) % STREET_EVERY[0]
                if kind in "#B":
                    # Buildings with a grass alley through the middle.
                    row.append("g" if block_x == 15 else kind)
                elif kind == "park":
                    row.append("w" if rng.random() < 0.03 else "g")
                else:
                    r = rng.random()
                    row.append("C" if r < 0.02 else "c" if r < 0.06 else ",")
        grid.append(row)
    for y, line in enumerate(core):
        grid[oy + y][ox:ox + core_w] = list(line)

    lines = widen(["".join(r) for r in grid])
    half_x, half_z = len(lines[0]) // 2, len(lines) // 2
    x0, z0, x1, z1 = GARAGE_LOT
    for z in range(z0, z1 + 1):
        row = list(lines[z + half_z])
        row[x0 + half_x:x1 + half_x + 1] = "." * (x1 - x0 + 1)
        lines[z + half_z] = "".join(row)
    out = root / "world" / "city_layout.txt"
    out.write_text("\n".join(lines) + "\n")
    print(f"Wrote {out.relative_to(root)}: {len(lines[0])} x {len(lines)}")


if __name__ == "__main__":
    main()
