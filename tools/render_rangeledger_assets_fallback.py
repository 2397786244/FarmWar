"""Small dependency-free GLB orthographic renderer used when Blender is unavailable.

The normal production path is ``render_rangeledger_assets.py`` in Blender.  This
fallback deliberately reads the same GLB files and produces the same transparent
square assets so a headless macOS session without a working Metal backend can
still validate the browser page.
"""

import argparse
import json
import math
import struct
import zlib
from pathlib import Path


JOBS = [
    ("mpx", "assets/tools/FTF_Weapon_MPX_Compact_IronSights.glb"),
    ("m4", "assets/tools/M4.glb"),
    ("ar15", "assets/tools/AR15.glb"),
    ("shotgun", "assets/tools/Shotgun.glb"),
    ("hunting_rifle", "assets/tools/HuntingRifle.glb"),
    ("crossbow", "assets/tools/Crossbow.glb"),
    ("suppressed_pistol", "assets/tools/SuppressedPistol.glb"),
    ("future_m4", "assets/tools/FutureM4.glb"),
    ("future_mpx", "assets/tools/FTF_Weapon_FutureMPX_BlackGreen.glb"),
    ("grenade", "assets/tools/Grenade.glb"),
    ("ammo_supply_box", "assets/other_items/weapons/AmmoSupplyBox.glb"),
]

COMPONENTS = {
    5120: ("b", 1, True),
    5121: ("B", 1, False),
    5122: ("h", 2, True),
    5123: ("H", 2, False),
    5125: ("I", 4, False),
    5126: ("f", 4, False),
}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def parse_args():
    parser = argparse.ArgumentParser(description="Render Range Ledger GLBs without external Python packages.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", default="assets/icons/rangeledger")
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--only", default="")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def unpack_glb(path):
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"not a GLB file: {path}")
    json_length = struct.unpack_from("<I", data, 12)[0]
    json_start = 20
    json_chunk = data[json_start : json_start + json_length]
    json_value = json.loads(json_chunk.rstrip(b" \t\r\n\0").decode("utf-8"))
    bin_header = json_start + json_length
    bin_length = struct.unpack_from("<I", data, bin_header)[0]
    bin_start = bin_header + 8
    return json_value, data[bin_start : bin_start + bin_length]


def decode_accessor(gltf, binary, accessor_index):
    accessor = gltf["accessors"][accessor_index]
    component_format, component_size, signed = COMPONENTS[accessor["componentType"]]
    component_count = TYPE_COUNTS[accessor["type"]]
    view = gltf["bufferViews"][accessor["bufferView"]]
    base_offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", component_size * component_count)
    count = accessor["count"]
    fmt = "<" + component_format * component_count
    raw_values = []
    for index in range(count):
        offset = base_offset + index * stride
        values = list(struct.unpack_from(fmt, binary, offset))
        if accessor.get("normalized", False):
            normalized = []
            for value in values:
                if signed:
                    normalized.append(max(-1.0, value / ((1 << (component_size * 8 - 1)) - 1)))
                else:
                    normalized.append(value / ((1 << (component_size * 8)) - 1))
            values = normalized
        raw_values.append(values[0] if component_count == 1 else tuple(values))
    return raw_values


def identity():
    return (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)


def matrix_multiply(a, b):
    return tuple(
        sum(a[row * 4 + k] * b[k * 4 + col] for k in range(4))
        for row in range(4)
        for col in range(4)
    )


def matrix_from_gltf(values):
    # glTF stores matrices column-major; the renderer uses row-major tuples.
    return tuple(values[col * 4 + row] for row in range(4) for col in range(4))


def quaternion_matrix(q):
    x, y, z, w = q
    return (
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0.0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0.0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
    )


def local_matrix(node):
    if "matrix" in node:
        return matrix_from_gltf(node["matrix"])
    translation = node.get("translation", [0.0, 0.0, 0.0])
    rotation = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    scale = node.get("scale", [1.0, 1.0, 1.0])
    t = (1.0, 0.0, 0.0, translation[0], 0.0, 1.0, 0.0, translation[1], 0.0, 0.0, 1.0, translation[2], 0.0, 0.0, 0.0, 1.0)
    s = (scale[0], 0.0, 0.0, 0.0, 0.0, scale[1], 0.0, 0.0, 0.0, 0.0, scale[2], 0.0, 0.0, 0.0, 0.0, 1.0)
    return matrix_multiply(matrix_multiply(t, quaternion_matrix(rotation)), s)


def transform_point(matrix, point):
    x, y, z = point
    return (
        matrix[0] * x + matrix[1] * y + matrix[2] * z + matrix[3],
        matrix[4] * x + matrix[5] * y + matrix[6] * z + matrix[7],
        matrix[8] * x + matrix[9] * y + matrix[10] * z + matrix[11],
    )


