# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Handheld Medicine Cannon
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_MedicineCannon_RedWhite_v1.glb
#
# DESIGN
# - Chunky shoulder-supported medicine projectile cannon
# - Red and white body with black grips and a large circular black muzzle
# - Green medicine indicators and a GREEN medical cross only
# - No red cross artwork
# - No fertilizer tank, chili-fluid tank, hose, pressure gauge or spray cone
# - Large cylindrical barrel and octagonal medicine loading chamber make this
#   visually distinct from the fertilizer injector and chili marker sprayer
# - Revision: positive-X medical markings; rear black lock ring clearance fixed
#
# EXPORTED HIERARCHY
#   FTF_Tool_MedicineCannon_RedWhite_v1
#   |-- FTF_Tool_MedicineCannon_RedWhite_v1_Static
#   |-- ProjectileSpawnPoint
#   `-- SecondaryHandGrip
#
# ASSET STANDARD
# - Blender authoring/projectile direction: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip: (0, 0, 0)
# - ProjectileSpawnPoint is centred just beyond the black muzzle
# - SecondaryHandGrip marks the front support-hand position
# - No cameras, lights, text or collision meshes
# - All visual meshes merge into one static mesh before export
#
# Run:
#   blender --background --factory-startup --python medicine_cannon.py
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
OUTPUT_FILE = "FTF_Tool_MedicineCannon_RedWhite_v1.glb"

ROOT_NAME = "FTF_Tool_MedicineCannon_RedWhite_v1"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

PROJECTILE_POINT_LOCATION = Vector((0.0, -2.09, 0.58))
SECONDARY_GRIP_LOCATION = Vector((0.0, -1.08, -0.02))


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
    roughness=0.75,
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
        "red": make_material(
            "MAT_MC_MedicineRed", (0.72, 0.025, 0.020), 0.60, 0.12
        ),
        "red_dark": make_material(
            "MAT_MC_DeepRedArmor", (0.32, 0.012, 0.012), 0.70, 0.20
        ),
        "white": make_material(
            "MAT_MC_MedicalWhite", (0.88, 0.90, 0.88), 0.56, 0.16
        ),
        "white_alt": make_material(
            "MAT_MC_WarmWhitePanels", (0.70, 0.73, 0.71), 0.64, 0.22
        ),
        "black": make_material(
            "MAT_MC_BlackMuzzleAndGrip", (0.010, 0.012, 0.014), 0.84, 0.16
        ),
        "bore": make_material(
            "MAT_MC_DeepBlackBore", (0.002, 0.003, 0.004), 0.94, 0.04
        ),
        "gunmetal": make_material(
            "MAT_MC_DarkGunmetal", (0.11, 0.13, 0.14), 0.50, 0.48
        ),
        "green": make_material(
            "MAT_MC_MedicineGreen", (0.08, 0.56, 0.16), 0.56, 0.04
        ),
        "green_glow": make_material(
            "MAT_MC_GlowingMedicineGreen",
            (0.08, 0.95, 0.24),
            emission=(0.035, 0.82, 0.14),
            emission_strength=2.2,
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
    root.empty_display_size = 0.30
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "MedicineCannon"
    root["visual_style"] = "ShoulderSupportedCylindricalCannon"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "PrimaryHandGrip"
    root["projectile_spawn_node"] = "ProjectileSpawnPoint"
    root["secondary_hand_node"] = "SecondaryHandGrip"
    root["medical_cross_color"] = "Green"
    root["contains_red_cross"] = False
    root["has_collision_mesh"] = False
    root["effects_baked_into_model"] = False

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
        0.15,
    )
    # Empty arrows point +Z by default; +90 degrees around X maps +Z to -Y.
    projectile.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    projectile["effect_role"] = "MedicineProjectileOrigin"
    projectile["local_forward_axis"] = "-Y"

    secondary = create_marker(
        "SecondaryHandGrip",
        SECONDARY_GRIP_LOCATION,
        root,
        collection,
        "CUBE",
        0.10,
    )
    secondary["interaction_role"] = "SupportHandGrip"
    return projectile, secondary


