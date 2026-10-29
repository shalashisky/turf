"""Generates placeholder sprite sheets so movement and aiming can be tested
before real art exists. Run from the project root: python3 tools/make_placeholder_art.py

player_8dir.png: 4 columns x 8 rows of 32x32 frames.
  Rows (facing, clockwise from "toward the camera"): s, se, e, ne, n, nw, w, sw
  Columns: 0 = idle, 1-3 = walk cycle
dummy_8dir.png: same layout as the player sheet, without the facing arrow. The dummy gang, in blue.
panther_8dir.png: same layout, a Black Panther: a black cat in a leather jacket.
yellow_8dir.png: same layout, a member of the Yellows.
cia_8dir.png: same layout, a CIA agent in a black suit and sunglasses.
homeless_1_8dir.png, homeless_2_8dir.png: same layout, long beards and beanies.
druggie_8dir.png: same layout, a pale, strung-out druggie in a stained hoodie.
crew_8dir.png: same layout, one of the player's own crew, in the player's red.
guy_8dir.png: same layout, Guy: a gaunt old session violinist in a faded denim shirt.
rap_dawg_8dir.png: same layout, a dog in a beanie, for the Rap Dawg neighbor.
clerk_8dir.png: same layout, a store clerk in a green apron.
pedestrian_1_8dir.png .. pedestrian_3_8dir.png: same layout, passers-by in different outfits.
cash.png: 14x8 dollar bill, for cash drops.
pistol.png: 14x9 pistol pointing right, grip at the left.
weed_bag.png: 12x12 knotted baggie of green buds, a hotbar icon.
seed_packet.png: 10x12 paper seed packet with a leaf on it, a hotbar icon.
burger.png: 12x10 burger, a hotbar icon.
cocaine.png: 10x10 little baggie of white powder, a hotbar icon.
grow_tray.png: 16x10 hydroponic tray with a sprout in it, a hotbar icon.
molotov.png: 14x7 bottle lying neck-right, with a burning rag in the neck.
tec9.png: 20x11 machine pistol pointing right: long receiver, perforated
  barrel shroud, and the magazine in front of the grip.
cop_8dir.png: same layout as the player sheet, a beat cop in uniform and cap.
nightstick.png: 20x6 police baton pointing right, handle at the left.
shadow_blob.png: soft round shadow projected under the player.
baseball_bat.png: 24x8 bat pointing right, grip at the left edge.
pickup_arrow.png: 11x10 green arrow pointing down, shown above pickups.
fist.png: 10x9 fist punching right, wrist at the left edge.
brass_knuckles.png: the fist with a brass band across the knuckles.
knife.png: 20x6 knife pointing right, handle at the left edge.
weed_plant.png: 5 frames of 32x32, seedling to ready-to-harvest.
"""
import struct
import zlib
from pathlib import Path

FRAME = 32
COLUMNS = 4
# Screen-space facing for each sheet row (x right, y down).
DIRECTIONS = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]

OUTLINE = (20, 16, 24, 255)
ARROW = (255, 220, 50, 255)

