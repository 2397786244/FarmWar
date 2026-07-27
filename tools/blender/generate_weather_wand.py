import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "tools")
FILENAME = "FTF_Tool_Weather_Wand_PurpleCrystal.glb"


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


def create_root():
    root = bpy.data.objects.new("FTF_Tool_Weather_Wand_PurpleCrystal", None)
    bpy.context.collection.objects.link(root)
    return root


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_bevel(obj, width):
    if width <= 0:
        return
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1


def finish(obj, name, material, parent):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def add_cube(name, location, dimensions, material, parent, bevel=0.02, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish(obj, name, material, parent)


def add_cylinder(
    name,
    location,
    radius,
    depth,
    material,
    parent,
    vertices=8,
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
    add_bevel(obj, bevel)
    return finish(obj, name, material, parent)


def add_ico(name, location, dimensions, material, parent, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=0.5,
        location=location,
    )
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    return finish(obj, name, material, parent)


def add_cylinder_between(name, start, end, radius, material, parent, vertices=8):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    obj = add_cylinder(
        name,
        (start + end) * 0.5,
        radius,
        direction.length,
        material,
        parent,
        vertices=vertices,
    )
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


def add_torus(name, location, major_radius, minor_radius, material, parent):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=12,
        minor_segments=4,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=location,
    )
    return finish(bpy.context.object, name, material, parent)


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def build_wand():
    root = create_root()
    dark_purple = make_material("MAT_DeepPurple", "#35265E", roughness=0.63)
    purple = make_material("MAT_CrystalPurple", "#864FE0", roughness=0.30)
    purple_light = make_material("MAT_CrystalHighlight", "#C08BFF", roughness=0.25)
    gold = make_material("MAT_WarmGold", "#E0A83A", metallic=0.62, roughness=0.42)
    graphite = make_material("MAT_GripGraphite", "#252D35", roughness=0.82)
    cyan = make_material("MAT_WeatherCyan", "#55D5E5", roughness=0.48)

    add_ico("BottomPommel", (0.0, 0.0, 0.075), (0.18, 0.18, 0.15), gold, root)
    add_cylinder("Grip", (0.0, 0.0, 0.30), 0.095, 0.40, graphite, root, vertices=8, bevel=0.012)
    add_cylinder("LowerGripBand", (0.0, 0.0, 0.13), 0.115, 0.055, gold, root, vertices=10)
    add_cylinder("UpperGripBand", (0.0, 0.0, 0.49), 0.115, 0.055, gold, root, vertices=10)

    add_cylinder("MainShaft", (0.0, 0.0, 0.78), 0.060, 0.58, dark_purple, root, vertices=8)
    add_cylinder("ShaftSpiralBandLower", (0.0, 0.0, 0.63), 0.078, 0.055, purple, root, vertices=8)
    add_cylinder("ShaftSpiralBandUpper", (0.0, 0.0, 0.88), 0.078, 0.055, cyan, root, vertices=8)

    # A simple weather-direction cross makes the wand readable from the rear.
    add_cube("WeatherCrossHorizontal", (0.0, 0.0, 0.98), (0.34, 0.075, 0.075), gold, root, bevel=0.025)
    add_cube("WeatherCrossDepth", (0.0, 0.0, 0.98), (0.075, 0.34, 0.075), gold, root, bevel=0.025)
    add_cylinder("CrystalCollar", (0.0, 0.0, 1.06), 0.17, 0.13, gold, root, vertices=10)
    add_torus("CrystalSeatRing", (0.0, 0.0, 1.135), 0.15, 0.025, purple_light, root)

    crystal_center = Vector((0.0, 0.0, 1.32))
    add_ico(
        "CrystalBall",
        crystal_center,
        (0.38, 0.38, 0.38),
        purple,
        root,
        subdivisions=2,
    )

    # Four gold claws visibly hold the crystal without covering its silhouette.
    claw_starts = [
        (-0.13, 0.0, 1.10),
        (0.13, 0.0, 1.10),
        (0.0, -0.13, 1.10),
        (0.0, 0.13, 1.10),
    ]
    claw_ends = [
        (-0.15, 0.0, 1.32),
        (0.15, 0.0, 1.32),
        (0.0, -0.15, 1.32),
        (0.0, 0.15, 1.32),
    ]
    for index, (start, end) in enumerate(zip(claw_starts, claw_ends)):
        add_cylinder_between(
            f"CrystalClaw{index + 1}",
            start,
            end,
            0.022,
            gold,
            root,
            vertices=6,
        )

    # Three small facets add color variation without transparent materials.
    add_ico("CrystalFacetLeft", (-0.095, -0.155, 1.36), (0.075, 0.035, 0.11), purple_light, root)
    add_ico("CrystalFacetRight", (0.085, -0.165, 1.27), (0.060, 0.030, 0.085), purple_light, root)
    add_ico("CrystalFacetTop", (0.0, -0.11, 1.45), (0.070, 0.030, 0.060), cyan, root)
    return root


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
    if collision or zero_scale or "CrystalBall" not in {obj.name for obj in meshes}:
        raise RuntimeError(
            f"Invalid wand collision={collision}, zero_scale={zero_scale}"
        )
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(f"VALID wand meshes={len(meshes)} triangles={triangles}")


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

    root = build_wand()
    validate(root)
    path = os.path.join(output_dir, FILENAME)
    export(root, path)

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    names = {obj.name for obj in meshes}
    collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    if collision or "CrystalBall" not in names:
        raise RuntimeError(
            f"Reimport failed collision={collision}, crystal={'CrystalBall' in names}"
        )
    print(f"REIMPORT OK {FILENAME} meshes={len(meshes)}")


if __name__ == "__main__":
    main()
