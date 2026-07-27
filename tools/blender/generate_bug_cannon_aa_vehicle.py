import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "tools")

COLORS = {
    "leaf": "#5BC65A",
    "leaf_light": "#8CDD62",
    "leaf_dark": "#26734A",
    "purple": "#7953C6",
    "purple_dark": "#49327C",
    "bug_yellow": "#F4C83E",
    "graphite": "#2C343A",
    "dark": "#17232A",
    "steel": "#6F8793",
    "navy": "#27577A",
    "blue": "#398DCA",
    "cyan": "#53D7E5",
    "orange": "#F09838",
    "cream": "#E9DFC9",
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--asset",
        choices=("all", "bug-cannon", "anti-air"),
        default="all",
    )
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


def make_materials():
    materials = {
        key: make_material("MAT_" + key.title(), color)
        for key, color in COLORS.items()
    }
    materials["metal"] = make_material(
        "MAT_Metal",
        COLORS["steel"],
        metallic=0.58,
        roughness=0.46,
    )
    return materials


def create_empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    return obj


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


def add_cone(
    name,
    location,
    radius1,
    radius2,
    depth,
    material,
    parent,
    vertices=8,
    rotation=(0, 0, 0),
):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    apply_scale(obj)
    return finish(obj, name, material, parent)


def add_ico(name, location, dimensions, material, parent):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
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


def build_bug_cannon():
    root = create_empty("FTF_Tool_Bug_Cannon_GreenPurple")
    materials = make_materials()

    add_cube(
        "Receiver",
        (0.0, 0.0, 0.0),
        (0.52, 0.70, 0.38),
        materials["leaf"],
        root,
        bevel=0.065,
    )
    add_cylinder(
        "BugBarrel",
        (0.0, -0.55, 0.07),
        0.18,
        0.72,
        materials["leaf_dark"],
        root,
        vertices=10,
        rotation=(math.radians(90), 0.0, 0.0),
    )
    add_cone(
        "MuzzleBell",
        (0.0, -0.94, 0.07),
        0.28,
        0.18,
        0.20,
        materials["purple"],
        root,
        vertices=10,
        rotation=(math.radians(90), 0.0, 0.0),
    )
    add_cylinder(
        "MuzzleOpening",
        (0.0, -1.055, 0.07),
        0.18,
        0.035,
        materials["dark"],
        root,
        vertices=10,
        rotation=(math.radians(90), 0.0, 0.0),
    )

    # Segmented insect abdomen doubles as the ammunition canister.
    add_ico(
        "BugAbdomen",
        (0.0, 0.38, 0.18),
        (0.62, 0.68, 0.52),
        materials["purple"],
        root,
    )
    for index, y in enumerate((0.18, 0.37, 0.56)):
        add_cylinder(
            f"AbdomenBand{index + 1}",
            (0.0, y, 0.18),
            0.315,
            0.055,
            materials["purple_dark"],
            root,
            vertices=10,
            rotation=(math.radians(90), 0.0, 0.0),
        )

    # Compound-eye pods establish the insect face without obscuring the muzzle.
    add_ico(
        "LeftCompoundEye",
        (-0.245, -0.30, 0.25),
        (0.18, 0.17, 0.20),
        materials["bug_yellow"],
        root,
    )
    add_ico(
        "RightCompoundEye",
        (0.245, -0.30, 0.25),
        (0.18, 0.17, 0.20),
        materials["bug_yellow"],
        root,
    )

    # Mandibles frame the firing opening.
    add_cube(
        "LeftMandible",
        (-0.24, -0.95, 0.02),
        (0.12, 0.34, 0.10),
        materials["cream"],
        root,
        bevel=0.025,
        rotation=(0.0, 0.0, math.radians(-22)),
    )
    add_cube(
        "RightMandible",
        (0.24, -0.95, 0.02),
        (0.12, 0.34, 0.10),
        materials["cream"],
        root,
        bevel=0.025,
        rotation=(0.0, 0.0, math.radians(22)),
    )

    # Solid wing-like fins avoid transparent sorting issues.
    add_cube(
        "LeftWingFin",
        (-0.38, 0.22, 0.26),
        (0.30, 0.42, 0.055),
        materials["leaf_light"],
        root,
        bevel=0.04,
        rotation=(0.0, math.radians(-15), math.radians(-15)),
    )
    add_cube(
        "RightWingFin",
        (0.38, 0.22, 0.26),
        (0.30, 0.42, 0.055),
        materials["leaf_light"],
        root,
        bevel=0.04,
        rotation=(0.0, math.radians(15), math.radians(15)),
    )

    add_cylinder_between(
        "LeftAntenna",
        (-0.13, -0.12, 0.30),
        (-0.26, -0.40, 0.58),
        0.025,
        materials["leaf_dark"],
        root,
        vertices=6,
    )
    add_cylinder_between(
        "RightAntenna",
        (0.13, -0.12, 0.30),
        (0.26, -0.40, 0.58),
        0.025,
        materials["leaf_dark"],
        root,
        vertices=6,
    )
    add_ico("LeftAntennaTip", (-0.26, -0.40, 0.58), (0.09, 0.09, 0.09), materials["bug_yellow"], root)
    add_ico("RightAntennaTip", (0.26, -0.40, 0.58), (0.09, 0.09, 0.09), materials["bug_yellow"], root)

    add_cube(
        "Grip",
        (0.0, 0.08, -0.39),
        (0.22, 0.30, 0.58),
        materials["graphite"],
        root,
        bevel=0.055,
        rotation=(math.radians(-10), 0.0, 0.0),
    )
    add_cube(
        "GripCap",
        (0.0, 0.13, -0.69),
        (0.25, 0.32, 0.10),
        materials["purple_dark"],
        root,
        bevel=0.035,
    )
    add_cube(
        "Trigger",
        (0.0, -0.13, -0.20),
        (0.08, 0.09, 0.14),
        materials["bug_yellow"],
        root,
        bevel=0.02,
    )
    return root


