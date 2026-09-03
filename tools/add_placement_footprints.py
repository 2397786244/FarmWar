#!/usr/bin/env python3
"""Add authored placement-only BoxShape3D footprints to map buildings/facilities.

The script intentionally derives footprints only from an existing physics
CollisionShape3D. Scenes without one are reported and left untouched.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TARGET_ROOTS = (PROJECT_ROOT / "buildings", PROJECT_ROOT / "facilities")
DEFENSE_SCENES = (
    PROJECT_ROOT / "character/weapons/TallBrick.tscn",
    PROJECT_ROOT / "character/weapons/TallLogWall.tscn",
    PROJECT_ROOT / "character/weapons/TallMeshWall.tscn",
    PROJECT_ROOT / "character/weapons/WireMeshGate.tscn",
    PROJECT_ROOT / "character/weapons/ChainLinkFence.tscn",
)
# These scenes only expose trigger/Area collision; neither is an entity
# collider for the scene itself.
ENTITY_COLLISION_SKIPS = {
    PROJECT_ROOT / "buildings/auxiliary/MessageArea.tscn",
    PROJECT_ROOT / "buildings/auxiliary/NeutralCropGenerator.tscn",
}
NUMBER = r"[-+0-9.eE]+"


@dataclass
class Footprint:
    center: tuple[float, float, float]
    size: tuple[float, float, float]


def _numbers(value: str) -> list[float]:
    return [float(item) for item in re.findall(NUMBER, value)]


def _vector(value: str) -> tuple[float, float, float] | None:
    values = _numbers(value)
    return tuple(values[:3]) if len(values) >= 3 else None


def _format(value: float) -> str:
    return ("%.5f" % value).rstrip("0").rstrip(".") or "0"


def _blocks(text: str, kind: str) -> dict[str, tuple[str, str]]:
    pattern = re.compile(
        rf'^\[{kind} type="([^"]+)" id="([^"]+)"\]\n(.*?)(?=^\[|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    return {match.group(2): (match.group(1), match.group(3)) for match in pattern.finditer(text)}


def _node_blocks(text: str) -> list[tuple[str, str, str]]:
    pattern = re.compile(
        r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?[^\]]*\]\n(.*?)(?=^\[|\Z)',
        re.MULTILINE | re.DOTALL,
    )
    return [(match.group(1), match.group(2), match.group(3) or "", match.group(4)) for match in pattern.finditer(text)]


def _transform(block: str) -> tuple[tuple[float, ...], tuple[float, float, float]]:
    match = re.search(r"^transform = Transform3D\(([^)]*)\)", block, re.MULTILINE)
    if match is None:
        return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0)
    values = _numbers(match.group(1))
    if len(values) != 12:
        return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0)
    return tuple(values[:9]), tuple(values[9:12])


def _shape_bounds(shape_type: str, block: str) -> tuple[tuple[float, float, float], tuple[float, float, float]] | None:
    if shape_type == "BoxShape3D":
        match = re.search(r"^size = Vector3\(([^)]*)\)", block, re.MULTILINE)
        return (0.0, 0.0, 0.0), (_vector(match.group(1)) if match else (1.0, 1.0, 1.0))
    if shape_type == "SphereShape3D":
        match = re.search(r"^radius = (.+)$", block, re.MULTILINE)
        radius = float(match.group(1)) if match else 0.5
        return (0.0, 0.0, 0.0), (radius * 2.0, radius * 2.0, radius * 2.0)
    if shape_type in {"CylinderShape3D", "CapsuleShape3D"}:
        radius_match = re.search(r"^radius = (.+)$", block, re.MULTILINE)
        height_match = re.search(r"^height = (.+)$", block, re.MULTILINE)
        radius = float(radius_match.group(1)) if radius_match else 0.5
        height = float(height_match.group(1)) if height_match else 1.0
        return (0.0, 0.0, 0.0), (radius * 2.0, height, radius * 2.0)
    if shape_type in {"ConcavePolygonShape3D", "ConvexPolygonShape3D"}:
        match = re.search(r"(?:data|points) = PackedVector3Array\(([^)]*)\)", block, re.MULTILINE)
        if match is None:
            return None
        values = _numbers(match.group(1))
        if len(values) < 3:
            return None
        points = list(zip(values[0::3], values[1::3], values[2::3]))
        minimum = [min(point[index] for point in points) for index in range(3)]
        maximum = [max(point[index] for point in points) for index in range(3)]
        center = tuple((minimum[index] + maximum[index]) * 0.5 for index in range(3))
        size = tuple(maximum[index] - minimum[index] for index in range(3))
        return center, size
    return None


def _footprint_from_text(text: str) -> Footprint | str:
    resources = _blocks(text, "sub_resource")
    candidates = _node_blocks(text)
    # A root shape belongs to the scene's entity collider. Union all of those
    # shapes so compound buildings get one truthful ground footprint. A nested
    # shape is used only when no direct root collider exists.
    direct = [node for node in candidates if node[1] == "CollisionShape3D" and node[2] == "."]
    ordered = direct if direct else [node for node in candidates if node[1] == "CollisionShape3D"]
    minimum: list[float] | None = None
    maximum: list[float] | None = None
    for _, _, _, block in ordered:
        shape_match = re.search(r'^shape = SubResource\("([^"]+)"\)', block, re.MULTILINE)
        if shape_match is None:
            continue
        resource = resources.get(shape_match.group(1))
        if resource is None:
            continue
        shape_type, shape_block = resource
        shape_bounds = _shape_bounds(shape_type, shape_block)
        if shape_bounds is None:
            continue
        local_center, size = shape_bounds
        if min(size) <= 0.0:
            continue
        basis, center = _transform(block)
        center = (
            center[0] + basis[0] * local_center[0] + basis[3] * local_center[1] + basis[6] * local_center[2],
            center[1] + basis[1] * local_center[0] + basis[4] * local_center[1] + basis[7] * local_center[2],
            center[2] + basis[2] * local_center[0] + basis[5] * local_center[1] + basis[8] * local_center[2],
        )
        half = [value * 0.5 for value in size]
        extent = (
            abs(basis[0]) * half[0] + abs(basis[3]) * half[1] + abs(basis[6]) * half[2],
            abs(basis[1]) * half[0] + abs(basis[4]) * half[1] + abs(basis[7]) * half[2],
            abs(basis[2]) * half[0] + abs(basis[5]) * half[1] + abs(basis[8]) * half[2],
        )
        shape_minimum = [center[index] - extent[index] for index in range(3)]
        shape_maximum = [center[index] + extent[index] for index in range(3)]
        if minimum is None:
            minimum, maximum = shape_minimum, shape_maximum
        else:
            minimum = [min(minimum[index], shape_minimum[index]) for index in range(3)]
            maximum = [max(maximum[index], shape_maximum[index]) for index in range(3)]
    if minimum is not None and maximum is not None:
        return Footprint(
            tuple((minimum[index] + maximum[index]) * 0.5 for index in range(3)),
            tuple(maximum[index] - minimum[index] for index in range(3)),
        )
    return "no supported entity CollisionShape3D"


def _targets() -> list[Path]:
    result: list[Path] = []
    for root in TARGET_ROOTS:
        for path in root.rglob("*.tscn"):
            if root.name == "buildings" and "nature" in path.parts:
                continue
            if root.name == "buildings" and "GroundDecorations" in path.parts:
                continue
            result.append(path)
    result.extend(path for path in DEFENSE_SCENES if path.exists())
    return sorted(set(result))


def _append_footprint(text: str, footprint: Footprint) -> str:
    resource_id = "BoxShape3D_placement_footprint"
    resource = f'''[sub_resource type="BoxShape3D" id="{resource_id}"]\nsize = Vector3({_format(footprint.size[0])}, {_format(footprint.size[1])}, {_format(footprint.size[2])})\n\n'''
    nodes = f'''\n[node name="PlacementFootprint" type="StaticBody3D" parent="."]\ncollision_layer = 16\ncollision_mask = 0\n\n[node name="CollisionShape3D" type="CollisionShape3D" parent="PlacementFootprint"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {_format(footprint.center[0])}, {_format(footprint.center[1])}, {_format(footprint.center[2])})\nshape = SubResource("{resource_id}")\n'''
    first_node = text.find("[node ")
    if first_node < 0:
        raise ValueError("scene has no nodes")
    return text[:first_node] + resource + text[first_node:].rstrip() + "\n" + nodes


def _remove_generated_footprint(text: str) -> str:
    resource = r'\n?\[sub_resource type="BoxShape3D" id="BoxShape3D_placement_footprint"\]\nsize = Vector3\([^\n]+\)\n'
    nodes = r'\n?\[node name="PlacementFootprint" type="StaticBody3D" parent="\."\][\s\S]*?\[node name="CollisionShape3D" type="CollisionShape3D" parent="PlacementFootprint"\][\s\S]*?shape = SubResource\("BoxShape3D_placement_footprint"\)\n?'
    return re.sub(nodes, "", re.sub(resource, "", text))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    added: list[str] = []
    skipped: list[str] = []
    existing: list[str] = []
    for path in _targets():
        text = path.read_text(encoding="utf-8")
        base_text = _remove_generated_footprint(text)
        relative = str(path.relative_to(PROJECT_ROOT))
        if path in ENTITY_COLLISION_SKIPS:
            skipped.append(f"{relative}: no entity CollisionShape3D")
            if args.apply:
                path.write_text(base_text, encoding="utf-8")
            continue
        if '[node name="PlacementFootprint"' in base_text:
            existing.append(str(path.relative_to(PROJECT_ROOT)))
            continue
        result = _footprint_from_text(base_text)
        if isinstance(result, str):
            skipped.append(f"{relative}: {result}")
            continue
        added.append("%s: center=%s size=%s" % (relative, result.center, result.size))
        if args.apply:
            path.write_text(_append_footprint(base_text, result), encoding="utf-8")
    print("placement footprints: added=%d existing=%d skipped=%d" % (len(added), len(existing), len(skipped)))
    for line in skipped:
        print("SKIP", line)
    if not args.apply:
        for line in added:
            print("PLAN", line)


if __name__ == "__main__":
    main()
