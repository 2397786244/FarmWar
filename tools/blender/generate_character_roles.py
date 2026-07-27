import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "characters")

TEAM_COLORS = {
    "Red": "#F23838",
    "Blue": "#1687F8",
}

EXPRESSIONS = ("Calm", "Fierce", "Funny", "Happy", "Worried")

PALETTE = {
    "skin": "#E5A076",
    "skin_shadow": "#C47753",
    "eye": "#253039",
    "cream": "#F0E4C9",
    "warm_white": "#FFF9EB",
    "graphite": "#303B43",
    "dark_graphite": "#1B252C",
    "steel": "#79A8C5",
    "wood": "#93603D",
    "dark_wood": "#543521",
    "leaf": "#52C95B",
    "leaf_dark": "#258247",
    "teal": "#22BFB2",
    "deep_teal": "#147D78",
    "denim": "#3188C6",
    "denim_dark": "#1D5F94",
    "straw": "#F2C744",
    "straw_dark": "#C39325",
    "cook_red": "#F05A44",
    "cook_yellow": "#FFD13F",
    "guard_navy": "#3477A8",
    "guard_dark": "#214B70",
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index:index + 2], 16) / 255.0 for index in range(0, 8, 2))


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_material(name, color, metallic=0.0, roughness=0.72):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def make_materials(team_name):
    materials = {
        key: make_material("MAT_" + key.title(), value)
        for key, value in PALETTE.items()
    }
    materials["team"] = make_material(
        "MAT_Team_" + team_name,
        TEAM_COLORS[team_name],
        roughness=0.58,
    )
    materials["metal"] = make_material(
        "MAT_Metal",
        PALETTE["steel"],
        metallic=0.55,
        roughness=0.48,
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


def finish_object(obj, name, material, parent):
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
    return finish_object(obj, name, material, parent)


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
    return finish_object(obj, name, material, parent)


def add_ico(name, location, dimensions, material, parent, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=0.5,
        location=location,
    )
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    return finish_object(obj, name, material, parent)


def add_cylinder_between(name, start, end, radius, material, parent, vertices=8):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    midpoint = (start + end) * 0.5
    obj = add_cylinder(
        name,
        midpoint,
        radius,
        direction.length,
        material,
        parent,
        vertices=vertices,
    )
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


def add_expression_shape_keys(obj, transforms):
    """Add the same five facial blend-shape names to one feature mesh."""
    basis = obj.shape_key_add(name="Basis")
    original_positions = [point.co.copy() for point in basis.data]

    for expression in EXPRESSIONS:
        settings = transforms.get(expression, {})
        scale = Vector(settings.get("scale", (1.0, 1.0, 1.0)))
        offset = Vector(settings.get("offset", (0.0, 0.0, 0.0)))
        rotation_y = math.radians(float(settings.get("rotation_y", 0.0)))
        rotation = Matrix.Rotation(rotation_y, 4, "Y")
        shape = obj.shape_key_add(name=expression)

        for index, position in enumerate(original_positions):
            scaled = Vector((
                position.x * scale.x,
                position.y * scale.y,
                position.z * scale.z,
            ))
            shape.data[index].co = rotation @ scaled + offset


def add_eye_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_scale = (1.30, 1.0, 1.30) if side == "Left" else (0.95, 1.0, 0.38)
    funny_offset = (0.0, 0.0, 0.018) if side == "Left" else (0.0, 0.0, -0.012)
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {
            "scale": (1.10, 1.0, 0.55),
            "rotation_y": 14.0 * sign,
            "offset": (0.0, 0.0, -0.010),
        },
        "Funny": {
            "scale": funny_scale,
            "rotation_y": -10.0 * sign,
            "offset": funny_offset,
        },
        "Happy": {
            "scale": (1.18, 1.0, 0.35),
            "rotation_y": -5.0 * sign,
            "offset": (0.0, 0.0, -0.015),
        },
        "Worried": {
            "scale": (0.92, 1.0, 1.15),
            "rotation_y": -8.0 * sign,
            "offset": (0.0, 0.0, 0.005),
        },
    })


