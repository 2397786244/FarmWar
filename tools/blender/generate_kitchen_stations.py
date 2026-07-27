import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "kitchen")

TEAM_COLORS = {
    "Red": "#F23838",
    "Blue": "#1687F8",
}

BASE_COLORS = {
    "cream": "#E9DFC9",
    "warm_white": "#F5F0E5",
    "graphite": "#2C343A",
    "dark": "#18232A",
    "steel": "#7893A0",
    "steel_dark": "#4E6875",
    "cyan": "#52CFE0",
    "wood": "#8C5C3D",
    "water": "#55BFE3",
    "indicator": "#FFD34A",
}


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
    for collection in (bpy.data.meshes, bpy.data.materials):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)


def make_material(name, color, metallic=0.0, roughness=0.7):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def make_materials(team=None):
    materials = {
        key: make_material("MAT_" + key.title(), color)
        for key, color in BASE_COLORS.items()
    }
    materials["metal"] = make_material(
        "MAT_Metal",
        BASE_COLORS["steel"],
        metallic=0.58,
        roughness=0.46,
    )
    if team is not None:
        materials["team"] = make_material(
            "MAT_Team_" + team,
            TEAM_COLORS[team],
            roughness=0.56,
        )
    return materials


def create_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_bevel(obj, width):
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1


def finish(obj, name, material, parent):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.parent = parent
    if material is not None:
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
    vertices=10,
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


def add_counter_body(root, materials):
    add_cube(
        "CabinetBody",
        (0.0, 0.0, 0.43),
        (1.20, 0.80, 0.86),
        materials["cream"],
        root,
        bevel=0.055,
    )
    add_cube(
        "BottomPlinth",
        (0.0, 0.03, 0.085),
        (1.08, 0.70, 0.17),
        materials["graphite"],
        root,
        bevel=0.035,
    )
    add_cube(
        "FrontAccent",
        (0.0, -0.415, 0.59),
        (0.84, 0.055, 0.19),
        materials["team"],
        root,
        bevel=0.035,
    )
    add_cube(
        "LeftCabinetDoor",
        (-0.285, -0.428, 0.33),
        (0.50, 0.040, 0.36),
        materials["warm_white"],
        root,
        bevel=0.03,
    )
    add_cube(
        "RightCabinetDoor",
        (0.285, -0.428, 0.33),
        (0.50, 0.040, 0.36),
        materials["warm_white"],
        root,
        bevel=0.03,
    )


def build_induction_counter(team):
    root = create_root("FTF_Kitchen_Induction_Counter_" + team)
    materials = make_materials(team)
    add_counter_body(root, materials)

    add_cube(
        "CounterTop",
        (0.0, 0.0, 0.905),
        (1.26, 0.86, 0.09),
        materials["steel_dark"],
        root,
        bevel=0.04,
    )
    add_cube(
        "InductionGlass",
        (0.0, -0.015, 0.972),
        (0.78, 0.60, 0.045),
        materials["dark"],
        root,
        bevel=0.045,
    )
    add_cylinder(
        "HeatingZone",
        (0.0, -0.015, 1.002),
        0.245,
        0.018,
        materials["graphite"],
        root,
        vertices=12,
    )
    add_torus(
        "HeatingRingOuter",
        (0.0, -0.015, 1.015),
        0.245,
        0.016,
        materials["cyan"],
        root,
    )
    add_torus(
        "HeatingRingInner",
        (0.0, -0.015, 1.016),
        0.145,
        0.011,
        materials["cyan"],
        root,
    )

    add_cube(
        "ControlPanel",
        (0.0, -0.445, 0.80),
        (0.52, 0.055, 0.13),
        materials["graphite"],
        root,
        bevel=0.025,
    )
    for index, x in enumerate((-0.15, 0.0, 0.15)):
        add_cylinder(
            f"ControlButton{index + 1}",
            (x, -0.480, 0.80),
            0.033,
            0.025,
            materials["indicator"] if index == 1 else materials["team"],
            root,
            vertices=8,
            rotation=(1.5708, 0.0, 0.0),
        )

    # Marker-like geometric supports show where the existing pot should sit.
    for side, x in (("Left", -0.31), ("Right", 0.31)):
        add_cube(
            side + "PotGuide",
            (x, -0.015, 1.015),
            (0.08, 0.10, 0.035),
            materials["metal"],
            root,
            bevel=0.015,
        )
    return root