def build_anti_air_vehicle():
    root = create_empty("FTF_Vehicle_Anti_Air_2m")
    materials = make_materials()

    # Move both complete side assemblies outward so the chassis no longer
    # intersects the tracks. The revised footprint is about 2.3m wide.
    add_cube(
        "LeftTrack",
        (-1.00, 0.0, 0.24),
        (0.30, 2.00, 0.42),
        materials["dark"],
        root,
        bevel=0.08,
    )
    add_cube(
        "RightTrack",
        (1.00, 0.0, 0.24),
        (0.30, 2.00, 0.42),
        materials["dark"],
        root,
        bevel=0.08,
    )
    add_cube(
        "ChassisBody",
        (0.0, 0.0, 0.34),
        (1.65, 1.72, 0.48),
        materials["navy"],
        root,
        bevel=0.10,
    )
    add_cube(
        "FrontBumper",
        (0.0, -0.91, 0.30),
        (1.55, 0.16, 0.25),
        materials["steel"],
        root,
        bevel=0.05,
    )
    add_cube(
        "TeamPanel",
        (0.0, -0.905, 0.48),
        (0.72, 0.045, 0.20),
        materials["cyan"],
        root,
        bevel=0.04,
    )

    for side, x in (("Left", -1.07), ("Right", 1.07)):
        for index, y in enumerate((-0.68, 0.0, 0.68)):
            add_cylinder(
                f"{side}RoadWheel{index + 1}",
                (x, y, 0.25),
                0.22,
                0.16,
                materials["metal"],
                root,
                vertices=8,
                rotation=(0.0, math.radians(90), 0.0),
            )

    # Runtime control hierarchy:
    # TurretYawPivot still rotates around up. GunPitchPivot is retained for
    # compatibility, but now carries a vertical 2x2 missile-cell assembly.
    turret_yaw = create_empty("TurretYawPivot", (0.0, 0.0, 0.70), root)
    add_cylinder(
        "TurretRing",
        (0.0, 0.0, 0.0),
        0.56,
        0.18,
        materials["steel"],
        turret_yaw,
        vertices=12,
    )
    add_cube(
        "TurretHousing",
        (0.0, 0.02, 0.23),
        (0.90, 0.78, 0.46),
        materials["blue"],
        turret_yaw,
        bevel=0.10,
    )
    add_cube(
        "TurretRearAmmoBox",
        (0.0, 0.45, 0.23),
        (0.65, 0.28, 0.38),
        materials["graphite"],
        turret_yaw,
        bevel=0.065,
    )

    gun_pitch = create_empty("GunPitchPivot", (0.0, -0.05, 0.48), turret_yaw)
    add_cube(
        "MissileLauncherBase",
        (0.0, 0.0, 0.0),
        (0.76, 0.68, 0.16),
        materials["graphite"],
        gun_pitch,
        bevel=0.055,
    )
    for column, x in (("Left", -0.17), ("Right", 0.17)):
        for row, y in (("Front", -0.16), ("Rear", 0.16)):
            prefix = column + row + "LaunchCell"
            add_cube(
                prefix + "Body",
                (x, y, 0.22),
                (0.25, 0.25, 0.36),
                materials["navy"],
                gun_pitch,
                bevel=0.035,
            )
            add_cube(
                prefix + "Collar",
                (x, y, 0.41),
                (0.27, 0.27, 0.08),
                materials["orange"],
                gun_pitch,
                bevel=0.025,
            )
            add_cylinder(
                prefix + "Opening",
                (x, y, 0.455),
                0.075,
                0.025,
                materials["dark"],
                gun_pitch,
                vertices=10,
            )

    # Radar remains independently steerable, but is lower and farther back
    # so it sits beneath the missile-cell tops instead of floating above them.
    radar_yaw = create_empty("RadarYawPivot", (0.0, 0.42, 0.38), turret_yaw)
    add_cylinder(
        "RadarMast",
        (0.0, 0.0, 0.12),
        0.045,
        0.24,
        materials["metal"],
        radar_yaw,
        vertices=8,
    )
    radar_pitch = create_empty("RadarPitchPivot", (0.0, 0.0, 0.26), radar_yaw)
    add_cone(
        "RadarDish",
        (0.0, -0.035, 0.0),
        0.30,
        0.22,
        0.10,
        materials["cream"],
        radar_pitch,
        vertices=10,
        rotation=(math.radians(90), 0.0, 0.0),
    )
    add_cylinder(
        "RadarReceiver",
        (0.0, -0.13, 0.0),
        0.055,
        0.16,
        materials["cyan"],
        radar_pitch,
        vertices=8,
        rotation=(math.radians(90), 0.0, 0.0),
    )
    return root