def add_brow_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_height = 0.045 if side == "Left" else -0.025
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {
            "rotation_y": -22.0 * sign,
            "offset": (0.0, 0.0, -0.025),
        },
        "Funny": {
            "rotation_y": 18.0 * sign,
            "offset": (0.0, 0.0, funny_height),
        },
        "Happy": {
            "rotation_y": 7.0 * sign,
            "offset": (0.0, 0.0, 0.020),
        },
        "Worried": {
            "rotation_y": 22.0 * sign,
            "offset": (0.0, 0.0, 0.030),
        },
    })


def add_mouth_expression_shapes(obj, segment):
    if segment == "Left":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, 0.025)
        happy_rotation = -18.0
        worried_rotation = 20.0
    elif segment == "Right":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, -0.025)
        happy_rotation = 18.0
        worried_rotation = -20.0
    else:
        happy_offset = (0.0, 0.0, -0.012)
        worried_offset = (0.0, 0.0, 0.018)
        funny_offset = (0.0, 0.0, 0.0)
        happy_rotation = 0.0
        worried_rotation = 0.0

    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {
            "scale": (1.05, 1.0, 0.72),
            "offset": worried_offset,
            "rotation_y": worried_rotation,
        },
        "Funny": {
            "scale": (1.0, 1.0, 1.25 if segment == "Center" else 0.85),
            "offset": funny_offset,
            "rotation_y": 12.0 if segment != "Center" else 0.0,
        },
        "Happy": {
            "offset": happy_offset,
            "rotation_y": happy_rotation,
        },
        "Worried": {
            "scale": (0.92, 1.0, 0.9),
            "offset": worried_offset,
            "rotation_y": worried_rotation,
        },
    })


def add_face(root, materials):
    # A lightly beveled cube keeps a broad, clean face plane. Do not replace
    # this with an Icosphere: its faceted cheeks conflict with the game's
    # blocky character style and make facial expressions harder to read.
    add_cube(
        "Head",
        (0.0, 0.0, 1.72),
        (0.46, 0.38, 0.44),
        materials["skin"],
        root,
        bevel=0.025,
    )
    left_eye = add_ico(
        "LeftEye",
        (-0.09, -0.192, 1.76),
        (0.055, 0.035, 0.070),
        materials["eye"],
        root,
    )
    right_eye = add_ico(
        "RightEye",
        (0.09, -0.192, 1.76),
        (0.055, 0.035, 0.070),
        materials["eye"],
        root,
    )
    add_eye_expression_shapes(left_eye, "Left")
    add_eye_expression_shapes(right_eye, "Right")

    left_brow = add_cube(
        "LeftBrow",
        (-0.10, -0.202, 1.855),
        (0.15, 0.030, 0.035),
        materials["dark_wood"],
        root,
        bevel=0.0,
    )
    right_brow = add_cube(
        "RightBrow",
        (0.10, -0.202, 1.855),
        (0.15, 0.030, 0.035),
        materials["dark_wood"],
        root,
        bevel=0.0,
    )
    add_brow_expression_shapes(left_brow, "Left")
    add_brow_expression_shapes(right_brow, "Right")

    add_cube(
        "Nose",
        (0.0, -0.215, 1.68),
        (0.075, 0.055, 0.075),
        materials["skin_shadow"],
        root,
        bevel=0.012,
    )

    for segment, x in (("Left", -0.060), ("Center", 0.0), ("Right", 0.060)):
        mouth = add_cube(
            "Mouth" + segment,
            (x, -0.207, 1.585),
            (0.070, 0.026, 0.028),
            materials["eye"],
            root,
            bevel=0.0,
        )
        add_mouth_expression_shapes(mouth, segment)

    # The tongue is hidden inside the head for every pose except Funny.
    tongue = add_cube(
        "FunnyTongue",
        (0.0, -0.010, 1.555),
        (0.10, 0.025, 0.075),
        materials["cook_red"],
        root,
        bevel=0.0,
    )
    add_expression_shape_keys(tongue, {
        "Calm": {},
        "Fierce": {},
        "Funny": {"offset": (0.0, -0.215, -0.015)},
        "Happy": {},
        "Worried": {},
    })


