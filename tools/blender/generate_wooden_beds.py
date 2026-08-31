import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "facilities", "interior")
DOUBLE_FILENAME = "WoodenDoubleBed.glb"
SINGLE_FILENAME = "WoodenSingleBed.glb"
PREVIEW_FILENAME = "WoodenBeds_preview.png"

LENGTH = 4.0
DOUBLE_WIDTH = 5.0
SINGLE_WIDTH = 3.5


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate wooden double and single bed GLBs.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=os.path.join("/tmp", PREVIEW_FILENAME))
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
    for data in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(data):
            if item.users == 0:
                data.remove(item)


def make_material(name, color, metallic=0.0, roughness=0.55):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = next(
        (node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if bsdf is None:
        bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
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
    obj.data.materials.append(material)
    obj.parent = parent
    return obj


def add_cube(name, location, dimensions, material, parent, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    return finish(obj, name, material, parent)


def add_cylinder(name, location, radius, depth, material, parent, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=16,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    modifier = obj.modifiers.new("EdgeBevel", "BEVEL")
    modifier.width = min(radius * 0.18, 0.025)
    modifier.segments = 2
    return finish(obj, name, material, parent)


def add_pillow(name, location, width, material, parent):
    # A scaled UV sphere keeps the pillow soft without relying on cloth simulation.
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=32,
        ring_count=16,
        location=location,
    )
    obj = bpy.context.object
    obj.scale = (width * 0.5, 0.48, 0.19)
    apply_scale(obj)
    modifier = obj.modifiers.new("PillowSmooth", "BEVEL")
    modifier.width = 0.025
    modifier.segments = 2
    return finish(obj, name, material, parent)


def add_empty(name, location, parent):
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.22
    empty.location = location
    empty.parent = parent
    return empty


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def world_bounds(meshes):
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def create_materials():
    return {
        "wood": make_material("MAT_HoneyOak", "#8A542F", roughness=0.48),
        "wood_dark": make_material("MAT_HoneyOakDark", "#50301C", roughness=0.58),
        "wood_light": make_material("MAT_HoneyOakLight", "#B67742", roughness=0.46),
        "linen": make_material("MAT_WhiteLinen", "#F1F1EA", roughness=0.86),
        "linen_shadow": make_material("MAT_LinenFold", "#D9DBD6", roughness=0.90),
        "blue": make_material("MAT_QuiltBlue", "#2E639C", roughness=0.78),
        "blue_light": make_material("MAT_QuiltStitch", "#5B91C4", roughness=0.72),
        "brass": make_material("MAT_BrassDetail", "#B78A3A", metallic=0.72, roughness=0.30),
    }


def build_bed(root_name, width, length, pillow_count, materials):
    root = bpy.data.objects.new(root_name, None)
    bpy.context.collection.objects.link(root)

    wood = materials["wood"]
    wood_dark = materials["wood_dark"]
    wood_light = materials["wood_light"]
    linen = materials["linen"]
    linen_shadow = materials["linen_shadow"]
    blue = materials["blue"]
    blue_light = materials["blue_light"]
    brass = materials["brass"]

    half_width = width * 0.5
    half_length = length * 0.5
    rail_height = 0.54
    mattress_z = 0.82
    mattress_height = 0.34
    top_z = mattress_z + mattress_height * 0.5

    # Four legs stop just inside the lower edge of the rails.  This keeps a
    # small, believable join while avoiding the visibly deep overlap that
    # would result from running a full-height leg through the frame.
    for x, x_name in ((-half_width + 0.13, "Left"), (half_width - 0.13, "Right")):
        for y, y_name in ((-half_length + 0.13, "Foot"), (half_length - 0.13, "Head")):
            add_cube(
                f"Leg{x_name}{y_name}",
                (x, y, 0.19),
                (0.26, 0.26, 0.38),
                wood_dark,
                root,
                bevel=0.035,
            )
            add_cylinder(
                f"LegCap{x_name}{y_name}",
                (x, y, 0.365),
                0.050,
                0.028,
                brass,
                root,
            )

    # Each rail ends flush against the next rail's inner face.  Leaving the
    # former full-length/full-width overlap at the corners creates coplanar
    # faces, which flicker once rendered in the game.
    add_cube("SideRailLeft", (-half_width + 0.095, 0.0, rail_height), (0.19, length - 0.36, 0.42), wood_dark, root, bevel=0.035)
    add_cube("SideRailRight", (half_width - 0.095, 0.0, rail_height), (0.19, length - 0.36, 0.42), wood_dark, root, bevel=0.035)
    add_cube("FootRail", (0.0, -half_length + 0.09, rail_height), (width - 0.38, 0.18, 0.42), wood, root, bevel=0.035)
    add_cube("HeadRail", (0.0, half_length - 0.09, rail_height), (width - 0.38, 0.18, 0.42), wood, root, bevel=0.035)

    # Cross slats are deliberately visible from the sides and ensure the mattress has a believable support.
    slat_count = 7
    for index in range(slat_count):
        y = -half_length + 0.42 + index * (length - 0.84) / float(slat_count - 1)
        add_cube(
            f"SupportSlat{index + 1:02d}",
            (0.0, y, 0.67),
            (width - 0.30, 0.085, 0.075),
            wood_light if index % 2 == 0 else wood,
            root,
            bevel=0.010,
        )

    # A tall, slatted wooden headboard gives the furniture its main silhouette.
    add_cube("HeadboardFrameTop", (0.0, half_length - 0.10, 2.05), (width, 0.20, 0.18), wood_dark, root, bevel=0.035)
    add_cube("HeadboardFrameBottom", (0.0, half_length - 0.10, 0.82), (width, 0.20, 0.16), wood_dark, root, bevel=0.028)
    panel_count = 10 if width >= 4.5 else 7
    panel_width = (width - 0.46) / panel_count
    for index in range(panel_count):
        x = -half_width + 0.23 + panel_width * (index + 0.5)
        add_cube(
            f"HeadboardSlat{index + 1:02d}",
            (x, half_length - 0.10, 1.42),
            (panel_width - 0.035, 0.15, 1.20),
            wood if index % 2 == 0 else wood_light,
            root,
            bevel=0.022,
        )

    # Mattress and sheet use distinct thin layers so white linen remains legible above the wood frame.
    add_cube("Mattress", (0.0, 0.0, mattress_z), (width - 0.24, length - 0.24, mattress_height), linen, root, bevel=0.09)
    add_cube("FittedSheet", (0.0, 0.0, top_z + 0.026), (width - 0.30, length - 0.30, 0.060), linen_shadow, root, bevel=0.045)
    add_cube("SheetTop", (0.0, 0.03, top_z + 0.064), (width - 0.38, length - 0.38, 0.036), linen, root, bevel=0.030)

    # Pillows are at the head; the single bed gets one centered pillow, the double gets two.
    pillow_y = half_length - 0.72
    if pillow_count == 1:
        add_pillow("Pillow01", (0.0, pillow_y, top_z + 0.22), min(width * 0.60, 1.55), linen, root)
    else:
        pillow_width = min(width * 0.31, 1.50)
        pillow_gap = 0.18
        for index, x in enumerate((-(pillow_width + pillow_gap) * 0.5, (pillow_width + pillow_gap) * 0.5)):
            add_pillow(f"Pillow{index + 1:02d}", (x, pillow_y, top_z + 0.22), pillow_width, linen, root)

    # The blue duvet sits below the pillows, leaves a linen border, and has a folded top plus stitched bands.
    duvet_length = length * 0.62
    duvet_center_y = -0.46
    duvet_z = top_z + 0.16
    add_cube(
        "BlueDuvet",
        (0.0, duvet_center_y, duvet_z),
        (width - 0.44, duvet_length, 0.24),
        blue,
        root,
        bevel=0.115,
    )
    add_cube(
        "DuvetFold",
        (0.0, duvet_center_y + duvet_length * 0.5 - 0.15, duvet_z + 0.115),
        (width - 0.52, 0.28, 0.105),
        blue_light,
        root,
        bevel=0.045,
    )
    for index in range(4):
        y = duvet_center_y - duvet_length * 0.34 + index * duvet_length * 0.225
        add_cube(
            f"DuvetStitch{index + 1:02d}",
            (0.0, y, duvet_z + 0.125),
            (width - 0.72, 0.030, 0.018),
            blue_light,
            root,
            bevel=0.006,
        )

    add_empty("BedCenter", (0.0, 0.0, top_z + 0.10), root)
    add_empty("HeadboardAnchor", (0.0, half_length, 0.0), root)
    add_empty("SleepPosition", (0.0, -0.10, top_z + 0.18), root)
    return root


def validate(root, width, length, pillow_count):
    descendants = list(hierarchy(root))
    meshes = [obj for obj in descendants if obj.type == "MESH"]
    names = {obj.name for obj in descendants}
    required = {
        "Mattress", "FittedSheet", "SheetTop", "BlueDuvet",
        "HeadboardFrameTop", "HeadboardFrameBottom", "BedCenter", "SleepPosition",
    }
    for index in range(pillow_count):
        required.add(f"Pillow{index + 1:02d}")
    missing = sorted(required - names)
    if missing:
        raise RuntimeError(f"{root.name} missing nodes: {missing}")
    minimum, maximum = world_bounds(meshes)
    size = maximum - minimum
    if abs(size.x - width) > 0.001 or abs(size.y - length) > 0.001:
        raise RuntimeError(f"{root.name} size mismatch: {tuple(size)} expected={(width, length)}")
    if abs(minimum.z) > 0.001:
        raise RuntimeError(f"{root.name} must rest on floor, got z={minimum.z}")
    print(
        f"VALID {root.name} size={tuple(round(value, 3) for value in size)} "
        f"pillows={pillow_count} meshes={len(meshes)}"
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
    print(f"EXPORTED {path}")


def reimport_validate(path, width, length):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    minimum, maximum = world_bounds(meshes)
    size = maximum - minimum
    if abs(size.x - width) > 0.001 or abs(size.y - length) > 0.001:
        raise RuntimeError(f"Reimport size mismatch for {os.path.basename(path)}: {tuple(size)}")
    print(f"REIMPORT OK {os.path.basename(path)} size={tuple(round(value, 3) for value in size)}")


def render_preview(double_path, single_path, preview_path):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=double_path)
    double_root = bpy.context.scene.objects.get("WoodenDoubleBed")
    if double_root is not None:
        double_root.location.x = -3.0
    bpy.ops.import_scene.gltf(filepath=single_path)
    single_root = bpy.context.scene.objects.get("WoodenSingleBed")
    if single_root is not None:
        single_root.location.x = 3.35

    scene = bpy.context.scene
    # Blender 4 uses the EEVEE_NEXT identifier; Blender 5 again exposes it
    # as BLENDER_EEVEE. Keep the generator usable with either installed app.
    scene.render.engine = "BLENDER_EEVEE" if bpy.app.version >= (5, 0, 0) else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 820
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = preview_path
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("BedPreviewWorld")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.050, 0.070, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35

    bpy.ops.mesh.primitive_plane_add(size=24, location=(0.0, 0.0, -0.012))
    floor = bpy.context.object
    floor.data.materials.append(make_material("MAT_PreviewFloor", "#56616B", roughness=0.92))

    bpy.ops.object.camera_add(location=(10.8, -13.8, 8.2))
    camera = bpy.context.object
    camera.data.lens = 52
    camera.rotation_euler = (Vector((0.0, 0.0, 1.0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    for name, location, energy, size in (
        ("Key", (-6.5, -5.0, 8.0), 1450, 5.5),
        ("Fill", (7.0, -2.0, 5.0), 950, 4.5),
        ("Rim", (0.0, 5.0, 7.0), 1050, 4.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (Vector((0.0, 0.0, 0.9)) - light.location).to_track_quat("-Z", "Y").to_euler()

    os.makedirs(os.path.dirname(os.path.abspath(preview_path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print(f"PREVIEW {preview_path}")


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    generated = (
        (DOUBLE_FILENAME, "WoodenDoubleBed", DOUBLE_WIDTH, 2),
        (SINGLE_FILENAME, "WoodenSingleBed", SINGLE_WIDTH, 1),
    )
    output_paths = {}
    for filename, root_name, width, pillows in generated:
        clear_scene()
        materials = create_materials()
        root = build_bed(root_name, width, LENGTH, pillows, materials)
        validate(root, width, LENGTH, pillows)
        path = os.path.join(output_dir, filename)
        export(root, path)
        output_paths[filename] = path
        reimport_validate(path, width, LENGTH)

    render_preview(output_paths[DOUBLE_FILENAME], output_paths[SINGLE_FILENAME], os.path.abspath(args.preview))


if __name__ == "__main__":
    main()
