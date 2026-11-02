#!/usr/bin/env python3
"""Draws weft's icon alternatives as Icon Composer documents.

Each design is a set of flat layers — Icon Composer gives them depth, glass
and shadow — over a fill, with fills of their own for dark mode and for
tinted icons, so the system can draw every appearance:

    scripts/make-icons.py            # design/icons/<Name>.icon, one a design

The one chosen — Rapids — is also written where the apps take it from:
Resources/Icons/Weft.icon for the Mac (compiled by scripts/build-app.sh)
and iOS/Weft/AppIcon.icon for the iPhone and iPad.

A thread woven over and under is one layer in front of the cards, cut where
it goes under one, so the cut falls on the card's edge and no seam shows.
"""
import json
import os
import shutil
import sys

SIZE = 1024
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ROOT = os.path.join(BASE, "design", "icons")
CHOSEN = "Rapids"
INSTALLED = [os.path.join(BASE, "Resources", "Icons", "Weft.icon"), os.path.join(BASE, "iOS", "Weft", "AppIcon.icon")]


def srgb(hex_color):
    hex_color = hex_color.lstrip("#")
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">\n{body}\n</svg>\n')


def rect(x, y, w, h, r, color):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{color}"/>'


def rounded(x, y, w, h, r):
    """A rounded rectangle as a path, clockwise, for cutting holes."""
    return (f"M{x + r},{y} H{x + w - r} A{r},{r} 0 0 1 {x + w},{y + r} V{y + h - r} "
            f"A{r},{r} 0 0 1 {x + w - r},{y + h} H{x + r} A{r},{r} 0 0 1 {x},{y + h - r} "
            f"V{y + r} A{r},{r} 0 0 1 {x + r},{y} Z")


def card_with_holes(card, holes, color):
    """A card with lines cut out of it — the paper shows through, whatever its colour."""
    d = rounded(*card) + " " + " ".join(rounded(*hole) for hole in holes)
    return f'<path d="{d}" fill="{color}" fill-rule="evenodd"/>'


def polyline(points, width, color, cap="round"):
    d = "M" + " L".join(f"{x},{y}" for x, y in points)
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round"/>')