def add_body(
    root,
    materials,
    shirt_material,
    pants_material,
    boot_material,
    sleeve_material=None,
):
    sleeve_material = sleeve_material or shirt_material
    add_cube("Torso", (0.0, 0.0, 1.18), (0.62, 0.34, 0.64), shirt_material, root, bevel=0.055)

    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        leg_x = 0.17 * sign
        add_cube(
            side + "Leg",
            (leg_x, 0.0, 0.59),
            (0.25, 0.28, 0.58),
            pants_material,
            root,
            bevel=0.035,
        )
        add_cube(
            side + "Boot",
            (leg_x, -0.055, 0.18),
            (0.27, 0.39, 0.25),
            boot_material,
            root,
            bevel=0.04,
        )

        shoulder = (0.36 * sign, 0.0, 1.38)
        elbow = (0.52 * sign, 0.0, 1.14)
        wrist = (0.61 * sign, -0.015, 0.93)
        add_cylinder_between(
            side + "UpperArm",
            shoulder,
            elbow,
            0.105,
            sleeve_material,
            root,
        )
        add_cylinder_between(
            side + "Forearm",
            elbow,
            wrist,
            0.088,
            materials["skin"],
            root,
        )
        add_ico(
            side + "Hand",
            wrist,
            (0.18, 0.15, 0.19),
            materials["skin"],
            root,
        )

    add_face(root, materials)


def add_team_badge(root, materials, y, z=1.25):
    # Separate depth layers avoid coplanar Z-fighting with clothes and badge frame.
    add_cube(
        "TeamBadgeFrame",
        (0.0, y, z),
        (0.28, 0.040, 0.20),
        materials["graphite"],
        root,
        bevel=0.025,
    )
    add_cube(
        "TeamBadge",
        (0.0, y - 0.034, z),
        (0.21, 0.030, 0.13),
        materials["team"],
        root,
        bevel=0.018,
    )


def build_farmer(team_name):
    root = create_root("FTF_Character_Farmer_" + team_name)
    materials = make_materials(team_name)
    add_body(
        root,
        materials,
        materials["leaf"],
        materials["denim_dark"],
        materials["dark_wood"],
        materials["leaf"],
    )

    # Denim overalls and straps.
    add_cube("OverallBib", (0.0, -0.19, 1.18), (0.42, 0.055, 0.48), materials["denim"], root, bevel=0.035)
    add_cube("LeftOverallStrap", (-0.18, -0.19, 1.43), (0.085, 0.052, 0.28), materials["denim"], root, bevel=0.018)
    add_cube("RightOverallStrap", (0.18, -0.19, 1.43), (0.085, 0.052, 0.28), materials["denim"], root, bevel=0.018)
    add_cube("OverallPocket", (0.0, -0.226, 1.08), (0.23, 0.030, 0.16), materials["denim_dark"], root, bevel=0.018)

    # Straw hat.
    add_cylinder("StrawHatBrim", (0.0, 0.0, 1.94), 0.36, 0.055, materials["straw_dark"], root, vertices=10)
    add_cylinder("StrawHatCrown", (0.0, 0.0, 2.055), 0.23, 0.23, materials["straw"], root, vertices=10, bevel=0.015)
    add_cube("HatBandFront", (0.0, -0.222, 1.995), (0.34, 0.035, 0.07), materials["leaf_dark"], root, bevel=0.012)

    # Seed backpack makes the silhouette immediately readable.
    add_cube("SeedBackpack", (0.0, 0.255, 1.22), (0.46, 0.24, 0.58), materials["teal"], root, bevel=0.065)
    add_cylinder("SeedBackpackCap", (0.0, 0.265, 1.54), 0.095, 0.10, materials["straw"], root, vertices=8)
    add_cube("LeftBackpackStrap", (-0.22, 0.115, 1.24), (0.065, 0.08, 0.55), materials["deep_teal"], root, bevel=0.018)
    add_cube("RightBackpackStrap", (0.22, 0.115, 1.24), (0.065, 0.08, 0.55), materials["deep_teal"], root, bevel=0.018)

    add_team_badge(root, materials, y=-0.265, z=1.27)
    return root