PLAYER = {
    "jacket": (200, 40, 50, 255),
    "stripe": (240, 240, 240, 255),
    "pants": (50, 70, 130, 255),
    "shoes": (235, 235, 235, 255),
    "skin": (140, 90, 60, 255),
    "hair": (25, 20, 20, 255),
}
RAP_DAWG = {
    "jacket": (70, 175, 235, 255),
    "stripe": (70, 175, 235, 255),
    "pants": (35, 55, 140, 255),
    "shoes": (220, 45, 45, 255),
    "skin": (150, 100, 60, 255),  # fur
    "hair": (240, 120, 30, 255),  # beanie
    "dog": True,
}
CLERK = {
    "jacket": (60, 140, 85, 255),
    "stripe": (235, 235, 225, 255),
    "pants": (95, 70, 50, 255),
    "shoes": (40, 35, 35, 255),
    "skin": (190, 140, 100, 255),
    "hair": (150, 150, 150, 255),
}
PEDESTRIANS = [
    {"jacket": (210, 170, 60, 255), "stripe": (240, 225, 170, 255), "pants": (60, 60, 70, 255),
     "shoes": (235, 235, 235, 255), "skin": (120, 80, 50, 255), "hair": (30, 25, 25, 255)},
    {"jacket": (90, 160, 150, 255), "stripe": (90, 160, 150, 255), "pants": (130, 110, 80, 255),
     "shoes": (90, 60, 40, 255), "skin": (230, 190, 160, 255), "hair": (200, 160, 60, 255)},
    {"jacket": (160, 60, 140, 255), "stripe": (235, 235, 235, 255), "pants": (40, 40, 60, 255),
     "shoes": (240, 240, 240, 255), "skin": (180, 130, 90, 255), "hair": (90, 50, 30, 255)},
]
COP = {
    "jacket": (35, 50, 115, 255),
    "stripe": (225, 200, 80, 255),  # gold trim
    "pants": (25, 32, 75, 255),
    "shoes": (20, 20, 25, 255),
    "skin": (160, 110, 75, 255),
    "hair": (30, 40, 95, 255),  # the cap
}
DUMMY = {
    "jacket": (60, 110, 210, 255),
    "stripe": (220, 230, 255, 255),
    "pants": (40, 50, 90, 255),
    "shoes": (40, 40, 40, 255),
    "skin": (200, 160, 130, 255),
    "hair": (60, 40, 30, 255),
}
PANTHER = {
    "jacket": (30, 28, 32, 255),  # leather
    "stripe": (150, 150, 160, 255),
    "pants": (25, 25, 30, 255),
    "shoes": (60, 50, 45, 255),
    "skin": (42, 40, 48, 255),  # black fur
    "hair": (42, 40, 48, 255),
    "cat": True,
}
YELLOW = {
    "jacket": (240, 200, 40, 255),
    "stripe": (40, 40, 40, 255),
    "pants": (40, 40, 40, 255),
    "shoes": (240, 200, 40, 255),
    "skin": (180, 130, 90, 255),
    "hair": (25, 20, 20, 255),
}
CIA = {
    "jacket": (28, 28, 34, 255),  # suit
    "stripe": (28, 28, 34, 255),
    "pants": (28, 28, 34, 255),
    "shoes": (15, 15, 18, 255),
    "skin": (210, 170, 140, 255),
    "hair": (40, 30, 25, 255),
    "sunglasses": True,
}
DRUGGIE = {
    "jacket": (105, 120, 85, 255),  # stained hoodie
    "stripe": (85, 95, 70, 255),
    "pants": (70, 75, 90, 255),
    "shoes": (55, 50, 50, 255),
    "skin": (215, 200, 180, 255),  # pale
    "hair": (120, 100, 70, 255),
}
CREW = {
    "jacket": (190, 35, 45, 255),
    "stripe": (30, 28, 30, 255),
    "pants": (35, 35, 42, 255),
    "shoes": (235, 235, 235, 255),
    "skin": (120, 80, 55, 255),
    "hair": (200, 35, 45, 255),  # bandana
}
GUY = {
    "jacket": (95, 125, 170, 255),  # faded denim shirt
    "stripe": (125, 155, 195, 255),
    "pants": (60, 55, 50, 255),
    "shoes": (40, 35, 30, 255),
    "skin": (215, 190, 140, 255),
    "hair": (170, 165, 145, 255),
}
HOMELESS = [
    {"jacket": (110, 85, 60, 255), "stripe": (90, 70, 50, 255), "pants": (70, 70, 60, 255),
     "shoes": (50, 40, 35, 255), "skin": (190, 145, 110, 255), "hair": (120, 110, 100, 255),
     "beard": (150, 140, 130, 255), "beanie": (150, 50, 45, 255)},
    {"jacket": (75, 90, 70, 255), "stripe": (60, 72, 55, 255), "pants": (90, 80, 65, 255),
     "shoes": (45, 40, 35, 255), "skin": (140, 95, 65, 255), "hair": (60, 50, 45, 255),
     "beard": (90, 80, 72, 255), "beanie": (60, 90, 130, 255)},
]


def new_image(width, height):
    return [[(0, 0, 0, 0)] * width for _ in range(height)]


def rect(image, x0, y0, x1, y1, color):
    height, width = len(image), len(image[0])
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < width and 0 <= y < height:
                image[y][x] = color


