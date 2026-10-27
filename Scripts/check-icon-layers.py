#!/usr/bin/env python3
"""Checks that Resources/Logo/icon-layers/*.svg are the logo, split for Icon Composer.

Icon Composer wants numbered layers (back to front, at most four), 1024 by 1024, without the
canvas mask and without transparency, clip paths, masks, filters, gradients or text. The logo
(Resources/Logo/holzBar.svg) has semi-transparent colours and one clip path, so the layers carry
the solid colours those produce. This script recomputes them from the logo and proves that every
shape of the logo (except the tile, the clip path and the highlight, which is rebuilt as a path)
appears exactly once, with identical geometry and the expected colour, and that the layers hold
no shape the logo does not have.

Standard library only. Exit status 1 and one `error:` line per problem; on success it prints
`==> the icon layers match the logo`.
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Resources" / "Logo" / "holzBar.svg"
LAYER_DIR = ROOT / "Resources" / "Logo" / "icon-layers"
LAYER_NAMES = ["01-plank.svg", "02-bar.svg", "03-sparkle.svg"]
VIEW_BOX = "0 0 1024 1024"

SHAPES = {"rect", "circle", "ellipse", "path"}
GEOMETRY = ["x", "y", "width", "height", "rx", "cx", "cy", "r", "ry", "d"]
PAINT_DEFAULT = {"fill": "#000000", "stroke": "none"}
FORBIDDEN_TAGS = {
    "clippath", "mask", "filter", "lineargradient", "radialgradient", "pattern", "text", "tspan",
    "style", "image", "use", "script", "foreignobject",
}
FORBIDDEN_ATTRS = {
    "opacity", "fill-opacity", "stroke-opacity", "clip-path", "mask", "filter", "style",
    "mix-blend-mode", "stop-opacity",
}
COLOUR = re.compile(r"^#[0-9A-F]{6}$")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")

errors: list[str] = []


def error(message: str) -> None:
    errors.append(f"error: {message}")


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].lower()


def parse(path: Path):
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, OSError) as exc:
        error(f"{path.name}: cannot be parsed ({exc})")
        return None


def walk(element, inherited=None):
    """Yields (element, effective paint) for every element, resolving fill and stroke inheritance."""
    paint = dict(inherited or PAINT_DEFAULT)
    for key in ("fill", "stroke"):
        if key in element.attrib:
            value = element.attrib[key].strip()
            paint[key] = "none" if value.lower() == "none" else value.upper()
    yield element, paint
    for child in element:
        yield from walk(child, paint)


def blend(top: str, alpha: float, under: str) -> str:
    channels = []
    for i in (1, 3, 5):
        t, u = int(top[i:i + 2], 16), int(under[i:i + 2], 16)
        channels.append(round(t * alpha + u * (1 - alpha)))
    return "#" + "".join(f"{c:02X}" for c in channels)


def number(value, default=0.0) -> float:
    return float(value) if value is not None else default


def anchor(element):
    """A point that lies inside what the element draws over."""
    tag = local(element.tag)
    if tag == "rect":
        return (number(element.get("x")) + number(element.get("width")) / 2,
                number(element.get("y")) + number(element.get("height")) / 2)
    if tag in ("circle", "ellipse"):
        return number(element.get("cx")), number(element.get("cy"))
    numbers = NUMBER.findall(element.get("d", ""))
    return float(numbers[0]), float(numbers[1])


def is_tile(element) -> bool:
    return (local(element.tag) == "rect" and element.get("x") == "100" and element.get("y") == "100"
            and element.get("width") == "824")


def key_of(element):
    return (local(element.tag),) + tuple(element.get(name) for name in GEOMETRY)


def logo_shapes(root):
    """Maps the geometry key of every logo shape to its expected (fill, stroke), and returns the
    palette the logo uses plus the baked colours."""
    expected = {}
    palette: set[str] = set()
    drawn = []  # earlier rectangles with a solid fill: (x, y, w, h, fill)
    baked: set[str] = set()
    for element, paint in walk(root):
        tag = local(element.tag)
        if tag not in SHAPES or is_tile(element):
            continue
        if any(local(parent.tag) == "clippath" for parent in root.iter() if element in list(parent)):
            continue
        highlight = element.get("clip-path") is not None
        alpha = float(element.get("opacity", "1"))
        fill, stroke = paint["fill"], paint["stroke"]
        for colour in (fill, stroke):
            if colour != "none":
                palette.add(colour)
        if alpha < 1:
            ax, ay = anchor(element)
            under = None
            for x, y, w, h, colour in drawn:
                if x <= ax <= x + w and y <= ay <= y + h:
                    under = colour
            if under is None:
                error(f"holzBar.svg: no colour found under a shape with opacity {alpha}")
                continue
            if fill != "none":
                fill = blend(fill, alpha, under)
                baked.add(fill)
            if stroke != "none":
                stroke = blend(stroke, alpha, under)
                baked.add(stroke)
        if highlight:
            expected["highlight"] = (fill, stroke)
        else:
            expected[key_of(element)] = (fill, stroke)
        if tag == "rect" and paint["fill"] != "none":
            drawn.append((number(element.get("x")), number(element.get("y")),
                          number(element.get("width")), number(element.get("height")), paint["fill"]))
    return expected, palette | baked


def path_points(d: str):
    """End points of an absolute path made of M, H, V, L, A, C and Z commands."""
    tokens = re.findall(r"[MHVLACZ]|-?\d+(?:\.\d+)?", d)
    points, i, x, y = [], 0, 0.0, 0.0
    counts = {"M": 2, "L": 2, "H": 1, "V": 1, "A": 7, "C": 6, "Z": 0}
    while i < len(tokens):
        command = tokens[i]
        if command not in counts:
            raise ValueError(f"unsupported path data near {command!r}")
        args = [float(t) for t in tokens[i + 1:i + 1 + counts[command]]]
        i += 1 + counts[command]
        if command in ("M", "L"):
            x, y = args
        elif command == "H":
            x = args[0]
        elif command == "V":
            y = args[0]
        elif command in ("A", "C"):
            x, y = args[-2], args[-1]
        if command != "Z":
            points.append((x, y))
    return points


def main() -> int:
    logo = parse(LOGO)
    if logo is None:
        print("\n".join(errors))
        return 1

    expected, allowed = logo_shapes(logo)
    plank = next((e for e, _ in walk(logo) if local(e.tag) == "rect" and e.get("fill") == "#C98B4F"), None)

    files = sorted(p.name for p in LAYER_DIR.glob("*.svg"))
    if files != LAYER_NAMES:
        error(f"icon-layers must hold exactly {', '.join(LAYER_NAMES)}; found {', '.join(files) or 'none'}")

    found: dict = {}
    for name in LAYER_NAMES:
        path = LAYER_DIR / name
        if not path.exists():
            continue
        root = parse(path)
        if root is None:
            continue
        if root.get("viewBox") != VIEW_BOX or root.get("width") != "1024" or root.get("height") != "1024":
            error(f"{name}: the canvas must be viewBox '{VIEW_BOX}', width 1024, height 1024")
        for element, paint in walk(root):
            tag = local(element.tag)
            if tag in FORBIDDEN_TAGS:
                error(f"{name}: <{tag}> is not allowed in a layer")
            for attribute in element.attrib:
                if attribute.lower() in FORBIDDEN_ATTRS:
                    error(f"{name}: attribute {attribute} is not allowed in a layer")
            for attribute in ("fill", "stroke"):
                value = element.get(attribute)
                if value is not None and value != "none" and not COLOUR.match(value.upper()):
                    error(f"{name}: {attribute}={value} is not a solid #RRGGBB colour")
            if tag not in SHAPES:
                continue
            if is_tile(element):
                error(f"{name}: the tile belongs to the canvas and is not exported")
                continue
            for colour in (paint["fill"], paint["stroke"]):
                if colour != "none" and colour not in allowed:
                    error(f"{name}: colour {colour} is neither in the logo nor a baked blend of it")
            key = key_of(element)
            if key in expected:
                found.setdefault(key, []).append((name, paint["fill"], paint["stroke"]))
            elif tag == "path" and plank is not None and "highlight" in expected:
                # The rebuilt highlight: a path that stays inside the plank.
                bounds = (number(plank.get("x")), number(plank.get("y")),
                          number(plank.get("x")) + number(plank.get("width")),
                          number(plank.get("y")) + number(plank.get("height")))
                try:
                    inside = all(bounds[0] <= px <= bounds[2] and bounds[1] <= py <= bounds[3]
                                 for px, py in path_points(element.get("d", "")))
                except ValueError as exc:
                    error(f"{name}: {exc}")
                    continue
                if not inside:
                    error(f"{name}: a path outside the plank is not a shape of the logo")
                found.setdefault("highlight", []).append((name, paint["fill"], paint["stroke"]))
            else:
                error(f"{name}: a <{tag}> that the logo does not have")

    for key, (fill, stroke) in expected.items():
        label = "the highlight" if key == "highlight" else f"{key[0]} {({n: v for n, v in zip(GEOMETRY, key[1:]) if v is not None})}"
        places = found.get(key, [])
        if not places:
            error(f"{label} of the logo is missing from the layers")
        elif len(places) > 1:
            error(f"{label} appears in more than one layer or more than once")
        else:
            name, got_fill, got_stroke = places[0]
            if (got_fill, got_stroke) != (fill, stroke):
                error(f"{name}: {label} has fill {got_fill} and stroke {got_stroke}, expected {fill} and {stroke}")

    if errors:
        print("\n".join(errors))
        return 1
    print("==> the icon layers match the logo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