# -----------------------------------------------------------------------------
# GEOMETRY HELPERS
# -----------------------------------------------------------------------------

def finish_object(obj, name, material, root, collection, bevel=0.0):
    obj.name = name
    assign_material(obj, material)
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
    return finish_object(obj, name, material, root, collection, bevel)


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
):
    p0 = Vector(p0)
    p1 = Vector(p1)
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")

    midpoint = (p0 + p1) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        location=midpoint,
        rotation=rotation,
    )
    return finish_object(
        bpy.context.object, name, material, root, collection, bevel
    )


def add_torus_y(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    root,
    collection,
):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=20,
        minor_segments=6,
        location=location,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    return finish_object(bpy.context.object, name, material, root, collection)


# -----------------------------------------------------------------------------
# BUILD MEDICINE CANNON
# -----------------------------------------------------------------------------

def build_medicine_cannon():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    materials = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    projectile_point, secondary_grip = create_runtime_markers(root, collection)

    # Primary grip and trigger group.
    add_cube(
        "PrimaryGrip_BlackCore",
        (0.0, 0.02, -0.31),
        (0.34, 0.38, 0.92),
        materials["black"],
        root,
        collection,
        bevel=0.036,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "PrimaryGrip_RedBackPlate",
        (0.0, 0.16, -0.27),
        (0.42, 0.11, 0.82),
        materials["red_dark"],
        root,
        collection,
        bevel=0.020,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "PrimaryGrip_WhiteSocket",
        (0.0, -0.04, 0.31),
        (0.66, 0.50, 0.48),
        materials["white"],
        root,
        collection,
        bevel=0.046,
    )
    add_cube(
        "TriggerGuard_Rear",
        (0.0, -0.18, -0.03),
        (0.48, 0.12, 0.33),
        materials["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "TriggerGuard_Front",
        (0.0, -0.42, 0.05),
        (0.48, 0.12, 0.48),
        materials["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "TriggerGuard_Bottom",
        (0.0, -0.30, -0.19),
        (0.46, 0.34, 0.10),
        materials["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "Trigger_GreenDoseLever",
        (0.0, -0.24, -0.07),
        (0.16, 0.09, 0.28),
        materials["green"],
        root,
        collection,
        bevel=0.022,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )

    # Rear receiver and shoulder stock.
    # Keep the rear white receiver behind the chamber lock ring.  The old
    # 0.72 m-long housing extended to Y=-0.63 and swallowed the black torus at
    # Y=-0.43, producing visible z-fighting/intersection after export.
    add_cube(
        "Receiver_WhiteRearHousing",
        (0.0, -0.20, 0.58),
        (0.76, 0.48, 0.62),
        materials["white"],
        root,
        collection,
        bevel=0.060,
    )
    add_cube(
        "Stock_RedShoulderBeam",
        (0.0, 0.40, 0.43),
        (0.58, 0.72, 0.30),
        materials["red"],
        root,
        collection,
        bevel=0.050,
    )
    add_cube(
        "Stock_WhiteCore",
        (0.0, 0.47, 0.43),
        (0.38, 0.52, 0.18),
        materials["white_alt"],
        root,
        collection,
        bevel=0.032,
    )
    add_cube(
        "Stock_BlackShoulderPad",
        (0.0, 0.77, 0.43),
        (0.62, 0.13, 0.44),
        materials["black"],
        root,
        collection,
        bevel=0.040,
    )

    # Large white cylindrical cannon body.
    add_cylinder_between(
        "Barrel_WhiteMainCylinder",
        (0.0, -0.30, 0.58),
        (0.0, -1.54, 0.58),
        0.31,
        materials["white"],
        root,
        collection,
        vertices=18,
        bevel=0.006,
    )
    add_cube(
        "Barrel_RedTopArmorSpine",
        (0.0, -1.08, 0.875),
        (0.46, 0.90, 0.16),
        materials["red"],
        root,
        collection,
        bevel=0.026,
    )
    add_cube(
        "Barrel_RedBottomArmorRail",
        (0.0, -1.06, 0.285),
        (0.46, 0.82, 0.14),
        materials["red_dark"],
        root,
        collection,
        bevel=0.020,
    )

    # Octagonal medicine loading chamber surrounds the barrel midsection.
    add_cylinder_between(
        "Chamber_RedOctagonalLoader",
        (0.0, -0.42, 0.58),
        (0.0, -0.88, 0.58),
        0.43,
        materials["red"],
        root,
        collection,
        vertices=8,
        bevel=0.008,
    )
    # The rear lock ring now sits fully in front of the shortened receiver,
    # with a small visible clearance instead of intersecting the white body.
    add_torus_y(
        "Chamber_BlackRearLockRing",
        (0.0, -0.485, 0.58),
        0.405,
        0.032,
        materials["black"],
        root,
        collection,
    )
    add_torus_y(
        "Chamber_WhiteFrontLockRing",
        (0.0, -0.87, 0.58),
        0.405,
        0.032,
        materials["white_alt"],
        root,
        collection,
    )
    add_cube(
        "Chamber_WhiteLeftArmor",
        (-0.39, -0.69, 0.58),
        (0.11, 0.30, 0.48),
        materials["white"],
        root,
        collection,
        bevel=0.026,
    )
    add_cube(
        "Chamber_WhiteRightArmor",
        (0.39, -0.69, 0.58),
        (0.11, 0.30, 0.48),
        materials["white"],
        root,
        collection,
        bevel=0.026,
    )

    # Green medicine status windows are on the positive-X side, matching
    # the medicine pistol's readable/detail side.
    for index, y in enumerate((-0.60, -0.69, -0.78)):
        add_cube(
            f"Chamber_GreenDoseWindow_{index:02d}",
            (0.452, y, 0.60),
            (0.035, 0.080, 0.14),
            materials["green_glow"],
            root,
            collection,
            bevel=0.010,
        )

    # Large circular BLACK cannon muzzle.
    add_cylinder_between(
        "Muzzle_RedArmorCollar",
        (0.0, -1.48, 0.58),
        (0.0, -1.66, 0.58),
        0.37,
        materials["red_dark"],
        root,
        collection,
        vertices=20,
        bevel=0.004,
    )
    add_torus_y(
        "Muzzle_WhiteTrimRing",
        (0.0, -1.64, 0.58),
        0.365,
        0.040,
        materials["white"],
        root,
        collection,
    )
    add_cylinder_between(
        "Muzzle_BlackOuterCannon",
        (0.0, -1.62, 0.58),
        (0.0, -1.94, 0.58),
        0.39,
        materials["black"],
        root,
        collection,
        vertices=22,
        bevel=0.006,
    )
    add_torus_y(
        "Muzzle_GreenDoseRing",
        (0.0, -1.94, 0.58),
        0.300,
        0.022,
        materials["green"],
        root,
        collection,
    )
    add_cylinder_between(
        "Muzzle_DeepBlackBore",
        (0.0, -1.93, 0.58),
        (0.0, -2.065, 0.58),
        0.265,
        materials["bore"],
        root,
        collection,
        vertices=22,
        bevel=0.002,
    )

    # Forward support grip for two-handed cannon use.
    add_cube(
        "ForwardGrip_RedMount",
        (0.0, -1.08, 0.27),
        (0.38, 0.32, 0.18),
        materials["red"],
        root,
        collection,
        bevel=0.022,
    )
    add_cube(
        "ForwardGrip_BlackCore",
        (0.0, -1.08, -0.02),
        (0.30, 0.30, 0.58),
        materials["black"],
        root,
        collection,
        bevel=0.036,
        rotation=(math.radians(5.0), 0.0, 0.0),
    )
    for index, z in enumerate((-0.17, -0.02, 0.13)):
        add_cube(
            f"ForwardGrip_RedGroove_{index:02d}",
            (0.0, -1.235, z),
            (0.24, 0.025, 0.035),
            materials["red_dark"],
            root,
            collection,
            bevel=0.004,
        )

    # GREEN medical cross on the positive-X detail side. No red cross is created.
    add_cube(
        "MedicalCross_GreenVertical",
        (0.392, -0.23, 0.60),
        (0.035, 0.075, 0.27),
        materials["green"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "MedicalCross_GreenHorizontal",
        (0.394, -0.23, 0.60),
        (0.038, 0.25, 0.085),
        materials["green"],
        root,
        collection,
        bevel=0.006,
    )

    # Rear/top details attached to receiver and barrel spine.
    add_cube(
        "Receiver_RedRearPlate",
        (0.0, 0.065, 0.60),
        (0.58, 0.070, 0.40),
        materials["red"],
        root,
        collection,
        bevel=0.016,
    )
    add_cube(
        "TopSight_BlackRear",
        (0.0, -0.18, 0.925),
        (0.20, 0.14, 0.10),
        materials["black"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "TopSight_GreenFront",
        (0.0, -1.40, 0.960),
        (0.12, 0.12, 0.10),
        materials["green_glow"],
        root,
        collection,
        bevel=0.010,
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
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def bbox_world_all(meshes):
    lows = []
    highs = []
    for obj in meshes:
        low, high = world_bbox(obj)
        lows.append(low)
        highs.append(high)
    combined_low = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
    combined_high = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
    return combined_low, combined_high


def aabb_distance(obj_a, obj_b):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)
    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def validate_clearance_pairs():
    """Ensure parts that must remain visually separate do not intersect."""
    pairs = [
        ("Chamber_BlackRearLockRing", "Receiver_WhiteRearHousing", 0.008),
        ("Chamber_BlackRearLockRing", "Chamber_WhiteLeftArmor", 0.008),
        ("Chamber_BlackRearLockRing", "Chamber_WhiteRightArmor", 0.008),
    ]

    failures = []
    for first_name, second_name, required_clearance in pairs:
        first = get_mesh_by_name(first_name)
        second = get_mesh_by_name(second_name)
        distance = aabb_distance(first, second)
        if distance < required_clearance:
            failures.append(
                f"{first_name} <-> {second_name}: clearance {distance:.4f} m "
                f"< required {required_clearance:.4f} m"
            )

    if failures:
        raise RuntimeError("INTERSECTION/CLEARANCE AUDIT FAILED:\n- " + "\n- ".join(failures))
    print(f"[VALID] Clearance audit passed: {len(pairs)} checks.")


def validate_attachment_pairs():
    pairs = [
        ("PrimaryGrip_BlackCore", "PrimaryGrip_WhiteSocket", 0.06),
        ("PrimaryGrip_RedBackPlate", "PrimaryGrip_BlackCore", 0.04),
        ("PrimaryGrip_WhiteSocket", "Receiver_WhiteRearHousing", 0.05),
        ("TriggerGuard_Rear", "PrimaryGrip_WhiteSocket", 0.05),
        ("TriggerGuard_Front", "Receiver_WhiteRearHousing", 0.06),
        ("TriggerGuard_Bottom", "TriggerGuard_Rear", 0.05),
        ("Trigger_GreenDoseLever", "TriggerGuard_Rear", 0.08),
        ("Stock_RedShoulderBeam", "Receiver_WhiteRearHousing", 0.04),
        ("Stock_WhiteCore", "Stock_RedShoulderBeam", 0.03),
        ("Stock_BlackShoulderPad", "Stock_RedShoulderBeam", 0.04),
        ("Barrel_WhiteMainCylinder", "Receiver_WhiteRearHousing", 0.04),
        ("Barrel_RedTopArmorSpine", "Barrel_WhiteMainCylinder", 0.04),
        ("Barrel_RedBottomArmorRail", "Barrel_WhiteMainCylinder", 0.04),
        ("Chamber_RedOctagonalLoader", "Barrel_WhiteMainCylinder", 0.03),
        ("Chamber_BlackRearLockRing", "Chamber_RedOctagonalLoader", 0.04),
        ("Chamber_WhiteFrontLockRing", "Chamber_RedOctagonalLoader", 0.04),
        ("Chamber_WhiteLeftArmor", "Chamber_RedOctagonalLoader", 0.04),
        ("Chamber_WhiteRightArmor", "Chamber_RedOctagonalLoader", 0.04),
        ("Chamber_GreenDoseWindow_00", "Chamber_WhiteRightArmor", 0.03),
        ("Chamber_GreenDoseWindow_01", "Chamber_WhiteRightArmor", 0.03),
        ("Chamber_GreenDoseWindow_02", "Chamber_WhiteRightArmor", 0.03),
        ("Muzzle_RedArmorCollar", "Barrel_WhiteMainCylinder", 0.04),
        ("Muzzle_BlackOuterCannon", "Muzzle_RedArmorCollar", 0.04),
        ("Muzzle_WhiteTrimRing", "Muzzle_BlackOuterCannon", 0.04),
        ("Muzzle_GreenDoseRing", "Muzzle_BlackOuterCannon", 0.04),
        ("Muzzle_DeepBlackBore", "Muzzle_BlackOuterCannon", 0.04),
        ("ForwardGrip_RedMount", "Barrel_RedBottomArmorRail", 0.04),
        ("ForwardGrip_BlackCore", "ForwardGrip_RedMount", 0.04),
        ("MedicalCross_GreenVertical", "Receiver_WhiteRearHousing", 0.04),
        ("MedicalCross_GreenHorizontal", "Receiver_WhiteRearHousing", 0.04),
        ("Receiver_RedRearPlate", "Receiver_WhiteRearHousing", 0.04),
        ("TopSight_BlackRear", "Receiver_WhiteRearHousing", 0.04),
        ("TopSight_GreenFront", "Barrel_RedTopArmorSpine", 0.04),
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
        raise RuntimeError("FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures))
    print(f"[VALID] Attachment audit passed: {len(pairs)} checks.")


def validate_before_merge(root, projectile_point, secondary_grip):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Root must remain an Empty at primary hand grip origin.")
    if projectile_point.parent != root or secondary_grip.parent != root:
        raise RuntimeError("Runtime marker hierarchy is invalid.")
    if (projectile_point.location - PROJECTILE_POINT_LOCATION).length > 0.0001:
        raise RuntimeError("ProjectileSpawnPoint moved away from muzzle centre.")
    if (secondary_grip.location - SECONDARY_GRIP_LOCATION).length > 0.0001:
        raise RuntimeError("SecondaryHandGrip moved away from forward grip.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(bad_scene))

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes under medicine cannon root.")

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

    red_crosses = [
        obj.name for obj in meshes
        if "cross" in obj.name.lower()
        and any(
            material is not None and "Red" in material.name
            for material in obj.data.materials
        )
    ]
    if red_crosses:
        raise RuntimeError("Red medical cross geometry is forbidden: " + ", ".join(red_crosses))

    validate_attachment_pairs()
    validate_clearance_pairs()
    low, high = bbox_world_all(meshes)
    dimensions = high - low

    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)

    print(
        f"[VALID BEFORE MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Medical cross: GREEN only\n"
        f"  ProjectileSpawnPoint: {tuple(round(v, 3) for v in projectile_point.location)}\n"
        f"  SecondaryHandGrip: {tuple(round(v, 3) for v in secondary_grip.location)}\n"
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
        raise RuntimeError("Expected one merged medicine cannon visual mesh.")
    if projectile_point.parent != root or secondary_grip.parent != root:
        raise RuntimeError("Runtime marker hierarchy damaged after merge.")

    low, high = bbox_world_all(meshes)
    dimensions = high - low
    meshes[0].data.calc_loop_triangles()
    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
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
    print("\n=== Generating Handheld Medicine Cannon ===\n")
    root, projectile_point, secondary_grip = build_medicine_cannon()
    validate_before_merge(root, projectile_point, secondary_grip)

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_after_merge(root, projectile_point, secondary_grip)
    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nGodot nodes:")
    print(" - ProjectileSpawnPoint: spawn medicine projectile or RPC effect here.")
    print(" - SecondaryHandGrip: optional support-hand IK target.")
    print(" - Green medical cross only; no red cross geometry is generated.")


if __name__ == "__main__":
    main()