def draw_character(palette, facing, step, arrow):
    frame = new_image(FRAME, FRAME)
    dx, dy = facing
    bob = 1 if step in (1, 3) else 0
    left_lift = 1 if step == 1 else 0
    right_lift = 1 if step == 3 else 0

    # Legs and shoes
    rect(frame, 12, 24 - left_lift, 14, 28 - left_lift, palette["pants"])
    rect(frame, 17, 24 - right_lift, 19, 28 - right_lift, palette["pants"])
    rect(frame, 12, 29 - left_lift, 14, 30 - left_lift, palette["shoes"])
    rect(frame, 17, 29 - right_lift, 19, 30 - right_lift, palette["shoes"])

    # Tracksuit jacket with side stripes
    rect(frame, 10, 14 - bob, 21, 23 - bob, palette["jacket"])
    rect(frame, 10, 14 - bob, 10, 23 - bob, palette["stripe"])
    rect(frame, 21, 14 - bob, 21, 23 - bob, palette["stripe"])

    if palette.get("dog"):
        draw_dog_head(frame, palette, dx, dy, bob)
        add_outline(frame)
        return frame
    if palette.get("cat"):
        draw_cat_head(frame, palette, dx, dy, bob)
        add_outline(frame)
        return frame

    # Head: hair covers the back of the head when facing away
    rect(frame, 12, 5 - bob, 19, 13 - bob, palette["skin"])
    if dy < 0:
        rect(frame, 12, 4 - bob, 19, 12 - bob, palette["hair"])
    else:
        rect(frame, 12, 4 - bob, 19, 6 - bob, palette["hair"])
        if dx:
            back = 12 if dx > 0 else 19
            rect(frame, back, 4 - bob, back, 10 - bob, palette["hair"])
        eye_shift = dx * 2
        if palette.get("sunglasses"):
            rect(frame, 13 + eye_shift, 9 - bob, 18 + eye_shift, 9 - bob, OUTLINE)
        else:
            if dy > 0 or dx == 0:
                rect(frame, 14 + eye_shift, 9 - bob, 14 + eye_shift, 10 - bob, OUTLINE)
            rect(frame, 17 + eye_shift, 9 - bob, 17 + eye_shift, 10 - bob, OUTLINE)
        if palette.get("beard"):
            # Long and scraggly, hanging down over the coat.
            rect(frame, 13 + dx, 11 - bob, 18 + dx, 15 - bob, palette["beard"])
            rect(frame, 14 + dx, 16 - bob, 17 + dx, 17 - bob, palette["beard"])
    if palette.get("beanie"):
        rect(frame, 11, 2 - bob, 20, 6 - bob, palette["beanie"])
        rect(frame, 11, 6 - bob, 20, 6 - bob, tuple(max(c - 40, 0) for c in palette["beanie"][:3]) + (255,))

    add_outline(frame)

    if arrow:
        length = (dx * dx + dy * dy) ** 0.5
        ux, uy = dx / length, dy / length
        cx, cy = 15.5, 18.5 - bob
        for i in range(10):
            x, y = int(round(cx + ux * i)), int(round(cy + uy * i))
            rect(frame, x, y, x, y, ARROW)
        tip_x, tip_y = int(round(cx + ux * 10)), int(round(cy + uy * 10))
        rect(frame, tip_x - 1, tip_y - 1, tip_x + 1, tip_y + 1, ARROW)
    return frame


def draw_cat_head(frame, palette, dx, dy, bob):
    fur = palette["skin"]
    eyes = (235, 205, 60, 255)
    rect(frame, 12, 5 - bob, 19, 13 - bob, fur)
    # Pointed ears.
    for x0, x1 in ((12, 13), (18, 19)):
        rect(frame, x0, 3 - bob, x1, 4 - bob, fur)
    rect(frame, 12, 2 - bob, 12, 2 - bob, fur)
    rect(frame, 19, 2 - bob, 19, 2 - bob, fur)
    if dy >= 0:
        eye_shift = dx * 2
        if dy > 0 or dx == 0:
            rect(frame, 14 + eye_shift, 8 - bob, 14 + eye_shift, 9 - bob, eyes)
        rect(frame, 17 + eye_shift, 8 - bob, 17 + eye_shift, 9 - bob, eyes)
        nose = 15 + dx * 2
        rect(frame, nose, 11 - bob, nose + 1, 11 - bob, (210, 120, 140, 255))
        # Whiskers.
        rect(frame, 11, 11 - bob, 12, 11 - bob, (150, 150, 155, 255))
        rect(frame, 19, 11 - bob, 20, 11 - bob, (150, 150, 155, 255))


