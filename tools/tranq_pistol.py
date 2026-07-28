# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Rounded Tranquilizer Pistol (Black / Purple)
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_TranquilizerPistol_RoundPurple_v2.glb
#
# DESIGN
# - Dedicated non-lethal tranquilizer launcher; no Glock / box-slide silhouette.
# - Rounded multi-stage cylindrical body:
#     rear control chamber -> pressure chamber -> emitter tube -> muzzle collar.
# - Rounded tilted grip and circular trigger guard.
# - Side-mounted glowing purple sedative canister with two physical mounts.
# - Purple crescent sedation emblem replaces the previous medical plus mark.
# - Low-poly handheld game asset intended for Godot.
#
# EXPORTED HIERARCHY
#   FTF_Tool_TranquilizerPistol_RoundPurple_v2
#   |-- FTF_Tool_TranquilizerPistol_RoundPurple_v2_Static
#   |-- ProjectileSpawnPoint
#   `-- SecondaryHandGrip
#
# ASSET STANDARD
# - Blender authoring/projectile direction: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip: (0, 0, 0)
# - ProjectileSpawnPoint is centred just beyond the muzzle
# - No cameras, lights, text or collision meshes
# - All visual meshes merge into one static mesh before export
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# -----------------------------------------------------------------------------
# PATHS / CONSTANTS
# -----------------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_tools")
OUTPUT_FILE = "FTF_Tool_TranquilizerPistol_RoundPurple_v2.glb"
SCRIPT_REVISION = "REV2_ROUNDED_BODY_AUDITED"

ROOT_NAME = "FTF_Tool_TranquilizerPistol_RoundPurple_v2"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

PROJECTILE_POINT_LOCATION = Vector((0.0, -1.075, 0.26))
SECONDARY_GRIP_LOCATION = Vector((0.0, -0.55, 0.02))


# -----------------------------------------------------------------------------
# SCENE / MATERIALS
# -----------------------------------------------------------------------------


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)



def configure_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0



def make_material(
    name,
    color,
    roughness=0.70,
    metallic=0.0,
    emission=None,
    emission_strength=0.0,
):
    material = bpy.data.materials.new(name)
    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    if emission is not None and emission_strength > 0.0:
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (*emission, 1.0)
        emit.inputs["Strength"].default_value = emission_strength
        links.new(emit.outputs["Emission"], output.inputs["Surface"])
    else:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    material.diffuse_color = (*color, 1.0)
    return material



def build_materials():
    return {
        "black": make_material(
            "MAT_TQ2_RubberBlack", (0.015, 0.018, 0.021), 0.86, 0.04
        ),
        "black_hard": make_material(
            "MAT_TQ2_HardBlack", (0.045, 0.052, 0.058), 0.58, 0.18
        ),
        "dark": make_material(
            "MAT_TQ2_DarkTechnical", (0.085, 0.095, 0.105), 0.62, 0.26
        ),
        "gunmetal": make_material(
            "MAT_TQ2_Gunmetal", (0.15, 0.165, 0.175), 0.42, 0.46
        ),
        "purple": make_material(
            "MAT_TQ2_SedativePurple", (0.50, 0.20, 0.72), 0.50, 0.08
        ),
        "lavender": make_material(
            "MAT_TQ2_LavenderShell", (0.73, 0.57, 0.92), 0.56, 0.05
        ),
        "purple_glow": make_material(
            "MAT_TQ2_PurpleGlow",
            (0.76, 0.43, 0.98),
            emission=(0.56, 0.18, 0.94),
            emission_strength=2.4,
        ),
        "bore": make_material(
            "MAT_TQ2_DeepBore", (0.002, 0.003, 0.004), 0.96, 0.02
        ),
    }


# -----------------------------------------------------------------------------
# OBJECT HELPERS
# -----------------------------------------------------------------------------


def get_or_create_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection



def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)



def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj



def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)



def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = False



def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True