def build_cook(team_name):
    root = create_root("FTF_Character_Cook_" + team_name)
    materials = make_materials(team_name)
    add_body(
        root,
        materials,
        materials["warm_white"],
        materials["graphite"],
        materials["dark_graphite"],
        materials["warm_white"],
    )

    # Double-breasted jacket and apron.
    add_cube("Apron", (0.0, -0.198, 1.08), (0.48, 0.060, 0.54), materials["cream"], root, bevel=0.035)
    add_cube("ApronLower", (0.0, -0.165, 0.72), (0.54, 0.045, 0.38), materials["cream"], root, bevel=0.035)
    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        for row in range(2):
            add_ico(
                f"{side}JacketButton{row + 1}",
                (0.105 * sign, -0.222, 1.23 - row * 0.14),
                (0.055, 0.030, 0.055),
                materials["cook_yellow"],
                root,
            )
    add_cube("Neckerchief", (0.0, -0.205, 1.48), (0.22, 0.055, 0.12), materials["cook_red"], root, bevel=0.025)

    # Chef hat: band plus three low-poly lobes.
    add_cylinder("ChefHatBand", (0.0, 0.0, 1.96), 0.235, 0.13, materials["cream"], root, vertices=10, bevel=0.012)
    add_ico("ChefHatLeft", (-0.13, 0.0, 2.10), (0.30, 0.30, 0.31), materials["warm_white"], root)
    add_ico("ChefHatCenter", (0.0, 0.0, 2.15), (0.34, 0.33, 0.37), materials["warm_white"], root)
    add_ico("ChefHatRight", (0.13, 0.0, 2.10), (0.30, 0.30, 0.31), materials["warm_white"], root)

    add_cube("ApronPocket", (0.0, -0.225, 0.90), (0.27, 0.030, 0.15), materials["cook_red"], root, bevel=0.018)
    add_team_badge(root, materials, y=-0.270, z=1.31)
    return root


def build_guard(team_name):
    root = create_root("FTF_Character_Guard_" + team_name)
    materials = make_materials(team_name)
    add_body(
        root,
        materials,
        materials["guard_navy"],
        materials["guard_dark"],
        materials["dark_graphite"],
        materials["guard_navy"],
    )

    # Protective work vest, shoulder pads and belt.
    add_cube("ProtectiveVest", (0.0, -0.195, 1.22), (0.54, 0.070, 0.50), materials["graphite"], root, bevel=0.045)
    add_cube("LeftShoulderPad", (-0.37, -0.015, 1.40), (0.24, 0.31, 0.19), materials["steel"], root, bevel=0.045)
    add_cube("RightShoulderPad", (0.37, -0.015, 1.40), (0.24, 0.31, 0.19), materials["steel"], root, bevel=0.045)
    add_cube("UtilityBelt", (0.0, -0.025, 0.88), (0.65, 0.35, 0.12), materials["dark_graphite"], root, bevel=0.025)
    add_cube("LeftBeltPouch", (-0.22, -0.215, 0.82), (0.19, 0.14, 0.22), materials["wood"], root, bevel=0.035)
    add_cube("RightBeltPouch", (0.22, -0.215, 0.82), (0.19, 0.14, 0.22), materials["wood"], root, bevel=0.035)
    add_cube("LeftKneePad", (-0.17, -0.165, 0.47), (0.22, 0.10, 0.20), materials["steel"], root, bevel=0.035)
    add_cube("RightKneePad", (0.17, -0.165, 0.47), (0.22, 0.10, 0.20), materials["steel"], root, bevel=0.035)

    # Practical security cap rather than a military helmet.
    add_cylinder("GuardCapCrown", (0.0, 0.01, 1.94), 0.235, 0.15, materials["guard_dark"], root, vertices=10, bevel=0.012)
    add_cube("GuardCapBrim", (0.0, -0.205, 1.91), (0.31, 0.24, 0.045), materials["graphite"], root, bevel=0.025)
    add_cube("RadioBody", (0.29, 0.20, 1.20), (0.14, 0.12, 0.27), materials["graphite"], root, bevel=0.025)
    add_cylinder("RadioAntenna", (0.29, 0.20, 1.43), 0.018, 0.22, materials["dark_graphite"], root, vertices=6)

    add_team_badge(root, materials, y=-0.275, z=1.26)
    return root


