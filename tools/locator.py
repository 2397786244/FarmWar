# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Rider Vehicle Locator Launcher
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_VehicleLocatorLauncher_White_v2.glb
#
# DESIGN
# - Small handheld launcher used by the Rider role to fire vehicle locator tags.
# - Predominantly white body with black grip and dark technical components.
# - Compact silhouette: more like a locator dart launcher / tagging tool than a
#   firearm or grenade launcher.
# - Blue tracking lights and a small orange beacon accent help communicate the
#   locator / tracking function.
# - Low-poly / stylized game asset intended for Godot.
#
# EXPORTED HIERARCHY
#   FTF_Tool_VehicleLocatorLauncher_White_v2
#   |-- FTF_Tool_VehicleLocatorLauncher_White_v2_Static
#   |-- ProjectileSpawnPoint
#   `-- SecondaryHandGrip
#
# ASSET STANDARD
# - Blender authoring/projectile direction: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip: (0, 0, 0)
# - ProjectileSpawnPoint is centred just beyond the front emitter muzzle
# - SecondaryHandGrip marks the optional support-hand position
# - No cameras, lights, text or collision meshes
# - All visual meshes merge into one static mesh before export
#
# Run:
#   blender --background --factory-startup --python vehicle_locator_launcher_white.py
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
OUTPUT_FILE = "FTF_Tool_VehicleLocatorLauncher_White_v2.glb"
SCRIPT_REVISION = "REV2_TOP_PARTS_ATTACHED"

ROOT_NAME = "FTF_Tool_VehicleLocatorLauncher_White_v2"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