def add_bevel(obj, width=0.01, segments=1):
    modifier = obj.modifiers.new("LowPolyBevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier



def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for modifier in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError as exc:
            print(f"[WARN] Could not apply {modifier.name} on {obj.name}: {exc}")



def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.22
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "TranquilizerPistol"
    root["visual_style"] = "RoundedMultiStageSedativeLauncher"
    root["projectile_payload"] = "SedationDart"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["projectile_spawn_node"] = "ProjectileSpawnPoint"
    root["secondary_hand_node"] = "SecondaryHandGrip"
    root["contains_medical_plus_symbol"] = False
    root["sedation_emblem"] = "PurpleCrescent"
    root["revision"] = SCRIPT_REVISION

    collection.objects.link(root)
    return root



def create_marker(name, location, root, collection, display_type, size):
    marker = bpy.data.objects.new(name, None)
    marker.empty_display_type = display_type
    marker.empty_display_size = size
    marker.location = location
    marker.parent = root
    collection.objects.link(marker)
    return marker



def create_runtime_markers(root, collection):
    projectile = create_marker(
        "ProjectileSpawnPoint",
        PROJECTILE_POINT_LOCATION,
        root,
        collection,
        "SINGLE_ARROW",
        0.12,
    )
    projectile.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    projectile["effect_role"] = "SedationDartOrigin"
    projectile["local_forward_axis"] = "-Y"

    secondary = create_marker(
        "SecondaryHandGrip",
        SECONDARY_GRIP_LOCATION,
        root,
        collection,
        "CUBE",
        0.08,
    )
    secondary["interaction_role"] = "OptionalSupportHandGrip"
    return projectile, secondary


# -----------------------------------------------------------------------------
# GEOMETRY HELPERS
# -----------------------------------------------------------------------------


def finish_object(
    obj,
    name,
    material,
    root,
    collection,
    bevel=0.0,
    smooth=False,
):
    obj.name = name
    assign_material(obj, material)
    if smooth:
        set_smooth_shading(obj)
    else:
        set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = root
    move_to_collection(obj, collection)
    return obj



def add_cube(
    name,
    location,
    dimensions,
    material,
    root,
    collection,
    bevel=0.0,
    rotation=(0.0, 0.0, 0.0),
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(
        obj,
        name,
        material,
        root,
        collection,
        bevel=bevel,
        smooth=False,
    )



def add_cylinder(
    name,
    location,
    radius,
    depth,
    material,
    root,
    collection,
    rotation=(0.0, 0.0, 0.0),
    vertices=16,
    bevel=0.0,
    smooth=True,
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return finish_object(
        bpy.context.object,
        name,
        material,
        root,
        collection,
        bevel=bevel,
        smooth=smooth,
    )



def add_cylinder_between(
    name,
    p0,
    p1,
    radius,
    material,
    root,
    collection,
    vertices=16,
    bevel=0.0,
    smooth=True,
):
    p0 = Vector(p0)
    p1 = Vector(p1)
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")

    midpoint = (p0 + p1) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    return add_cylinder(
        name,
        midpoint,
        radius,
        length,
        material,
        root,
        collection,
        rotation=rotation,
        vertices=vertices,
        bevel=bevel,
        smooth=smooth,
    )



def add_torus_x(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    root,
    collection,
    major_segments=20,
    minor_segments=6,
):
    # Torus axis along X, so the ring lies in the YZ plane.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=(0.0, math.radians(90.0), 0.0),
    )
    return finish_object(
        bpy.context.object,
        name,
        material,
        root,
        collection,
        smooth=True,
    )


# -----------------------------------------------------------------------------
# BUILD MODEL
# -----------------------------------------------------------------------------


def build_tranquilizer_pistol():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    materials = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    projectile_point, secondary_grip = create_runtime_markers(root, collection)

    # Rounded tilted grip. The upper end overlaps the grip neck, while the lower
    # cap overlaps the core by only a few millimetres to avoid visible clipping.
    add_cylinder_between(
        "Grip_RoundCore",
        (0.0, 0.105, -0.46),
        (0.0, -0.015, 0.055),
        0.125,
        materials["black"],
        root,
        collection,
        vertices=16,
        bevel=0.005,
    )
    add_cylinder_between(
        "Grip_LowerCap",
        (0.0, 0.116, -0.475),
        (0.0, 0.098, -0.405),
        0.140,
        materials["black_hard"],
        root,
        collection,
        vertices=16,
        bevel=0.004,
    )
    add_cylinder_between(
        "Grip_UpperNeck",
        (0.0, -0.020, 0.015),
        (0.0, -0.075, 0.155),
        0.135,
        materials["black_hard"],
        root,
        collection,
        vertices=16,
        bevel=0.004,
    )

    # Circular trigger guard replaces the box-like guard. It overlaps the grip
    # neck at the rear and the lower body connector at the top.
    add_torus_x(
        "TriggerGuard_Round",
        (0.0, -0.175, -0.005),
        0.125,
        0.024,
        materials["black_hard"],
        root,
        collection,
        major_segments=20,
        minor_segments=6,
    )
    add_cylinder_between(
        "Trigger_CurvedLever",
        (0.0, -0.185, 0.075),
        (0.0, -0.205, -0.055),
        0.023,
        materials["purple"],
        root,
        collection,
        vertices=12,
        bevel=0.003,
    )

    # Lower body bridge connects the circular body to the grip and trigger ring.
    add_cylinder_between(
        "Body_LowerBridge",
        (0.0, -0.10, 0.115),
        (0.0, -0.18, 0.235),
        0.145,
        materials["black_hard"],
        root,
        collection,
        vertices=16,
        bevel=0.004,
    )

    # Multi-stage rounded gun body. Adjacent axial sections overlap only
    # 6-10 mm, enough to avoid gaps after beveling without exposing large
    # intersecting rings on the outside.
    add_cylinder_between(
        "Body_RearControlChamber",
        (0.0, -0.075, 0.26),
        (0.0, -0.365, 0.26),
        0.170,
        materials["black_hard"],
        root,
        collection,
        vertices=18,
        bevel=0.004,
    )
    add_cylinder_between(
        "Body_MidPressureChamber",
        (0.0, -0.355, 0.26),
        (0.0, -0.675, 0.26),
        0.195,
        materials["dark"],
        root,
        collection,
        vertices=18,
        bevel=0.004,
    )
    add_cylinder_between(
        "Body_FrontEmitterTube",
        (0.0, -0.665, 0.26),
        (0.0, -0.915, 0.26),
        0.145,
        materials["black_hard"],
        root,
        collection,
        vertices=18,
        bevel=0.003,
    )
    add_cylinder_between(
        "Muzzle_BlackCollar",
        (0.0, -0.905, 0.26),
        (0.0, -1.005, 0.26),
        0.165,
        materials["black"],
        root,
        collection,
        vertices=20,
        bevel=0.003,
    )
    add_cylinder_between(
        "Muzzle_DeepBore",
        (0.0, -0.995, 0.26),
        (0.0, -1.060, 0.26),
        0.075,
        materials["bore"],
        root,
        collection,
        vertices=18,
        bevel=0.002,
    )

    # Narrow technical bands sit on radius transitions rather than cutting
    # into the body. Their axial placement is fully inside the larger-radius
    # chamber, preventing the old visible ring-through-body problem.
    add_cylinder_between(
        "Band_RearPurple",
        (0.0, -0.348, 0.26),
        (0.0, -0.375, 0.26),
        0.202,
        materials["purple"],
        root,
        collection,
        vertices=20,
        bevel=0.002,
    )
    add_cylinder_between(
        "Band_FrontGunmetal",
        (0.0, -0.650, 0.26),
        (0.0, -0.680, 0.26),
        0.202,
        materials["gunmetal"],
        root,
        collection,
        vertices=20,
        bevel=0.002,
    )

    # Small top status housing is embedded into the pressure chamber.
    add_cube(
        "Top_StatusHousing",
        (0.0, -0.49, 0.455),
        (0.18, 0.26, 0.075),
        materials["black_hard"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "Top_PurpleStatusLight",
        (0.0, -0.49, 0.497),
        (0.10, 0.12, 0.025),
        materials["purple_glow"],
        root,
        collection,
        bevel=0.005,
    )

    # Right-side sedative canister. It is separated from the body shell by a
    # visible gap and connected through two stout mounting bridges.
    add_cylinder_between(
        "Canister_MountRear",
        (0.155, -0.405, 0.26),
        (0.245, -0.405, 0.26),
        0.034,
        materials["gunmetal"],
        root,
        collection,
        vertices=12,
        bevel=0.003,
    )
    add_cylinder_between(
        "Canister_MountFront",
        (0.155, -0.610, 0.26),
        (0.245, -0.610, 0.26),
        0.034,
        materials["gunmetal"],
        root,
        collection,
        vertices=12,
        bevel=0.003,
    )
    add_cylinder(
        "Canister_OuterShell",
        (0.305, -0.507, 0.26),
        0.073,
        0.285,
        materials["lavender"],
        root,
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
        vertices=16,
        bevel=0.003,
    )
    add_cylinder(
        "Canister_GlowCore",
        (0.305, -0.507, 0.26),
        0.050,
        0.235,
        materials["purple_glow"],
        root,
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
        vertices=16,
        bevel=0.002,
    )
    add_cylinder(
        "Canister_RearCap",
        (0.305, -0.365, 0.26),
        0.083,
        0.035,
        materials["black_hard"],
        root,
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
        vertices=16,
        bevel=0.003,
    )
    add_cylinder(
        "Canister_FrontCap",
        (0.305, -0.649, 0.26),
        0.083,
        0.035,
        materials["black_hard"],
        root,
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
        vertices=16,
        bevel=0.003,
    )
    add_cylinder_between(
        "Canister_FeedLine",
        (0.232, -0.507, 0.310),
        (0.185, -0.507, 0.335),
        0.016,
        materials["purple"],
        root,
        collection,
        vertices=10,
        bevel=0.002,
    )

    # Left-side crescent emblem. Each layer is offset along X so no coplanar
    # surfaces are created. The black foreground disc masks part of the purple
    # disc to form a crescent without a Boolean modifier.
    add_cylinder(
        "Emblem_Backplate",
        (-0.197, -0.505, 0.26),
        0.078,
        0.020,
        materials["black"],
        root,
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=18,
        bevel=0.002,
    )
    add_cylinder(
        "Emblem_CrescentPurpleDisc",
        (-0.213, -0.505, 0.26),
        0.054,
        0.018,
        materials["purple_glow"],
        root,
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=18,
        bevel=0.002,
    )
    add_cylinder(
        "Emblem_CrescentMask",
        (-0.226, -0.491, 0.275),
        0.041,
        0.014,
        materials["black_hard"],
        root,
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=18,
        bevel=0.001,
    )

    return root, projectile_point, secondary_grip


# -----------------------------------------------------------------------------
# VALIDATION
# -----------------------------------------------------------------------------


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)



def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]



def get_mesh_by_name(name):
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Missing expected mesh: {name}")
    return obj



def world_bbox(obj):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = Vector(
        (
            min(p.x for p in points),
            min(p.y for p in points),
            min(p.z for p in points),
        )
    )
    high = Vector(
        (
            max(p.x for p in points),
            max(p.y for p in points),
            max(p.z for p in points),
        )
    )
    return low, high



def bbox_world_all(meshes):
    lows = []
    highs = []
    for obj in meshes:
        low, high = world_bbox(obj)
        lows.append(low)
        highs.append(high)
    combined_low = Vector(
        (
            min(v.x for v in lows),
            min(v.y for v in lows),
            min(v.z for v in lows),
        )
    )
    combined_high = Vector(
        (
            max(v.x for v in highs),
            max(v.y for v in highs),
            max(v.z for v in highs),
        )
    )
    return combined_low, combined_high



def aabb_distance(obj_a, obj_b):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)
    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)