def draw_dog_head(frame, palette, dx, dy, bob):
    fur = palette["skin"]
    ears = (25, 20, 20, 255)
    muzzle = (205, 165, 115, 255)
    rect(frame, 12, 5 - bob, 19, 13 - bob, fur)
    # Floppy ears hang down either side, on the far side only when side-on.
    if dx >= 0:
        rect(frame, 10, 6 - bob, 11, 12 - bob, ears)
    if dx <= 0:
        rect(frame, 20, 6 - bob, 21, 12 - bob, ears)
    # Beanie, with a frog badge on the front.
    rect(frame, 11, 2 - bob, 20, 6 - bob, palette["hair"])
    if dy >= 0:
        badge = 15 + dx * 2
        rect(frame, badge, 4 - bob, badge + 1, 5 - bob, (70, 185, 80, 255))
        eye_shift = dx * 2
        if dy > 0 or dx == 0:
            rect(frame, 14 + eye_shift, 8 - bob, 14 + eye_shift, 8 - bob, OUTLINE)
        rect(frame, 17 + eye_shift, 8 - bob, 17 + eye_shift, 8 - bob, OUTLINE)
        snout = 14 + dx * 3
        rect(frame, snout, 10 - bob, snout + 3, 12 - bob, muzzle)
        rect(frame, snout + 1, 10 - bob, snout + 2, 10 - bob, OUTLINE)  # nose


def add_outline(image):
    height, width = len(image), len(image[0])
    solid = [[image[y][x][3] > 0 for x in range(width)] for y in range(height)]
    for y in range(height):
        for x in range(width):
            if solid[y][x]:
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height and solid[ny][nx]:
                    image[y][x] = OUTLINE
                    break


def blit(image, frame, ox, oy):
    for y in range(FRAME):
        image[oy + y][ox : ox + FRAME] = frame[y]