def write(name, background, layers):
    """`background`: (light top, light bottom, dark top, dark bottom).
    `layers`: front first — (file, svg body, tinted grey, dark colour or None)."""
    folder = os.path.join(ROOT, f"{name}.icon")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(os.path.join(folder, "Assets"))
    entries = []
    for file, body, tint, dark in layers:
        with open(os.path.join(folder, "Assets", file), "w") as handle:
            handle.write(svg(body))
        specializations = [{"appearance": "tinted", "value": {"solid": srgb(tint)}}]
        if dark:
            specializations.append({"appearance": "dark", "value": {"solid": srgb(dark)}})
        entries.append({"image-name": file, "name": os.path.splitext(file)[0], "fill-specializations": specializations})
    document = {
        "fill-specializations": [
            {"value": {"linear-gradient": [srgb(background[0]), srgb(background[1])]}},
            {"appearance": "dark", "value": {"linear-gradient": [srgb(background[2]), srgb(background[3])]}},
        ],
        "groups": [{
            "name": name,
            "layers": entries,
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"squares": "shared", "circles": ["watchOS"]},
    }
    with open(os.path.join(folder, "icon.json"), "w") as handle:
        json.dump(document, handle, indent=2)
    print(f"wrote {os.path.relpath(folder)}")
    if name == CHOSEN:
        for place in INSTALLED:
            shutil.rmtree(place, ignore_errors=True)
            shutil.copytree(folder, place)
            print(f"  and {os.path.relpath(place)}")


# MARK: Threads

def thread_piece(x0, x1, y, h, color, round_left, round_right):
    """A straight stretch of thread, its ends round where it ends and square
    where it goes under a card, so the cut falls on the card's edge."""
    r = h / 2
    left = f"M{x0 + r},{y} A{r},{r} 0 0 0 {x0 + r},{y + h}" if round_left else f"M{x0},{y} V{y + h}"
    if round_left:
        d = f"M{x0 + r},{y} H{x1 - (r if round_right else 0)} "
    else:
        d = f"M{x0},{y} H{x1 - (r if round_right else 0)} "
    d += f"A{r},{r} 0 0 1 {x1 - r},{y + h} " if round_right else f"V{y + h} "
    d += f"H{x0 + (r if round_left else 0)} "
    d += f"A{r},{r} 0 0 1 {x0 + r},{y} Z" if round_left else "Z"
    return f'<path d="{d}" fill="{color}"/>'


def woven(x0, x1, y, h, color, unders):
    """A thread across, in front of the cards but cut where it goes under
    one: `unders`, the cards' (x, width)."""
    pieces, start = [], x0
    for ux, uw in sorted(unders):
        pieces.append((start, ux))
        start = ux + uw
    pieces.append((start, x1))
    return "".join(thread_piece(a, b, y, h, color, a == x0, b == x1) for a, b in pieces)


def stroke_outline(points, width):
    """The outline of a polyline stroked `width` wide, mitred, its ends square."""
    import math
    half = width / 2
    def unit(dx, dy):
        length = math.hypot(dx, dy)
        return dx / length, dy / length
    left, right = [], []
    for i, (x, y) in enumerate(points):
        if i == 0:
            dx, dy = unit(points[1][0] - x, points[1][1] - y)
            nx, ny, scale = -dy, dx, 1
        elif i == len(points) - 1:
            dx, dy = unit(x - points[i - 1][0], y - points[i - 1][1])
            nx, ny, scale = -dy, dx, 1
        else:
            ax, ay = unit(x - points[i - 1][0], y - points[i - 1][1])
            bx, by = unit(points[i + 1][0] - x, points[i + 1][1] - y)
            nx, ny = unit(-ay - by, ax + bx)
            scale = 1 / max(0.2, nx * -ay + ny * ax)
        left.append((x + nx * half * scale, y + ny * half * scale))
        right.append((x - nx * half * scale, y - ny * half * scale))
    return left + right[::-1]


def clip(polygon, keep):
    """Sutherland–Hodgman: `polygon` clipped to the half-plane `keep` says,
    as (inside test, intersection with the edge)."""
    inside, cross = keep
    result = []
    for i, point in enumerate(polygon):
        prev = polygon[i - 1]
        if inside(point):
            if not inside(prev):
                result.append(cross(prev, point))
            result.append(point)
        elif inside(prev):
            result.append(cross(prev, point))
    return result


def slab(polygon, x0, x1):
    """The part of a polygon between two verticals."""
    def at(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))
    polygon = clip(polygon, (lambda p: p[0] >= x0, at(x0)))
    return clip(polygon, (lambda p: p[0] <= x1, at(x1))) if polygon else []


def shape(polygon, color):
    return f'<path d="M' + " L".join(f"{x:.1f},{y:.1f}" for x, y in polygon) + f' Z" fill="{color}"/>'


# MARK: The designs

def brackets():
    """TiddlyWiki's link, [[ ]], with a gold weft run through it: over the
    opening brackets, under the closing ones."""
    white, gold = "#ffffff", "#ffc44d"
    top, bottom, stroke, arm = 240, 784, 56, 60
    def bracket(x, facing):
        # A bracket's upright and its two arms, reaching in from it.
        x0 = x - stroke / 2 if facing > 0 else x - stroke / 2 - arm
        width = stroke + arm
        return (rect(x - stroke / 2, top, stroke, bottom - top, stroke / 2, white)
                + rect(x0, top, width, stroke, stroke / 2, white)
                + rect(x0, bottom - stroke, width, stroke, stroke / 2, white))
    uprights = [(270, 1), (378, 1), (646, -1), (754, -1)]
    marks = "".join(bracket(x, facing) for x, facing in uprights)
    thread = 36
    over = woven(176, 848, 512 - thread / 2, thread, gold, [(x - stroke / 2, stroke) for x, facing in uprights if facing < 0])
    write("Brackets", ("#6f8cff", "#3e4fd6", "#2b3270", "#121636"), [
        ("2-thread.svg", over, "#ffffff", None),
        ("1-brackets.svg", marks, "#a6a6a6", "#e9edff"),
    ])