def axis_overlap(obj_a, obj_b, axis):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)
    return min(a_max[axis], b_max[axis]) - max(a_min[axis], b_min[axis])



def validate_attachment_pairs():
    # Parts in this table must touch or overlap by design. A 6 mm maximum gap
    # catches visible floating components while allowing tiny bevel tolerances.
    pairs = [
        ("Grip_RoundCore", "Grip_LowerCap", 0.006),
        ("Grip_RoundCore", "Grip_UpperNeck", 0.006),
        ("Grip_UpperNeck", "Body_LowerBridge", 0.006),
        ("TriggerGuard_Round", "Grip_UpperNeck", 0.006),
        ("TriggerGuard_Round", "Body_LowerBridge", 0.006),
        ("Trigger_CurvedLever", "TriggerGuard_Round", 0.006),
        ("Body_LowerBridge", "Body_RearControlChamber", 0.006),
        ("Body_RearControlChamber", "Body_MidPressureChamber", 0.006),
        ("Body_MidPressureChamber", "Body_FrontEmitterTube", 0.006),
        ("Body_FrontEmitterTube", "Muzzle_BlackCollar", 0.006),
        ("Muzzle_BlackCollar", "Muzzle_DeepBore", 0.006),
        ("Band_RearPurple", "Body_MidPressureChamber", 0.006),
        ("Band_FrontGunmetal", "Body_MidPressureChamber", 0.006),
        ("Top_StatusHousing", "Body_MidPressureChamber", 0.006),
        ("Top_PurpleStatusLight", "Top_StatusHousing", 0.006),
        ("Canister_MountRear", "Body_MidPressureChamber", 0.006),
        ("Canister_MountFront", "Body_MidPressureChamber", 0.006),
        ("Canister_MountRear", "Canister_OuterShell", 0.006),
        ("Canister_MountFront", "Canister_OuterShell", 0.006),
        ("Canister_GlowCore", "Canister_OuterShell", 0.006),
        ("Canister_RearCap", "Canister_OuterShell", 0.006),
        ("Canister_FrontCap", "Canister_OuterShell", 0.006),
        ("Canister_FeedLine", "Body_MidPressureChamber", 0.006),
        ("Canister_FeedLine", "Canister_OuterShell", 0.006),
        ("Emblem_Backplate", "Body_MidPressureChamber", 0.006),
        ("Emblem_CrescentPurpleDisc", "Emblem_Backplate", 0.006),
        ("Emblem_CrescentMask", "Emblem_CrescentPurpleDisc", 0.006),
    ]

    failures = []
    for first_name, second_name, allowed_gap in pairs:
        first = get_mesh_by_name(first_name)
        second = get_mesh_by_name(second_name)
        distance = aabb_distance(first, second)
        if distance > allowed_gap:
            failures.append(
                f"{first_name} -> {second_name}: gap {distance:.4f} m "
                f"> allowed {allowed_gap:.4f} m"
            )

    if failures:
        raise RuntimeError(
            "FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures)
        )
    print(f"[VALID] Attachment audit passed: {len(pairs)} checks.")



