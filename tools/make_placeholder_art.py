"""Generates placeholder sprite sheets so movement and aiming can be tested
before real art exists. Run from the project root: python3 tools/make_placeholder_art.py

player_8dir.png: 4 columns x 8 rows of 32x32 frames.
  Rows (facing, clockwise from "toward the camera"): s, se, e, ne, n, nw, w, sw
  Columns: 0 = idle, 1-3 = walk cycle
dummy_8dir.png: same layout as the player sheet, without the facing arrow.
shadow_blob.png: soft round shadow projected under the player.
baseball_bat.png: 24x8 bat pointing right, grip at the left edge.
pickup_arrow.png: 11x10 green arrow pointing down, shown above pickups.
fist.png: 10x9 fist punching right, wrist at the left edge.
brass_knuckles.png: the fist with a brass band across the knuckles.
knife.png: 20x6 knife pointing right, handle at the left edge.
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
DUMMY = {
    "jacket": (180, 150, 220, 255),
    "stripe": (230, 230, 230, 255),
    "pants": (90, 90, 100, 255),
    "shoes": (40, 40, 40, 255),
    "skin": (200, 160, 130, 255),
    "hair": (60, 40, 30, 255),
}


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
        if dy > 0 or dx == 0:
            rect(frame, 14 + eye_shift, 9 - bob, 14 + eye_shift, 10 - bob, OUTLINE)
        rect(frame, 17 + eye_shift, 9 - bob, 17 + eye_shift, 10 - bob, OUTLINE)

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
    write_png(art / "shadow_blob.png", draw_blob(32))
    write_png(art / "baseball_bat.png", draw_bat())
    write_png(art / "pickup_arrow.png", draw_pickup_arrow())
    write_png(art / "fist.png", draw_fist())
    write_png(art / "brass_knuckles.png", draw_fist(brass=True))
    write_png(art / "knife.png", draw_knife())


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