def stack():
    """Tiddlers in a river: three cards, the front one with its title bar
    and lines of text."""
    front = (200, 404, 624, 408, 64)
    lines = [(264, 560, 496, 34, 17), (264, 634, 404, 34, 17), (264, 708, 452, 34, 17)]
    write("Stack", ("#f7f5f0", "#e4dfd3", "#2c2a27", "#141311"), [
        ("4-title.svg", rect(264, 468, 300, 50, 25, "#4d6bf0"), "#7a7a7a", "#7f97ff"),
        ("3-front.svg", card_with_holes(front, lines, "#ffffff"), "#f2f2f2", "#f4f2ec"),
        ("2-middle.svg", rect(248, 300, 528, 200, 56, "#a8b9ee"), "#bdbdbd", "#6d7fb8"),
        ("1-back.svg", rect(296, 210, 432, 200, 48, "#d3dcf5"), "#d8d8d8", "#47527a"),
    ])


def weave():
    """A basket weave: three cards for the warp, two threads for the weft,
    each over and under in turn."""
    warp = [(232, 140), (442, 140), (652, 140)]
    cards = "".join(rect(x, 216, w, 592, 54, "#ffffff") for x, w in warp)
    thread = 84
    blue = woven(176, 848, 404, thread, "#4d6bf0", [warp[1]])
    orange = woven(176, 848, 560, thread, "#f0a03c", [warp[0], warp[2]])
    write("Weave", ("#eef2ff", "#c9d5f6", "#1e2334", "#0c0f18"), [
        ("3-weft-2.svg", orange, "#e6e6e6", "#ffb85c"),
        ("2-weft-1.svg", blue, "#ffffff", "#7f97ff"),
        ("1-warp.svg", cards, "#8f8f8f", "#eef1f8"),
    ])


def thread():
    """A w drawn by one thread, behind the outer cards and in front of the
    middle one: a weft through three tiddlers."""
    bars = [(272, 120), (452, 120), (632, 120)]
    cards = "".join(rect(x, 236, w, 552, 48, "#ffffff") for x, w in bars)
    width, blue = 70, "#3f5ce8"
    w = [(182, 340), (332, 708), (512, 404), (692, 708), (842, 340)]
    outline = stroke_outline(w, width)
    # In front of the cards, cut away where the w goes behind the outer two.
    pieces = [slab(outline, 0, 272), slab(outline, 392, 632), slab(outline, 752, SIZE)]
    ends = "".join(f'<circle cx="{x}" cy="{y}" r="{width / 2}" fill="{blue}"/>' for x, y in (w[0], w[-1]))
    write("Thread", ("#f7f5f0", "#e2ddd1", "#2a2826", "#121110"), [
        ("2-thread.svg", "".join(shape(piece, blue) for piece in pieces if piece) + ends, "#ffffff", "#8da2ff"),
        ("1-cards.svg", cards, "#9a9a9a", "#e8e6e0"),
    ])


# MARK: Rivers — the warp waving

