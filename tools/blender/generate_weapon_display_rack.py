import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "facilities", "interior")
FILENAME = "WeaponDisplayRack.glb"
PREVIEW_FILENAME = "WeaponDisplayRack_preview.png"

MODULE_WIDTH = 4.60
MODULE_DEPTH = 0.72
MODULE_HEIGHT = 4.72
CABINET_HEIGHT = 0.88
BOARD_BOTTOM = 0.88
BOARD_TOP = 4.72
BOARD_DEPTH = 0.10
SLOT_HEIGHTS = (1.47, 2.58, 3.69)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--preview",
        default=os.path.join("/tmp", PREVIEW_FILENAME),
    )
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    channels = [int(value[index:index + 2], 16) / 255.0 for index in range(0, 8, 2)]

    def srgb_to_linear(channel):
        if channel <= 0.04045:
            return channel / 12.92
        return ((channel + 0.055) / 1.055) ** 2.4

    return tuple(srgb_to_linear(channel) for channel in channels[:3]) + (channels[3],)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def make_material(name, color, metallic=0.0, roughness=0.65):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def finish(obj, name, material, parent):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def add_cube(name, location, dimensions, material, parent, bevel=0.0, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("EdgeBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return finish(obj, name, material, parent)


def add_cylinder(
    name,
    location,
    radius,
    depth,
    material,
    parent,
    vertices=16,
    rotation=(0, 0, 0),
    bevel=0.0,
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    apply_scale(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("EdgeBevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return finish(obj, name, material, parent)


def add_empty(name, location, parent):
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.18
    empty.location = location
    empty.parent = parent
    return empty


def create_root():
    root = bpy.data.objects.new("WeaponDisplayRack", None)
    bpy.context.collection.objects.link(root)
    return root


def build_cabinet(root, materials):
    wood = materials["wood"]
    wood_dark = materials["wood_dark"]
    wood_light = materials["wood_light"]
    black = materials["black"]

    add_cube(
        "CabinetBody",
        (0.0, -0.19, 0.43),
        (MODULE_WIDTH, 0.64, 0.82),
        wood_dark,
        root,
        bevel=0.025,
    )
    add_cube(
        "CabinetTop",
        (0.0, -0.19, 0.87),
        (MODULE_WIDTH, 0.70, 0.08),
        wood_light,
        root,
        bevel=0.018,
    )
    add_cube(
        "CabinetPlinth",
        (0.0, -0.17, 0.055),
        (MODULE_WIDTH, 0.55, 0.11),
        black,
        root,
        bevel=0.012,
    )

    door_width = (MODULE_WIDTH - 0.12) * 0.5
    door_centers = (-door_width * 0.5 - 0.02, door_width * 0.5 + 0.02)
    for index, x in enumerate(door_centers):
        side = "Left" if index == 0 else "Right"
        add_cube(
            f"CabinetDoor{side}",
            (x, -0.522, 0.46),
            (door_width, 0.045, 0.68),
            wood,
            root,
            bevel=0.018,
        )
        # Shallow strips give the doors a readable wooden grain without textures.
        for strip_index in range(5):
            strip_x = x - door_width * 0.38 + strip_index * door_width * 0.19
            strip_material = wood_light if strip_index % 2 == 0 else wood_dark
            add_cube(
                f"{side}DoorGrain{strip_index + 1}",
                (strip_x, -0.548, 0.46),
                (0.025, 0.008, 0.58),
                strip_material,
                root,
                bevel=0.004,
            )

        handle_x = x + (0.15 if index == 0 else -0.15)
        add_cylinder(
            f"CabinetHandle{side}",
            (handle_x, -0.595, 0.48),
            0.025,
            0.24,
            black,
            root,
            vertices=12,
            rotation=(math.radians(90), 0.0, 0.0),
            bevel=0.006,
        )


def build_mesh_backboard(root, materials):
    metal = materials["metal"]
    metal_edge = materials["metal_edge"]
    panel_height = BOARD_TOP - BOARD_BOTTOM
    center_z = (BOARD_BOTTOM + BOARD_TOP) * 0.5

    # A genuine open metal grid keeps the pegboard readable from all viewing angles.
    grid_left = -MODULE_WIDTH * 0.5 + 0.10
    grid_right = MODULE_WIDTH * 0.5 - 0.10
    grid_bottom = BOARD_BOTTOM + 0.10
    grid_top = BOARD_TOP - 0.10
    grid_depth_y = 0.095

    column_count = 24
    row_count = 19
    for index in range(column_count + 1):
        ratio = index / column_count
        x = grid_left + (grid_right - grid_left) * ratio
        add_cube(
            f"PegboardVertical{index + 1:02d}",
            (x, grid_depth_y, center_z),
            (0.026, BOARD_DEPTH, panel_height - 0.20),
            metal,
            root,
            bevel=0.006,
        )
    for index in range(row_count + 1):
        ratio = index / row_count
        z = grid_bottom + (grid_top - grid_bottom) * ratio
        add_cube(
            f"PegboardHorizontal{index + 1:02d}",
            (0.0, grid_depth_y - 0.003, z),
            (MODULE_WIDTH - 0.20, BOARD_DEPTH, 0.026),
            metal,
            root,
            bevel=0.006,
        )

    # The outside frame stays fully inside the module bounds, so copies butt together cleanly.
    add_cube(
        "FrameLeft",
        (-MODULE_WIDTH * 0.5 + 0.04, 0.09, center_z),
        (0.08, 0.13, panel_height),
        metal_edge,
        root,
        bevel=0.012,
    )
    add_cube(
        "FrameRight",
        (MODULE_WIDTH * 0.5 - 0.04, 0.09, center_z),
        (0.08, 0.13, panel_height),
        metal_edge,
        root,
        bevel=0.012,
    )
    add_cube(
        "FrameTop",
        (0.0, 0.09, BOARD_TOP - 0.04),
        (MODULE_WIDTH - 0.08, 0.13, 0.08),
        metal_edge,
        root,
        bevel=0.012,
    )
    add_cube(
        "FrameBottom",
        (0.0, 0.09, BOARD_BOTTOM + 0.04),
        (MODULE_WIDTH - 0.08, 0.13, 0.08),
        metal_edge,
        root,
        bevel=0.012,
    )


def build_weapon_slot(root, materials, slot_index, z):
    metal = materials["metal_edge"]
    rubber = materials["rubber"]
    label = ("Bottom", "Middle", "Top")[slot_index]

    # A slim mounting rail visually defines each of the three one-metre-tall bays.
    add_cube(
        f"{label}WeaponRail",
        (0.0, -0.005, z - 0.12),
        (4.24, 0.10, 0.075),
        metal,
        root,
        bevel=0.015,
    )

    for support_index, x in enumerate((-1.55, 0.0, 1.55)):
        prefix = f"{label}Support{support_index + 1}"
        add_cube(
            prefix + "BackPlate",
            (x, -0.075, z - 0.02),
            (0.15, 0.08, 0.30),
            metal,
            root,
            bevel=0.018,
        )
        add_cube(
            prefix + "Arm",
            (x, -0.235, z - 0.04),
            (0.14, 0.33, 0.075),
            metal,
            root,
            bevel=0.018,
        )
        add_cube(
            prefix + "Lip",
            (x, -0.385, z + 0.045),
            (0.14, 0.07, 0.23),
            metal,
            root,
            bevel=0.018,
        )
        add_cube(
            prefix + "RubberPad",
            (x, -0.235, z + 0.002),
            (0.11, 0.27, 0.018),
            rubber,
            root,
            bevel=0.006,
        )

    add_empty(f"WeaponSlot{label}", (0.0, -0.26, z + 0.42), root)


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def world_bounds(meshes):
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def validate(root):
    descendants = list(hierarchy(root))
    meshes = [obj for obj in descendants if obj.type == "MESH"]
    names = {obj.name for obj in descendants}
    required = {
        "WeaponSlotTop",
        "WeaponSlotMiddle",
        "WeaponSlotBottom",
        "SnapLeft",
        "SnapRight",
        "CabinetDoorLeft",
        "CabinetDoorRight",
    }
    missing = sorted(required - names)
    minimum, maximum = world_bounds(meshes)
    size = maximum - minimum
    if missing:
        raise RuntimeError(f"Missing required nodes: {missing}")
    if size.x < 4.0 or abs(size.x - MODULE_WIDTH) > 0.001:
        raise RuntimeError(f"Invalid rack width: {size.x}")
    if abs(minimum.z) > 0.001 or abs(maximum.z - MODULE_HEIGHT) > 0.001:
        raise RuntimeError(f"Invalid rack height bounds: {minimum.z}, {maximum.z}")
    if any(SLOT_HEIGHTS[index + 1] - SLOT_HEIGHTS[index] < 1.0 for index in range(2)):
        raise RuntimeError("Weapon slot spacing is under one metre")

    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(
        "VALID rack "
        f"size={tuple(round(value, 3) for value in size)} "
        f"slots={SLOT_HEIGHTS} meshes={len(meshes)} triangles={triangles}"
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


def render_preview(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.render.film_transparent = False

    world = scene.world or bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.045, 0.06, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.30

    bpy.ops.mesh.primitive_plane_add(size=18, location=(0.0, 0.0, -0.012))
    floor = bpy.context.object
    floor.name = "PreviewFloor"
    floor.data.materials.append(make_material("MAT_PreviewFloor", "#52575E", roughness=0.88))

    bpy.ops.object.camera_add(location=(7.25, -10.1, 5.15))
    camera = bpy.context.object
    camera.data.lens = 54
    target = Vector((0.0, -0.06, 2.30))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-3.0, -4.0, 6.8))
    key = bpy.context.object
    key.data.energy = 1150
    key.data.shape = "RECTANGLE"
    key.data.size = 5.0
    key.data.size_y = 5.0
    key.rotation_euler = ((Vector((0.0, 0.0, 2.4)) - key.location).to_track_quat("-Z", "Y").to_euler())

    bpy.ops.object.light_add(type="AREA", location=(4.5, -1.5, 3.5))
    fill = bpy.context.object
    fill.data.energy = 700
    fill.data.size = 4.0
    fill.rotation_euler = ((Vector((0.0, 0.0, 2.2)) - fill.location).to_track_quat("-Z", "Y").to_euler())

    bpy.ops.object.light_add(type="AREA", location=(0.0, 2.0, 4.5))
    rim = bpy.context.object
    rim.data.energy = 950
    rim.data.size = 3.0
    rim.rotation_euler = ((Vector((0.0, 0.0, 2.5)) - rim.location).to_track_quat("-Z", "Y").to_euler())

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"PREVIEW {path}")


def build_rack():
    root = create_root()
    materials = {
        "metal": make_material("MAT_BlackPowderCoat", "#0B0D0F", metallic=0.32, roughness=0.52),
        "metal_edge": make_material("MAT_BlackFrame", "#060708", metallic=0.42, roughness=0.40),
        "rubber": make_material("MAT_HookRubber", "#35383A", metallic=0.0, roughness=0.92),
        "wood": make_material("MAT_WarmOak", "#7A482B", metallic=0.0, roughness=0.58),
        "wood_dark": make_material("MAT_WarmOakDark", "#54301E", metallic=0.0, roughness=0.64),
        "wood_light": make_material("MAT_WarmOakLight", "#9A613A", metallic=0.0, roughness=0.54),
        "black": make_material("MAT_CabinetBlack", "#141619", metallic=0.55, roughness=0.42),
    }

    build_cabinet(root, materials)
    build_mesh_backboard(root, materials)
    for index, z in enumerate(SLOT_HEIGHTS):
        build_weapon_slot(root, materials, index, z)

    add_empty("SnapLeft", (-MODULE_WIDTH * 0.5, 0.0, 0.0), root)
    add_empty("SnapRight", (MODULE_WIDTH * 0.5, 0.0, 0.0), root)
    return root


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    output_path = os.path.join(output_dir, FILENAME)
    os.makedirs(output_dir, exist_ok=True)

    clear_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    root = build_rack()
    validate(root)
    export(root, output_path)
    print(f"EXPORTED {output_path}")

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=output_path)
    imported = list(bpy.context.scene.objects)
    imported_meshes = [obj for obj in imported if obj.type == "MESH"]
    imported_names = {obj.name for obj in imported}
    minimum, maximum = world_bounds(imported_meshes)
    size = maximum - minimum
    required = {"WeaponSlotTop", "WeaponSlotMiddle", "WeaponSlotBottom", "SnapLeft", "SnapRight"}
    if required - imported_names or abs(size.x - MODULE_WIDTH) > 0.001:
        raise RuntimeError(
            f"Reimport failed missing={sorted(required - imported_names)} size={tuple(size)}"
        )
    print(
        f"REIMPORT OK {FILENAME} "
        f"size={tuple(round(value, 3) for value in size)} objects={len(imported)}"
    )

    render_preview(os.path.abspath(args.preview))


if __name__ == "__main__":
    main()