def write_png(path, image):
    height, width = len(image), len(image[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in image)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def draw_sheet(palette, arrow):
    sheet = new_image(FRAME * COLUMNS, FRAME * len(DIRECTIONS))
    for row, facing in enumerate(DIRECTIONS):
        for column in range(COLUMNS):
            blit(sheet, draw_character(palette, facing, column, arrow), column * FRAME, row * FRAME)
    return sheet


def main():
    art = Path(__file__).resolve().parent.parent / "art"
    art.mkdir(exist_ok=True)

    write_png(art / "player_8dir.png", draw_sheet(PLAYER, arrow=True))
    write_png(art / "dummy_8dir.png", draw_sheet(DUMMY, arrow=False))
    write_png(art / "panther_8dir.png", draw_sheet(PANTHER, arrow=False))
    write_png(art / "yellow_8dir.png", draw_sheet(YELLOW, arrow=False))
    write_png(art / "cia_8dir.png", draw_sheet(CIA, arrow=False))
    for i, palette in enumerate(HOMELESS):
        write_png(art / ("homeless_%d_8dir.png" % (i + 1)), draw_sheet(palette, arrow=False))
    write_png(art / "rap_dawg_8dir.png", draw_sheet(RAP_DAWG, arrow=False))
    write_png(art / "druggie_8dir.png", draw_sheet(DRUGGIE, arrow=False))
    write_png(art / "crew_8dir.png", draw_sheet(CREW, arrow=False))
    write_png(art / "guy_8dir.png", draw_sheet(GUY, arrow=False))
    write_png(art / "clerk_8dir.png", draw_sheet(CLERK, arrow=False))
    for i, palette in enumerate(PEDESTRIANS):
        write_png(art / ("pedestrian_%d_8dir.png" % (i + 1)), draw_sheet(palette, arrow=False))
    write_png(art / "cash.png", draw_cash())
    write_png(art / "pistol.png", draw_pistol())
    write_png(art / "tec9.png", draw_tec9())
    write_png(art / "molotov.png", draw_molotov())
    write_png(art / "weed_bag.png", draw_weed_bag())
    write_png(art / "seed_packet.png", draw_seed_packet())
    write_png(art / "burger.png", draw_burger())
    write_png(art / "cocaine.png", draw_cocaine())
    write_png(art / "grow_tray.png", draw_grow_tray())
    write_png(art / "nightstick.png", draw_nightstick())
    write_png(art / "cop_8dir.png", draw_sheet(COP, arrow=False))
    write_png(art / "shadow_blob.png", draw_blob(32))
    write_png(art / "baseball_bat.png", draw_bat())
    write_png(art / "pickup_arrow.png", draw_pickup_arrow())
    write_png(art / "fist.png", draw_fist())
    write_png(art / "brass_knuckles.png", draw_fist(brass=True))
    write_png(art / "knife.png", draw_knife())
    plants = new_image(32 * 5, 32)
    for stage in range(5):
        frame = draw_weed_plant(stage)
        for y in range(32):
            plants[y][stage * 32 : stage * 32 + 32] = frame[y]
    write_png(art / "weed_plant.png", plants)


def draw_bat():
    image = new_image(24, 8)
    tape = (45, 35, 40, 255)
    wood = (205, 160, 100, 255)
    shine = (235, 205, 150, 255)
    rect(image, 1, 2, 2, 5, tape)  # knob
    rect(image, 3, 3, 8, 4, tape)  # taped grip
    rect(image, 9, 3, 13, 4, wood)  # taper
    rect(image, 14, 2, 22, 5, wood)  # barrel
    rect(image, 14, 2, 21, 2, shine)
    rect(image, 22, 2, 22, 2, (0, 0, 0, 0))  # round off the end cap
    rect(image, 22, 5, 22, 5, (0, 0, 0, 0))
    add_outline(image)
    return image


def draw_fist(brass=False):
    image = new_image(10, 9)
    skin = (175, 125, 90, 255)
    shade = (135, 90, 62, 255)
    rect(image, 1, 3, 2, 5, skin)  # wrist
    rect(image, 3, 1, 8, 7, skin)  # fist
    rect(image, 8, 2, 8, 6, shade)  # knuckle face
    for y in (3, 5):
        rect(image, 6, y, 8, y, shade)  # finger creases
    rect(image, 4, 6, 6, 7, shade)  # thumb
    if brass:
        rect(image, 7, 1, 8, 7, (215, 170, 55, 255))  # band over the knuckles
        rect(image, 7, 1, 7, 7, (250, 220, 120, 255))  # shine
    add_outline(image)
    return image


def draw_knife():
    image = new_image(20, 6)
    rect(image, 1, 2, 6, 3, (70, 45, 30, 255))  # handle
    rect(image, 2, 2, 2, 3, (110, 75, 50, 255))  # rivet
    rect(image, 7, 1, 7, 4, (120, 120, 130, 255))  # guard
    rect(image, 8, 2, 16, 3, (200, 205, 215, 255))  # blade
    rect(image, 8, 2, 15, 2, (240, 245, 250, 255))  # edge shine
    rect(image, 17, 2, 17, 2, (200, 205, 215, 255))  # point
    add_outline(image)
    return image


def draw_line(image, x0, y0, x1, y1, color):
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        x = round(x0 + (x1 - x0) * i / steps)
        y = round(y0 + (y1 - y0) * i / steps)
        rect(image, x, y, x, y, color)


def draw_fan_leaf(image, x, y, size, color, tilt=0.0):
    """A pot leaf: thin blades fanning out from (x, y), pointing up."""
    import math
    for angle, scale in ((-70, 0.45), (-40, 0.75), (-15, 0.95), (0, 1.0), (15, 0.95), (40, 0.75), (70, 0.45)):
        a = math.radians(angle + tilt)
        length = size * scale
        draw_line(image, x, y, round(x + math.sin(a) * length), round(y - math.cos(a) * length), color)


def draw_weed_plant(stage):
    image = new_image(32, 32)
    stem = (70, 120, 50, 255)
    leaf = (60, 150, 60, 255)
    dark = (40, 110, 45, 255)
    pale = (150, 170, 70, 255)
    bud = (120, 160, 80, 255)
    hair = (235, 235, 225, 255)
    ripe = (170, 110, 190, 255)
    orange = (220, 130, 50, 255)
    base = 30
    if stage == 0:
        draw_line(image, 16, base, 16, base - 4, stem)
        rect(image, 13, base - 5, 15, base - 4, leaf)
        rect(image, 17, base - 5, 19, base - 4, leaf)
    else:
        height = (10, 18, 25, 26)[stage - 1]
        top = base - height
        draw_line(image, 16, base, 16, top, stem)
        # Pairs of fan leaves up the stem, bigger toward the bottom.
        levels = (1, 2, 4, 4)[stage - 1]
        for i in range(levels):
            y = base - 3 - i * (height - 4) // max(levels, 1)
            size = max(3, (4, 6, 7, 7)[stage - 1] - i)
            color = pale if stage == 4 and i == 0 else (leaf if i % 2 == 0 else dark)
            draw_fan_leaf(image, 15, y, size, color, tilt=-55)
            draw_fan_leaf(image, 17, y, size, color, tilt=55)
        draw_fan_leaf(image, 16, top + 2, (3, 4, 5, 4)[stage - 1], leaf)
        if stage >= 3:
            # Colas: bud clusters on the top and the side branches.
            spots = [(16, top + 1)] + [(16 + dx, top + 6 + i * 6) for i, dx in enumerate((-5, 5, -6, 6)) if top + 6 + i * 6 < base - 6]
            for bx, by in spots:
                rect(image, bx - 1, by - 2, bx + 1, by + 2, ripe if stage == 4 else bud)
                rect(image, bx, by - 3, bx, by - 3, ripe if stage == 4 else bud)
                for hx, hy in ((bx - 1, by - 1), (bx + 1, by + 1), (bx, by - 3)):
                    rect(image, hx, hy, hx, hy, orange if stage == 4 else hair)
    add_outline(image)
    return image


def draw_pistol():
    image = new_image(14, 9)
    metal = (70, 72, 80, 255)
    light = (120, 124, 135, 255)
    grip = (60, 40, 30, 255)
    rect(image, 2, 2, 12, 4, metal)  # slide and barrel
    rect(image, 3, 2, 11, 2, light)
    rect(image, 2, 5, 5, 7, grip)  # grip
    rect(image, 6, 5, 7, 5, metal)  # trigger guard
    add_outline(image)
    return image


def draw_weed_bag():
    image = new_image(12, 12)
    plastic = (215, 225, 220, 255)
    bud = (70, 140, 50, 255)
    bud_light = (120, 185, 70, 255)
    rect(image, 4, 1, 7, 2, plastic)  # knot
    rect(image, 2, 3, 9, 10, plastic)  # bag
    rect(image, 3, 5, 8, 9, bud)  # buds inside
    for x, y in ((4, 6), (6, 5), (7, 8), (4, 8)):
        image[y][x] = bud_light
    add_outline(image)
    return image


def draw_seed_packet():
    image = new_image(10, 12)
    paper = (200, 170, 120, 255)
    band = (150, 90, 50, 255)
    leaf = (60, 130, 45, 255)
    rect(image, 1, 1, 8, 10, paper)
    rect(image, 1, 1, 8, 2, band)  # folded top
    rect(image, 4, 4, 5, 8, leaf)  # stem and leaf
    rect(image, 2, 5, 7, 5, leaf)
    rect(image, 3, 4, 6, 4, leaf)
    add_outline(image)
    return image


def draw_burger():
    image = new_image(12, 10)
    bun = (205, 140, 60, 255)
    bun_light = (235, 180, 95, 255)
    lettuce = (90, 170, 60, 255)
    patty = (95, 55, 35, 255)
    cheese = (245, 200, 50, 255)
    rect(image, 2, 1, 9, 3, bun)  # top bun
    rect(image, 3, 1, 8, 1, bun_light)
    rect(image, 1, 4, 10, 4, lettuce)
    rect(image, 1, 5, 10, 5, cheese)
    rect(image, 1, 6, 10, 6, patty)
    rect(image, 2, 7, 9, 8, bun)  # bottom bun
    add_outline(image)
    return image


def draw_cocaine():
    image = new_image(10, 10)
    plastic = (215, 225, 230, 255)
    powder = (250, 250, 250, 255)
    shade = (200, 205, 210, 255)
    rect(image, 3, 1, 6, 2, plastic)  # twist at the top
    rect(image, 2, 3, 7, 8, plastic)
    rect(image, 3, 5, 6, 7, powder)
    image[7][3] = shade
    image[7][6] = shade
    add_outline(image)
    return image


def draw_grow_tray():
    image = new_image(16, 10)
    plastic = (60, 64, 70, 255)
    edge = (95, 100, 108, 255)
    water = (70, 120, 140, 255)
    leaf = (80, 170, 60, 255)
    rect(image, 1, 6, 12, 8, plastic)  # tray
    rect(image, 1, 6, 12, 6, edge)
    rect(image, 2, 7, 11, 7, water)
    rect(image, 13, 3, 14, 8, (200, 200, 190, 255))  # nutrient jug
    rect(image, 6, 3, 6, 5, leaf)  # sprout
    rect(image, 4, 2, 5, 3, leaf)
    rect(image, 7, 1, 8, 2, leaf)
    add_outline(image)
    return image


def draw_molotov():
    image = new_image(14, 7)
    glass = (70, 110, 60, 255)
    shine = (130, 170, 110, 255)
    liquid = (190, 140, 50, 255)
    rag = (220, 210, 185, 255)
    rect(image, 1, 1, 7, 5, glass)  # body
    rect(image, 2, 3, 7, 5, liquid)  # fuel inside
    rect(image, 2, 1, 6, 1, shine)
    rect(image, 8, 2, 9, 4, glass)  # neck
    rect(image, 10, 2, 11, 4, rag)  # rag stuffed in the neck
    image[1][12] = (255, 200, 60, 255)  # flame
    image[2][12] = (255, 140, 30, 255)
    image[3][12] = (255, 110, 20, 255)
    image[2][13] = (255, 220, 120, 255)
    add_outline(image)
    return image


def draw_tec9():
    image = new_image(20, 11)
    metal = (52, 54, 60, 255)
    light = (98, 102, 112, 255)
    dark = (30, 30, 34, 255)
    rect(image, 2, 2, 13, 4, metal)  # receiver
    rect(image, 3, 2, 12, 2, light)
    rect(image, 14, 2, 18, 4, metal)  # barrel shroud
    for x in (15, 17):
        image[3][x] = dark  # cooling holes
    rect(image, 2, 5, 4, 8, dark)  # grip
    rect(image, 5, 5, 6, 6, metal)  # trigger guard
    rect(image, 8, 5, 10, 9, metal)  # long magazine ahead of the grip
    rect(image, 8, 5, 8, 9, light)
    add_outline(image)
    return image


def draw_nightstick():
    image = new_image(20, 6)
    black = (35, 35, 40, 255)
    shine = (80, 80, 90, 255)
    rect(image, 1, 2, 17, 3, black)
    rect(image, 2, 2, 16, 2, shine)
    rect(image, 5, 1, 5, 4, black)  # side handle
    add_outline(image)
    return image


def draw_cash():
    image = new_image(14, 8)
    green = (90, 170, 90, 255)
    dark = (50, 115, 60, 255)
    rect(image, 1, 1, 12, 6, green)
    rect(image, 2, 2, 11, 5, dark)
    rect(image, 3, 2, 10, 5, green)
    rect(image, 6, 2, 7, 5, dark)  # the portrait in the middle
    add_outline(image)
    return image


def draw_pickup_arrow():
    image = new_image(11, 10)
    green = (90, 220, 90, 255)
    light = (170, 250, 160, 255)
    rect(image, 4, 1, 6, 4, green)  # stem
    for row, half_width in enumerate((4, 3, 2, 1, 0)):
        rect(image, 5 - half_width, 5 + row, 5 + half_width, 5 + row, green)  # head
    rect(image, 4, 1, 4, 4, light)
    add_outline(image)
    return image


def draw_blob(size):
    image = new_image(size, size)
    center = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            r = ((x - center) ** 2 + (y - center) ** 2) ** 0.5 / (size / 2)
            alpha = max(0.0, 1.0 - r * r) * 0.6
            image[y][x] = (0, 0, 0, int(alpha * 255))
    return image


if __name__ == "__main__":
    main()