def river_bar(cx, width, top, bottom, sway):
    """A card waving as a river does: its middle swayed sideways by
    `sway(t)`, t from 0 at its top to 1 at its bottom, the card as wide
    throughout and its ends round. The outline, and its left and right
    edges, for cutting threads where they go under it."""
    import math
    n = 160
    half = width / 2
    # Its ends' middles a half-width in, so its round ends reach top and bottom.
    middle = [(cx + sway(i / n), top + half + (bottom - top - width) * i / n) for i in range(n + 1)]
    left, right = [], []
    for i, (x, y) in enumerate(middle):
        a, b = middle[max(0, i - 1)], middle[min(n, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length  # to the left, x growing rightwards
        left.append((x + nx * half, y + ny * half))
        right.append((x - nx * half, y - ny * half))
    def cap(centre, start, inward):
        # Half a circle from one edge to the other, round the end: the
        # way away from the card's middle, `inward` the next point in.
        (x, y), points = centre, []
        a0 = math.atan2(start[1] - y, start[0] - x)
        out = math.atan2(y - inward[1], x - inward[0])
        sweep = math.pi if math.sin(out - a0) > 0 else -math.pi
        for i in range(1, 24):
            angle = a0 + sweep * i / 24
            points.append((x + half * math.cos(angle), y + half * math.sin(angle)))
        return points
    outline = (right[::-1] + cap(middle[0], right[0], middle[1]) + left
               + cap(middle[-1], left[-1], middle[-2]))
    return outline, left, right


def edge_at(edge, y):
    """Where an edge is across at a height."""
    for (x0, y0), (x1, y1) in zip(edge, edge[1:]):
        if min(y0, y1) <= y <= max(y0, y1) and y0 != y1:
            return x0 + (x1 - x0) * (y - y0) / (y1 - y0)
    return edge[0][0]


def river_woven(x0, x1, y, h, color, unders):
    """A thread across, in front of the cards but cut where it goes under
    one — `unders`, the cards' (left edge, right edge) — so the cut follows
    the card's edge however it leans there."""
    import math
    r, steps = h / 2, 12
    ys = [y + h * i / steps for i in range(steps + 1)]
    def end(centre, first):
        # Half a circle round the thread's end, from angle `first` on.
        return [(centre + r * math.cos(first + math.pi * i / steps), y + r + r * math.sin(first + math.pi * i / steps))
                for i in range(steps + 1)]
    pieces, start = [], None
    for left, right in sorted(unders, key=lambda pair: edge_at(pair[0], y)):
        pieces.append((start, left))
        start = right
    pieces.append((start, None))
    body = ""
    for left, right in pieces:
        # Down the right side, then up the left: round at the thread's
        # ends, else along the edge of the card it goes under.
        down = end(x1 - r, -math.pi / 2) if right is None else [(edge_at(right, v), v) for v in ys]
        up = end(x0 + r, math.pi / 2) if left is None else [(edge_at(left, v), v) for v in ys[::-1]]
        body += shape(down + up, color)
    return body


def river(name, sways, width=128, background=("#eef2ff", "#c9d5f6", "#1e2334", "#0c0f18")):
    """Weave's basket, its warp waving like a river: `sways`, how each card
    sways, left to right."""
    top, bottom = 216, 808
    bars = [river_bar(cx, width, top, bottom, sway) for cx, sway in zip((302, 512, 722), sways)]
    cards = "".join(shape(outline, "#ffffff") for outline, _, _ in bars)
    thread = 84
    blue = river_woven(176, 848, 404, thread, "#4d6bf0", [bars[1][1:]])
    orange = river_woven(176, 848, 560, thread, "#f0a03c", [bars[0][1:], bars[2][1:]])
    write(name, background, [
        ("3-weft-2.svg", orange, "#e6e6e6", "#ffb85c"),
        ("2-weft-1.svg", blue, "#ffffff", "#7f97ff"),
        ("1-warp.svg", cards, "#8f8f8f", "#eef1f8"),
    ])


def wave(amplitude, waves=1.0, phase=0.0):
    import math
    return lambda t: amplitude * math.sin(2 * math.pi * (waves * t + phase))


def current():
    """The three cards waving together, one S each: lines of a current."""
    river("Current", [wave(30)] * 3)


def bend():
    """The three cards bowed together, as a river bends."""
    import math
    river("Bend", [lambda t: 46 * math.sin(math.pi * t) - 23] * 3)


def ripple():
    """Each card a little behind the one before it: a wave passing across."""
    river("Ripple", [wave(26, 1, -i / 8) for i in range(3)])


def rapids():
    """The cards waving faster, a wave and a half each."""
    river("Rapids", [wave(20, 1.5)] * 3)


def meander():
    """The cards swaying wide and slow, the middle one most: a meander."""
    river("Meander", [wave(28, 0.75, 0.125), wave(40, 0.75, 0.125), wave(28, 0.75, 0.125)], width=120)


if __name__ == "__main__":
    designs = {"Brackets": brackets, "Stack": stack, "Weave": weave, "Thread": thread,
               "Current": current, "Bend": bend, "Ripple": ripple, "Rapids": rapids, "Meander": meander}
    for name in sys.argv[1:] or designs:
        designs[name]()