def hierarchy(root):
    yield root
    for child in root.children:
        yield from hierarchy(child)


def validate(root, required_nodes=()):
    objects = list(hierarchy(root))
    meshes = [obj for obj in objects if obj.type == "MESH"]
    names = {obj.name for obj in objects}
    collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    missing = [name for name in required_nodes if name not in names]
    if collision or zero_scale or missing:
        raise RuntimeError(
            f"{root.name}: collision={collision}, zero_scale={zero_scale}, missing={missing}"
        )
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    print(
        f"VALID {root.name}: meshes={len(meshes)}, triangles={triangles}, "
        f"required_nodes={list(required_nodes)}"
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
    print("EXPORTED", path)


def build_export_verify(builder, filename, output_dir, required_nodes=()):
    clear_scene()
    root = builder()
    validate(root, required_nodes)
    path = os.path.join(output_dir, filename)
    export(root, path)

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    objects = list(bpy.context.scene.objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    names = {obj.name for obj in objects}
    collision = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    missing = [name for name in required_nodes if name not in names]
    if collision or zero_scale or missing:
        raise RuntimeError(
            f"REIMPORT {filename}: collision={collision}, "
            f"zero_scale={zero_scale}, missing={missing}"
        )
    print(
        f"REIMPORT OK {filename}: meshes={len(meshes)}, "
        f"pivots={list(required_nodes)}"
    )
    return path


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    paths = []
    if args.asset in ("all", "bug-cannon"):
        paths.append(build_export_verify(
            build_bug_cannon,
            "FTF_Tool_Bug_Cannon_GreenPurple.glb",
            output_dir,
        ))
    if args.asset in ("all", "anti-air"):
        paths.append(build_export_verify(
            build_anti_air_vehicle,
            "FTF_Vehicle_Anti_Air_2m.glb",
            output_dir,
            (
                "TurretYawPivot",
                "GunPitchPivot",
                "RadarYawPivot",
                "RadarPitchPivot",
            ),
        ))
    print("DONE", paths)


if __name__ == "__main__":
    main()