def build_sink(team):
    root = create_root("FTF_Kitchen_Sink_" + team)
    materials = make_materials(team)
    add_counter_body(root, materials)

    # Four separate rim pieces leave a real opening instead of stacking a
    # fake basin over a coplanar countertop.
    add_cube("CounterRimFront", (0.0, -0.365, 0.92), (1.26, 0.13, 0.10), materials["steel"], root, bevel=0.035)
    add_cube("CounterRimBack", (0.0, 0.365, 0.92), (1.26, 0.13, 0.10), materials["steel"], root, bevel=0.035)
    add_cube("CounterRimLeft", (-0.535, 0.0, 0.92), (0.19, 0.62, 0.10), materials["steel"], root, bevel=0.035)
    add_cube("CounterRimRight", (0.535, 0.0, 0.92), (0.19, 0.62, 0.10), materials["steel"], root, bevel=0.035)

    add_cube(
        "BasinFloor",
        (0.0, 0.0, 0.825),
        (0.82, 0.52, 0.055),
        materials["steel_dark"],
        root,
        bevel=0.06,
    )
    add_cube(
        "BasinWater",
        (0.0, -0.015, 0.862),
        (0.67, 0.39, 0.020),
        materials["water"],
        root,
        bevel=0.055,
    )
    add_cylinder(
        "Drain",
        (0.0, 0.02, 0.882),
        0.065,
        0.015,
        materials["dark"],
        root,
        vertices=10,
    )

    add_cylinder_between(
        "FaucetStem",
        (0.0, 0.325, 0.965),
        (0.0, 0.325, 1.275),
        0.045,
        materials["metal"],
        root,
        vertices=10,
    )
    add_cylinder_between(
        "FaucetSpout",
        (0.0, 0.325, 1.275),
        (0.0, -0.065, 1.275),
        0.045,
        materials["metal"],
        root,
        vertices=10,
    )
    add_cylinder_between(
        "FaucetNozzle",
        (0.0, -0.065, 1.275),
        (0.0, -0.065, 1.165),
        0.052,
        materials["metal"],
        root,
        vertices=10,
    )
    for side, x in (("Left", -0.20), ("Right", 0.20)):
        add_cylinder(
            side + "TapKnob",
            (x, 0.325, 1.02),
            0.070,
            0.060,
            materials["team"],
            root,
            vertices=8,
            rotation=(1.5708, 0.0, 0.0),
        )
    return root


def build_cleaver():
    root = create_root("FTF_Kitchen_Cleaver")
    materials = make_materials()

    add_cube(
        "CleaverBlade",
        (-0.22, 0.0, 0.19),
        (0.48, 0.055, 0.30),
        materials["metal"],
        root,
        bevel=0.025,
    )
    add_cube(
        "BladeSpine",
        (-0.22, 0.0, 0.355),
        (0.50, 0.070, 0.055),
        materials["steel_dark"],
        root,
        bevel=0.018,
    )
    add_cube(
        "Handle",
        (0.19, 0.0, 0.225),
        (0.36, 0.13, 0.15),
        materials["wood"],
        root,
        bevel=0.045,
    )
    add_cube(
        "HandleGuard",
        (0.005, 0.0, 0.225),
        (0.065, 0.16, 0.19),
        materials["graphite"],
        root,
        bevel=0.025,
    )
    for index, x in enumerate((0.12, 0.25)):
        add_cylinder(
            f"HandleRivet{index + 1}",
            (x, -0.072, 0.225),
            0.025,
            0.018,
            materials["indicator"],
            root,
            vertices=8,
            rotation=(1.5708, 0.0, 0.0),
        )
    return root


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def validate(root):
    meshes = [obj for obj in hierarchy(root) if obj.type == "MESH"]
    bad_collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    if bad_collision or zero_scale:
        raise RuntimeError(
            f"{root.name}: collision={bad_collision}, zero_scale={zero_scale}"
        )
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(f"VALID {root.name}: meshes={len(meshes)}, triangles={triangles}")


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
    print("EXPORTED", path)


def build_and_export(builder, name, output_dir):
    clear_scene()
    root = builder()
    validate(root)
    path = os.path.join(output_dir, name + ".glb")
    export(root, path)
    return path


def verify(path):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    if collision or zero_scale:
        raise RuntimeError(
            f"REIMPORT FAILED {path}: collision={collision}, zero_scale={zero_scale}"
        )
    print(f"REIMPORT OK {os.path.basename(path)} meshes={len(meshes)}")


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    paths = []
    for team in ("Red", "Blue"):
        paths.append(build_and_export(
            lambda value=team: build_induction_counter(value),
            "FTF_Kitchen_Induction_Counter_" + team,
            output_dir,
        ))
        paths.append(build_and_export(
            lambda value=team: build_sink(value),
            "FTF_Kitchen_Sink_" + team,
            output_dir,
        ))

    paths.append(build_and_export(
        build_cleaver,
        "FTF_Kitchen_Cleaver",
        output_dir,
    ))

    for path in paths:
        verify(path)
    print(f"DONE: generated {len(paths)} GLBs in {output_dir}")


if __name__ == "__main__":
    main()