def validate_clearances():
    # These checks target the specific visible clipping risks in this design.
    failures = []

    body = get_mesh_by_name("Body_MidPressureChamber")
    canister = get_mesh_by_name("Canister_OuterShell")
    canister_gap = aabb_distance(body, canister)
    if canister_gap < 0.025:
        failures.append(
            f"Canister clearance too small: {canister_gap:.4f} m < 0.0250 m"
        )
    if canister_gap > 0.045:
        failures.append(
            f"Canister too far from body: {canister_gap:.4f} m > 0.0450 m"
        )

    # Bands must remain narrow along the barrel axis. A wider band could read as
    # a black/purple ring cutting through the neighbouring shell.
    for band_name in ("Band_RearPurple", "Band_FrontGunmetal"):
        band = get_mesh_by_name(band_name)
        low, high = world_bbox(band)
        axial_width = high.y - low.y
        if axial_width > 0.035:
            failures.append(
                f"{band_name} axial width {axial_width:.4f} m exceeds 0.0350 m"
            )

    # The crescent layers must be ordered outward on negative X with no coplanar
    # faces. This prevents flickering / z-fighting after GLB export.
    back = get_mesh_by_name("Emblem_Backplate")
    purple = get_mesh_by_name("Emblem_CrescentPurpleDisc")
    mask = get_mesh_by_name("Emblem_CrescentMask")
    back_min, back_max = world_bbox(back)
    purple_min, purple_max = world_bbox(purple)
    mask_min, mask_max = world_bbox(mask)
    if not (mask_max.x < purple_max.x < back_max.x):
        failures.append("Emblem layers are not ordered outward along negative X.")
    if abs(mask_max.x - purple_max.x) < 0.002:
        failures.append("Crescent mask is nearly coplanar with purple disc.")
    if abs(purple_max.x - back_max.x) < 0.002:
        failures.append("Purple crescent is nearly coplanar with backplate.")

    # Trigger must stay inside the circular guard rather than intersecting its
    # outer side walls. Bounding extents provide a conservative safety check.
    guard = get_mesh_by_name("TriggerGuard_Round")
    trigger = get_mesh_by_name("Trigger_CurvedLever")
    guard_min, guard_max = world_bbox(guard)
    trigger_min, trigger_max = world_bbox(trigger)
    if trigger_min.y <= guard_min.y or trigger_max.y >= guard_max.y:
        failures.append("Trigger extends through the circular guard along Y.")
    if trigger_min.z <= guard_min.z or trigger_max.z >= guard_max.z:
        failures.append("Trigger extends through the circular guard along Z.")

    # Muzzle bore must remain fully inside the black muzzle collar in X/Z.
    collar = get_mesh_by_name("Muzzle_BlackCollar")
    bore = get_mesh_by_name("Muzzle_DeepBore")
    collar_min, collar_max = world_bbox(collar)
    bore_min, bore_max = world_bbox(bore)
    margin_x = min(bore_min.x - collar_min.x, collar_max.x - bore_max.x)
    margin_z = min(bore_min.z - collar_min.z, collar_max.z - bore_max.z)
    if margin_x < 0.025 or margin_z < 0.025:
        failures.append(
            f"Muzzle bore containment margin too small: X={margin_x:.4f}, "
            f"Z={margin_z:.4f}"
        )

    if failures:
        raise RuntimeError(
            "CLIPPING / CLEARANCE AUDIT FAILED:\n- " + "\n- ".join(failures)
        )
    print("[VALID] Clipping and clearance audit passed.")



