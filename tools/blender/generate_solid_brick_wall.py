import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "buildings")
FILENAME = "FTF_Building_Solid_Brick_Wall_2x3m.glb"

WALL_WIDTH = 2.0
WALL_DEPTH = 0.5
WALL_HEIGHT = 3.0


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index:index + 2], 16) / 255.0 for index in range(0, 8, 2))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def make_material(name, color, roughness=0.8):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def create_root():
    root = bpy.data.objects.new("FTF_Building_Solid_Brick_Wall_2x3m", None)
    bpy.context.collection.objects.link(root)
    return root


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_cube(name, location, dimensions, material, parent, bevel=0.0, apply_bevel=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.dimensions = dimensions
    apply_scale(obj)
    obj.parent = parent
    obj.data.materials.append(material)

    if bevel > 0.0:
        modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        if apply_bevel:
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            obj.select_set(False)
    return obj


def join_objects(objects, name, parent):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    joined.data.name = "MESH_" + name
    joined.parent = parent
    joined.select_set(False)
    return joined


def wide_row_layout(row):
    if row % 2 == 0:
        return [
            (-0.75, 0.46),
            (-0.25, 0.46),
            (0.25, 0.46),
            (0.75, 0.46),
        ]
    return [
        (-0.875, 0.21),
        (-0.50, 0.46),
        (0.0, 0.46),
        (0.50, 0.46),
        (0.875, 0.21),
    ]


def narrow_row_layout(row):
    if row % 2 == 0:
        return [
            (-0.125, 0.21),
            (0.125, 0.21),
        ]
    return [
        (-0.1875, 0.085),
        (0.0, 0.21),
        (0.1875, 0.085),
    ]


def build_vertical_face(root, materials, side):
    brick_depth = 0.032
    brick_height = 0.26
    objects = []

    for row in range(10):
        z = 0.15 + row * 0.30
        if side in ("Front", "Back"):
            fixed = -0.234 if side == "Front" else 0.234
            bricks = wide_row_layout(row)
        else:
            fixed = -0.984 if side == "Left" else 0.984
            bricks = narrow_row_layout(row)

        for column, (across, width) in enumerate(bricks):
            material = materials[(row * 3 + column) % len(materials)]
            if side in ("Front", "Back"):
                location = (across, fixed, z)
                dimensions = (width, brick_depth, brick_height)
            else:
                location = (fixed, across, z)
                dimensions = (brick_depth, width, brick_height)
            objects.append(add_cube(
                f"{side}Brick_{row:02d}_{column:02d}",
                location,
                dimensions,
                material,
                root,
                bevel=0.0,
            ))

    return join_objects(objects, side + "BrickPattern", root)


def build_horizontal_face(root, materials, side):
    z = 0.016 if side == "Bottom" else WALL_HEIGHT - 0.016
    objects = []

    for row, y in enumerate((-0.125, 0.125)):
        for column, (x, width) in enumerate(wide_row_layout(row)):
            material = materials[(row * 5 + column) % len(materials)]
            objects.append(add_cube(
                f"{side}Brick_{row:02d}_{column:02d}",
                (x, y, z),
                (width, 0.21, 0.032),
                material,
                root,
                bevel=0.0,
            ))

    return join_objects(objects, side + "BrickPattern", root)


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def world_bounds(meshes):
    points = [
        obj.matrix_world @ Vector(corner)
        for obj in meshes
        for corner in obj.bound_box
    ]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def validate(root):
    meshes = [obj for obj in hierarchy(root) if obj.type == "MESH"]
    collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    minimum, maximum = world_bounds(meshes)
    size = maximum - minimum
    expected = Vector((WALL_WIDTH, WALL_DEPTH, WALL_HEIGHT))
    size_error = (size - expected).length

    if collision or zero_scale or size_error > 0.0001:
        raise RuntimeError(
            f"Invalid wall: collision={collision}, zero_scale={zero_scale}, "
            f"size={tuple(size)}, expected={tuple(expected)}"
        )

    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(
        f"VALID wall size={tuple(round(value, 4) for value in size)} "
        f"meshes={len(meshes)} triangles={triangles}"
    )


def export(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)
    clear_scene()

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    mortar = make_material("MAT_Mortar", "#8C8173", roughness=0.92)
    brick_materials = [
        make_material("MAT_Brick_Red", "#A84438", roughness=0.88),
        make_material("MAT_Brick_Warm", "#C05A43", roughness=0.86),
        make_material("MAT_Brick_Dark", "#7D342F", roughness=0.90),
    ]

    root = create_root()
    # The solid core is inset on all axes. Six geometric brick skins reach the
    # exact outer dimensions while slightly overlapping the core internally.
    add_cube(
        "SolidWallCore",
        (0.0, 0.0, WALL_HEIGHT * 0.5),
        (1.938, 0.438, WALL_HEIGHT - 0.062),
        mortar,
        root,
        bevel=0.012,
    )
    for side in ("Front", "Back", "Left", "Right"):
        build_vertical_face(root, brick_materials, side)
    build_horizontal_face(root, brick_materials, "Top")
    build_horizontal_face(root, brick_materials, "Bottom")

    validate(root)
    output_path = os.path.join(output_dir, FILENAME)
    export(root, output_path)

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=output_path)
    imported_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH"
    ]
    minimum, maximum = world_bounds(imported_meshes)
    size = maximum - minimum
    collision = [
        obj.name for obj in imported_meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    if collision or (size - Vector((2.0, 0.5, 3.0))).length > 0.0001:
        raise RuntimeError(
            f"Reimport failed: collision={collision}, size={tuple(size)}"
        )

    print(
        f"REIMPORT OK {FILENAME} "
        f"size={tuple(round(value, 4) for value in size)} "
        f"meshes={len(imported_meshes)}"
    )


if __name__ == "__main__":
    main()