def transform_direction(matrix, direction):
    x, y, z = direction
    return (
        matrix[0] * x + matrix[1] * y + matrix[2] * z,
        matrix[4] * x + matrix[5] * y + matrix[6] * z,
        matrix[8] * x + matrix[9] * y + matrix[10] * z,
    )


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(value, amount):
    return (value[0] * amount, value[1] * amount, value[2] * amount)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(value):
    return math.sqrt(dot(value, value))


def normalize(value):
    size = length(value)
    return scale(value, 1.0 / size) if size > 1e-8 else (0.0, 0.0, 1.0)


def load_triangles(path):
    gltf, binary = unpack_glb(path)
    accessor_cache = {}

    def accessor(index):
        if index not in accessor_cache:
            accessor_cache[index] = decode_accessor(gltf, binary, index)
        return accessor_cache[index]

    triangles = []
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    materials = gltf.get("materials", [])
    children_by_node = {index: node.get("children", []) for index, node in enumerate(nodes)}

    def visit(node_index, parent_matrix):
        node = nodes[node_index]
        world_matrix = matrix_multiply(parent_matrix, local_matrix(node))
        if "mesh" in node:
            mesh = meshes[node["mesh"]]
            for primitive in mesh.get("primitives", []):
                attributes = primitive.get("attributes", {})
                if "POSITION" not in attributes:
                    continue
                positions = accessor(attributes["POSITION"])
                normals = accessor(attributes["NORMAL"]) if "NORMAL" in attributes else None
                indices = accessor(primitive["indices"]) if "indices" in primitive else list(range(len(positions)))
                material_index = primitive.get("material", -1)
                material = materials[material_index] if 0 <= material_index < len(materials) else {}
                pbr = material.get("pbrMetallicRoughness", {})
                color = tuple(pbr.get("baseColorFactor", [0.7, 0.7, 0.7, 1.0]))
                emission = tuple(material.get("emissiveFactor", [0.0, 0.0, 0.0]))
                if len(indices) < 3:
                    continue
                for index in range(0, len(indices) - 2, 3):
                    point_indices = [int(indices[index]), int(indices[index + 1]), int(indices[index + 2])]
                    points = [transform_point(world_matrix, positions[value]) for value in point_indices]
                    face_normal = normalize(cross(sub(points[1], points[0]), sub(points[2], points[0])))
                    if normals is None:
                        point_normals = [face_normal, face_normal, face_normal]
                    else:
                        point_normals = [normalize(transform_direction(world_matrix, normals[value])) for value in point_indices]
                    triangles.append((points, point_normals, color, emission))
        for child in children_by_node.get(node_index, []):
            visit(child, world_matrix)

    roots = gltf.get("scenes", [{}])[gltf.get("scene", 0)].get("nodes", []) if gltf.get("scenes") else []
    for root in roots:
        visit(root, identity())
    return triangles


def project_points(triangles, size):
    all_points = [point for triangle in triangles for point in triangle[0]]
    minimum = tuple(min(point[index] for point in all_points) for index in range(3))
    maximum = tuple(max(point[index] for point in all_points) for index in range(3))
    target = scale(add(minimum, maximum), 0.5)
    camera_offset = normalize((1.7, -2.3, 1.15))
    view_direction = scale(camera_offset, -1.0)
    # These assets are equipment reference cards, so the long axis of a
    # firearm should read left-to-right.  Project world Z onto the view plane
    # and use it as the screen-right axis, then derive screen-up from it.
    world_length_axis = (0.0, 0.0, 1.0)
    right = normalize(sub(world_length_axis, scale(view_direction, dot(world_length_axis, view_direction))))
    up = normalize(cross(right, view_direction))
    camera = add(target, scale(camera_offset, max(length(sub(maximum, minimum)), 1.0) * 4.0))
    projected = []
    min_x = float("inf")
    max_x = float("-inf")
    min_y = float("inf")
    max_y = float("-inf")
    for points, normals, color, emission in triangles:
        values = []
        for point, normal in zip(points, normals):
            values.append((dot(sub(point, target), right), dot(sub(point, target), up), dot(sub(point, camera), view_direction), normal, color, emission))
            min_x = min(min_x, values[-1][0])
            max_x = max(max_x, values[-1][0])
            min_y = min(min_y, values[-1][1])
            max_y = max(max_y, values[-1][1])
        projected.append(values)
    span = max(max_x - min_x, max_y - min_y, 0.001) * 1.20
    pixels = []
    for triangle in projected:
        values = []
        for x, y, depth, normal, color, emission in triangle:
            values.append(((x / span + 0.5) * (size - 1), (0.5 - y / span) * (size - 1), depth, normal, color, emission))
        pixels.append(values)
    return pixels, right, up, view_direction