def validate_before_merge(root, projectile_point, secondary_grip):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Root must remain an Empty at primary hand grip origin.")
    if projectile_point.parent != root or secondary_grip.parent != root:
        raise RuntimeError("Runtime marker hierarchy is invalid.")
    if (projectile_point.location - PROJECTILE_POINT_LOCATION).length > 0.0001:
        raise RuntimeError("ProjectileSpawnPoint moved away from muzzle centre.")
    if (secondary_grip.location - SECONDARY_GRIP_LOCATION).length > 0.0001:
        raise RuntimeError("SecondaryHandGrip moved away from intended location.")

    forbidden = [
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type in {"CAMERA", "LIGHT"}
    ]
    if forbidden:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(forbidden))

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes under tranquilizer pistol root.")

    failures = []
    for obj in meshes:
        lowered = obj.name.lower()
        if lowered.startswith("ucx") or "collision" in lowered:
            failures.append("collision-like mesh: " + obj.name)
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale: " + obj.name)
    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    validate_attachment_pairs()
    validate_clearances()

    low, high = bbox_world_all(meshes)
    dimensions = high - low
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)

    print(
        f"[VALID BEFORE MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x "
        f"{dimensions.z:.2f} m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Floating-part audit: PASSED\n"
        f"  Clipping/clearance audit: PASSED\n"
        f"  ProjectileSpawnPoint: "
        f"{tuple(round(v, 3) for v in projectile_point.location)}\n"
        f"  SecondaryHandGrip: "
        f"{tuple(round(v, 3) for v in secondary_grip.location)}\n"
    )