ROLE_BUILDERS = {
    "Farmer": build_farmer,
    "Cook": build_cook,
    "Guard": build_guard,
}


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def validate_character(root):
    objects = list(iter_hierarchy(root))
    meshes = [obj for obj in objects if obj.type == "MESH"]
    failures = []

    for obj in meshes:
        upper_name = obj.name.upper()
        if upper_name.startswith(("UCX_", "MESH_UCX_")):
            failures.append("collision mesh: " + obj.name)
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if "." in obj.name:
            failures.append("non-semantic generated name: " + obj.name)

    if failures:
        raise RuntimeError("; ".join(failures))

    triangles = sum(
        len(loop_triangles)
        for loop_triangles in (
            (mesh.data.calc_loop_triangles() or mesh.data.loop_triangles)
            for mesh in meshes
        )
    )
    blend_shapes = sum(
        max(0, len(obj.data.shape_keys.key_blocks) - 1)
        for obj in meshes
        if obj.data.shape_keys is not None
    )
    print(
        f"VALID {root.name}: meshes={len(meshes)}, "
        f"materials={len({mat.name for obj in meshes for mat in obj.data.materials})}, "
        f"triangles={triangles}, blend_shapes={blend_shapes}"
    )


def export_character(root, output_path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )


def export_role_team_variants(role_name, builder, output_dir):
    """Build one role twice and export Red/Blue chest-badge variants."""
    paths = []
    for team_name in ("Red", "Blue"):
        clear_scene()
        root = builder(team_name)
        validate_character(root)
        output_path = os.path.join(
            output_dir,
            f"FTF_Character_{role_name}_{team_name}.glb",
        )
        export_character(root, output_path)
        paths.append(output_path)
        print("EXPORTED", output_path)
    return paths


def verify_export(path):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    collision_meshes = [
        obj.name for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
    ]
    zero_scale = [
        obj.name for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    imported_expression_sets = []
    for obj in meshes:
        if obj.data.shape_keys is None:
            continue
        names = {
            block.name
            for block in obj.data.shape_keys.key_blocks
            if block.name != "Basis"
        }
        if names:
            imported_expression_sets.append((obj.name, names))

    missing_expressions = [
        f"{name}: {sorted(set(EXPRESSIONS) - names)}"
        for name, names in imported_expression_sets
        if not set(EXPRESSIONS).issubset(names)
    ]
    if (
        collision_meshes
        or zero_scale
        or not imported_expression_sets
        or missing_expressions
    ):
        raise RuntimeError(
            f"Invalid export {path}: collision={collision_meshes}, "
            f"zero_scale={zero_scale}, expression_meshes={len(imported_expression_sets)}, "
            f"missing_expressions={missing_expressions}"
        )
    print(
        f"REIMPORT OK {os.path.basename(path)}: meshes={len(meshes)}, "
        f"expression_meshes={len(imported_expression_sets)}"
    )


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    exported = []
    for role_name, builder in ROLE_BUILDERS.items():
        exported.extend(
            export_role_team_variants(role_name, builder, output_dir)
        )

    for path in exported:
        verify_export(path)

    print(f"DONE: generated {len(exported)} character GLBs in {output_dir}")


if __name__ == "__main__":
    main()