def shade(normal, color, emission, view_direction):
    normal = normalize(normal)
    light_directions = [normalize((-0.55, -0.70, 0.90)), normalize((0.80, -0.30, 0.45)), normalize((0.10, 0.75, 0.60))]
    weights = [0.72, 0.30, 0.18]
    intensity = 0.25
    for light_direction, weight in zip(light_directions, weights):
        intensity += max(0.0, dot(normal, light_direction)) * weight
    emission_strength = min(1.0, length(emission) * 1.5)
    intensity = min(1.45, intensity + emission_strength * 0.75)
    # A modest cool rim helps dark weapons remain readable on a transparent page card.
    rim = max(0.0, 1.0 - max(0.0, dot(normal, scale(view_direction, -1.0)))) * 0.10
    return tuple(max(0, min(255, int((channel * intensity + rim) * 255.0))) for channel in color[:3])


def rasterize(triangles, size):
    high_size = size * 2
    projected, _right, _up, view_direction = project_points(triangles, high_size)
    pixels = bytearray(high_size * high_size * 4)
    zbuffer = [float("inf")] * (high_size * high_size)
    for triangle in projected:
        (x0, y0, z0, n0, color, emission), (x1, y1, z1, n1, _color1, _emission1), (x2, y2, z2, n2, _color2, _emission2) = triangle
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denominator) < 1e-8:
            continue
        left = max(0, int(math.floor(min(x0, x1, x2))))
        right = min(high_size - 1, int(math.ceil(max(x0, x1, x2))))
        top = max(0, int(math.floor(min(y0, y1, y2))))
        bottom = min(high_size - 1, int(math.ceil(max(y0, y1, y2))))
        for py in range(top, bottom + 1):
            sample_y = py + 0.5
            for px in range(left, right + 1):
                sample_x = px + 0.5
                w0 = ((y1 - y2) * (sample_x - x2) + (x2 - x1) * (sample_y - y2)) / denominator
                w1 = ((y2 - y0) * (sample_x - x2) + (x0 - x2) * (sample_y - y2)) / denominator
                w2 = 1.0 - w0 - w1
                if w0 < -1e-5 or w1 < -1e-5 or w2 < -1e-5:
                    continue
                index = py * high_size + px
                depth = w0 * z0 + w1 * z1 + w2 * z2
                if depth >= zbuffer[index]:
                    continue
                zbuffer[index] = depth
                normal = normalize(add(add(scale(n0, w0), scale(n1, w1)), scale(n2, w2)))
                rgb = shade(normal, color, emission, view_direction)
                offset = index * 4
                pixels[offset : offset + 4] = bytes((rgb[0], rgb[1], rgb[2], 255))
    return downsample(pixels, high_size, size)


def downsample(source, source_size, target_size):
    output = bytearray(target_size * target_size * 4)
    for y in range(target_size):
        for x in range(target_size):
            samples = []
            for sy in range(y * 2, y * 2 + 2):
                for sx in range(x * 2, x * 2 + 2):
                    offset = (sy * source_size + sx) * 4
                    samples.append(tuple(source[offset + channel] for channel in range(4)))
            alpha = sum(sample[3] for sample in samples) / 4.0
            if alpha <= 0.0:
                rgba = (0, 0, 0, 0)
            else:
                rgba = tuple(int(sum(sample[channel] * sample[3] for sample in samples) / max(sum(sample[3] for sample in samples), 1.0)) for channel in range(3)) + (int(alpha),)
            offset = (y * target_size + x) * 4
            output[offset : offset + 4] = bytes(rgba)
    return bytes(output)


def png_chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def write_png(path, rgba, size):
    rows = b"".join(b"\x00" + rgba[y * size * 4 : (y + 1) * size * 4] for y in range(size))
    png = b"\x89PNG\r\n\x1a\n"
    png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += png_chunk(b"IDAT", zlib.compress(rows, 9))
    png += png_chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output = (project / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    only = {value.strip() for value in args.only.split(",") if value.strip()}
    jobs = [(image_id, model) for image_id, model in JOBS if not only or image_id in only]
    counts = {"rendered": 0, "skipped": 0, "failed": 0}
    for image_id, relative_model in jobs:
        destination = output / f"{image_id}.png"
        if destination.is_file() and not args.overwrite:
            print(f"[RangeLedgerFallback] SKIP {image_id}")
            counts["skipped"] += 1
            continue
        try:
            triangles = load_triangles(project / relative_model)
            if not triangles:
                raise ValueError("model contains no triangles")
            write_png(destination, rasterize(triangles, args.size), args.size)
            print(f"[RangeLedgerFallback] RENDER {image_id}: {destination} ({len(triangles)} triangles)")
            counts["rendered"] += 1
        except Exception as exc:
            print(f"[RangeLedgerFallback] FAILED {image_id}: {exc}")
            counts["failed"] += 1
    print(f"[RangeLedgerFallback] Done: {counts}")
    if counts["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