# -----------------------------------------------------------------------------
# MERGE / EXPORT
# -----------------------------------------------------------------------------


def merge_static_meshes(root):
    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes available for merge.")

    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = ROOT_NAME + "_Static"
    merged.parent = root
    set_flat_shading(merged)
    return merged



def validate_after_merge(root, projectile_point, secondary_grip):
    meshes = get_meshes_under_root(root)
    if len(meshes) != 1 or meshes[0].name != ROOT_NAME + "_Static":
        raise RuntimeError("Expected one merged tranquilizer pistol visual mesh.")
    if projectile_point.parent != root or secondary_grip.parent != root:
        raise RuntimeError("Runtime marker hierarchy damaged after merge.")

    low, high = bbox_world_all(meshes)
    dimensions = high - low
    meshes[0].data.calc_loop_triangles()
    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x "
        f"{dimensions.z:.2f} m\n"
        f"  Visual meshes: 1\n"
        f"  Triangles: {len(meshes[0].data.loop_triangles)}\n"
        f"  ProjectileSpawnPoint preserved: {projectile_point.name}\n"
        f"  SecondaryHandGrip preserved: {secondary_grip.name}\n"
    )



def select_for_export(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root



def export_glb(root, filepath):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    select_for_export(root)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print(f"[EXPORT] {filepath}")


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------


def main():
    print(f"\n=== Generating Rounded Tranquilizer Pistol [{SCRIPT_REVISION}] ===\n")
    root, projectile_point, secondary_grip = build_tranquilizer_pistol()
    validate_before_merge(root, projectile_point, secondary_grip)

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_after_merge(root, projectile_point, secondary_grip)
    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("Godot nodes:")
    print(" - ProjectileSpawnPoint: spawn sedative dart here.")
    print(" - SecondaryHandGrip: optional support-hand IK target.")


if __name__ == "__main__":
    main()