PROJECTILE_POINT_LOCATION = Vector((0.0, -1.08, 0.36))
SECONDARY_GRIP_LOCATION = Vector((0.0, -0.52, -0.05))


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
        "white": make_material(
            "MAT_VL_CleanWhite", (0.89, 0.90, 0.92), 0.54, 0.14
        ),
        "white_alt": make_material(
            "MAT_VL_SoftWhite", (0.76, 0.78, 0.82), 0.62, 0.18
        ),
        "black": make_material(
            "MAT_VL_BlackGrip", (0.02, 0.023, 0.026), 0.86, 0.08
        ),
        "gunmetal": make_material(
            "MAT_VL_Gunmetal", (0.11, 0.13, 0.15), 0.46, 0.48
        ),
        "dark": make_material(
            "MAT_VL_DarkTech", (0.08, 0.09, 0.10), 0.68, 0.24
        ),
        "blue_glow": make_material(
            "MAT_VL_BlueGlow",
            (0.26, 0.78, 0.97),
            emission=(0.08, 0.48, 0.95),
            emission_strength=2.0,
        ),
        "orange_glow": make_material(
            "MAT_VL_OrangeBeacon",
            (0.96, 0.62, 0.18),
            emission=(0.98, 0.42, 0.04),
            emission_strength=2.0,
        ),
        "core": make_material(
            "MAT_VL_CoreBlack", (0.002, 0.003, 0.004), 0.95, 0.03
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
    root.empty_display_size = 0.25
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "HandheldTool"
    root["role_owner"] = "Rider"
    root["tool_category"] = "VehicleLocatorLauncher"
    root["visual_style"] = "CompactWhiteLocatorTool"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "PrimaryHandGrip"
    root["projectile_spawn_node"] = "ProjectileSpawnPoint"
    root["secondary_hand_node"] = "SecondaryHandGrip"
    root["fires_payload"] = "VehicleLocatorTag"
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
        0.12,
    )
    projectile.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    projectile["effect_role"] = "VehicleLocatorProjectileOrigin"
    projectile["local_forward_axis"] = "-Y"

    secondary = create_marker(
        "SecondaryHandGrip",
        SECONDARY_GRIP_LOCATION,
        root,
        collection,
        "CUBE",
        0.09,
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
# BUILD TOOL
# -----------------------------------------------------------------------------


def build_vehicle_locator_launcher():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    materials = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    projectile_point, secondary_grip = create_runtime_markers(root, collection)

    # Primary grip and trigger area.
    add_cube(
        "Grip_BlackPrimary",
        (0.0, 0.02, -0.22),
        (0.20, 0.24, 0.66),
        materials["black"],
        root,
        collection,
        bevel=0.024,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_WhiteBackstrap",
        (0.0, 0.10, -0.18),
        (0.24, 0.09, 0.56),
        materials["white_alt"],
        root,
        collection,
        bevel=0.014,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )
    add_cube(
        "Frame_WhiteTriggerBlock",
        (0.0, -0.05, 0.10),
        (0.34, 0.42, 0.24),
        materials["white"],
        root,
        collection,
        bevel=0.026,
    )
    add_cube(
        "TriggerGuard_BlackRear",
        (0.0, -0.16, -0.01),
        (0.28, 0.09, 0.20),
        materials["black"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "TriggerGuard_BlackFront",
        (0.0, -0.27, 0.02),
        (0.28, 0.09, 0.28),
        materials["black"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "TriggerGuard_BlackBottom",
        (0.0, -0.22, -0.11),
        (0.26, 0.22, 0.07),
        materials["black"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "Trigger_Dark",
        (0.0, -0.17, -0.03),
        (0.08, 0.04, 0.16),
        materials["dark"],
        root,
        collection,
        bevel=0.008,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )

    # Main white body, compact and friendly rather than weapon-like.
    add_cube(
        "Body_WhiteMain",
        (0.0, -0.25, 0.35),
        (0.34, 0.86, 0.34),
        materials["white"],
        root,
        collection,
        bevel=0.030,
    )
    add_cube(
        "Body_WhiteTopShell",
        (0.0, -0.30, 0.55),
        (0.28, 0.68, 0.14),
        materials["white_alt"],
        root,
        collection,
        bevel=0.018,
    )
    add_cube(
        "Body_GunmetalLeftPanel",
        (-0.18, -0.22, 0.35),
        (0.06, 0.56, 0.20),
        materials["gunmetal"],
        root,
        collection,
        bevel=0.008,
    )
    add_cube(
        "Body_GunmetalRightPanel",
        (0.18, -0.22, 0.35),
        (0.06, 0.56, 0.20),
        materials["gunmetal"],
        root,
        collection,
        bevel=0.008,
    )

    # Rear locator battery / signal pack.
    add_cube(
        "RearPack_WhiteBattery",
        (0.0, 0.20, 0.36),
        (0.24, 0.26, 0.28),
        materials["white_alt"],
        root,
        collection,
        bevel=0.016,
    )
    add_cube(
        "RearPack_OrangeBeacon",
        (0.0, 0.20, 0.51),
        (0.12, 0.12, 0.08),
        materials["orange_glow"],
        root,
        collection,
        bevel=0.010,
    )

    # Mid-body locator chamber.
    add_cylinder_between(
        "Chamber_WhiteLocatorDrum",
        (0.0, -0.36, 0.36),
        (0.0, -0.56, 0.36),
        0.18,
        materials["white_alt"],
        root,
        collection,
        vertices=14,
        bevel=0.003,
    )
    add_torus_y(
        "Chamber_BlueScanRing",
        (0.0, -0.56, 0.36),
        0.165,
        0.018,
        materials["blue_glow"],
        root,
        collection,
    )

    # Front launcher / emitter tube.
    add_cylinder_between(
        "Barrel_WhiteEmitterTube",
        (0.0, -0.54, 0.36),
        (0.0, -0.88, 0.36),
        0.12,
        materials["white"],
        root,
        collection,
        vertices=16,
        bevel=0.003,
    )
    add_cube(
        "Barrel_WhiteTopGuide",
        (0.0, -0.73, 0.52),
        (0.18, 0.26, 0.10),
        materials["white_alt"],
        root,
        collection,
        bevel=0.012,
    )
    add_cylinder_between(
        "Muzzle_BlackEmitterHead",
        (0.0, -0.86, 0.36),
        (0.0, -1.02, 0.36),
        0.15,
        materials["black"],
        root,
        collection,
        vertices=18,
        bevel=0.003,
    )
    add_cylinder_between(
        "Muzzle_Core",
        (0.0, -0.98, 0.36),
        (0.0, -1.07, 0.36),
        0.08,
        materials["core"],
        root,
        collection,
        vertices=16,
        bevel=0.002,
    )

    # Top sensor / tracking block.
    add_cube(
        "TopSensor_WhiteHousing",
        (0.0, -0.14, 0.65),
        (0.18, 0.34, 0.10),
        materials["white"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "TopSensor_BlueWindow",
        (0.0, -0.14, 0.70),
        (0.12, 0.18, 0.06),
        materials["blue_glow"],
        root,
        collection,
        bevel=0.008,
    )

    # Side tracker light panels.
    for index, y in enumerate((-0.42, -0.26, -0.10)):
        add_cube(
            f"Panel_LeftBlueLight_{index:02d}",
            (-0.185, y, 0.38),
            (0.028, 0.080, 0.09),
            materials["blue_glow"],
            root,
            collection,
            bevel=0.006,
        )
        add_cube(
            f"Panel_RightBlueLight_{index:02d}",
            (0.185, y, 0.38),
            (0.028, 0.080, 0.09),
            materials["blue_glow"],
            root,
            collection,
            bevel=0.006,
        )

    # Short front support / off-hand area.
    add_cube(
        "Support_WhiteUndermount",
        (0.0, -0.52, 0.16),
        (0.20, 0.26, 0.12),
        materials["white_alt"],
        root,
        collection,
        bevel=0.010,
    )
    add_cube(
        "Support_BlackMiniGrip",
        (0.0, -0.52, -0.05),
        (0.14, 0.14, 0.36),
        materials["black"],
        root,
        collection,
        bevel=0.020,
        rotation=(math.radians(4.0), 0.0, 0.0),
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



def validate_attachment_pairs():
    pairs = [
        ("Grip_BlackPrimary", "Frame_WhiteTriggerBlock", 0.005),
        ("Grip_WhiteBackstrap", "Grip_BlackPrimary", 0.005),
        ("TriggerGuard_BlackRear", "Frame_WhiteTriggerBlock", 0.005),
        ("TriggerGuard_BlackFront", "Frame_WhiteTriggerBlock", 0.005),
        ("TriggerGuard_BlackBottom", "TriggerGuard_BlackRear", 0.005),
        ("Trigger_Dark", "TriggerGuard_BlackRear", 0.005),
        ("Body_WhiteMain", "Frame_WhiteTriggerBlock", 0.005),
        ("Body_WhiteTopShell", "Body_WhiteMain", 0.005),
        ("Body_GunmetalLeftPanel", "Body_WhiteMain", 0.005),
        ("Body_GunmetalRightPanel", "Body_WhiteMain", 0.005),
        ("RearPack_WhiteBattery", "Body_WhiteMain", 0.005),
        ("RearPack_OrangeBeacon", "RearPack_WhiteBattery", 0.005),
        ("Chamber_WhiteLocatorDrum", "Body_WhiteMain", 0.005),
        ("Chamber_BlueScanRing", "Chamber_WhiteLocatorDrum", 0.005),
        ("Barrel_WhiteEmitterTube", "Chamber_WhiteLocatorDrum", 0.005),
        ("Barrel_WhiteTopGuide", "Barrel_WhiteEmitterTube", 0.005),
        ("Muzzle_BlackEmitterHead", "Barrel_WhiteEmitterTube", 0.005),
        ("Muzzle_Core", "Muzzle_BlackEmitterHead", 0.005),
        ("TopSensor_WhiteHousing", "Body_WhiteTopShell", 0.005),
        ("TopSensor_BlueWindow", "TopSensor_WhiteHousing", 0.005),
        ("Panel_LeftBlueLight_00", "Body_GunmetalLeftPanel", 0.005),
        ("Panel_RightBlueLight_00", "Body_GunmetalRightPanel", 0.005),
        ("Support_WhiteUndermount", "Chamber_WhiteLocatorDrum", 0.005),
        ("Support_BlackMiniGrip", "Support_WhiteUndermount", 0.005),
    ]

    failures = []
    for first_name, second_name, allowed_gap in pairs:
        first = get_mesh_by_name(first_name)
        second = get_mesh_by_name(second_name)
        distance = aabb_distance(first, second)
        if distance > allowed_gap:
            failures.append(
                f"{first_name} -> {second_name}: gap {distance:.4f} m > allowed {allowed_gap:.4f} m"
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
        raise RuntimeError("SecondaryHandGrip moved away from mini grip.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(bad_scene))

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes under vehicle locator launcher root.")

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
        raise RuntimeError("Expected one merged vehicle locator launcher visual mesh.")
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
    print(f"\n=== Generating Rider Vehicle Locator Launcher [{SCRIPT_REVISION}] ===\n")
    root, projectile_point, secondary_grip = build_vehicle_locator_launcher()
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
    print(" - ProjectileSpawnPoint: spawn locator projectile here.")
    print(" - SecondaryHandGrip: optional support-hand IK target.")


if __name__ == "__main__":
    main()
