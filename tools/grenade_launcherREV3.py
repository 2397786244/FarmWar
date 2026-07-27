# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Handheld Olive Grenade Launcher
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_GrenadeLauncher_Olive_v2.glb
#
# DESIGN
# - Distinct from the medicine cannon: this is a military-style revolving
#   grenade launcher with an olive-green body, black barrel and black grips.
# - Large central drum / breech block, compact barrel, low-profile top rail,
#   mechanical sights and skeletal shoulder stock.
# - Low-poly / stylized game asset intended for Godot.
# - Handheld, shoulder-fired, chunky proportions, easy-to-read silhouette.
#
# EXPORTED HIERARCHY
#   FTF_Tool_GrenadeLauncher_Olive_v2
#   |-- FTF_Tool_GrenadeLauncher_Olive_v2_Static
#   |-- ProjectileSpawnPoint
#   `-- SecondaryHandGrip
#
# ASSET STANDARD
# - Blender authoring/projectile direction: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip: (0, 0, 0)
# - ProjectileSpawnPoint is centred just beyond the muzzle
# - SecondaryHandGrip marks the support-hand position
# - No cameras, lights, text or collision meshes
# - All visual meshes merge into one static mesh before export
#
# Run:
#   blender --background --factory-startup --python grenade_launcher_olive.py
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
OUTPUT_FILE = "FTF_Tool_GrenadeLauncher_Olive_v2.glb"
SCRIPT_REVISION = "REV2_TOP_RAIL_ATTACHED"

ROOT_NAME = "FTF_Tool_GrenadeLauncher_Olive_v2"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

PROJECTILE_POINT_LOCATION = Vector((0.0, -1.41, 0.45))
SECONDARY_GRIP_LOCATION = Vector((0.0, -0.80, -0.13))


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
        "olive": make_material(
            "MAT_GL_OliveBody", (0.22, 0.28, 0.19), 0.66, 0.12
        ),
        "olive_dark": make_material(
            "MAT_GL_DarkOlive", (0.13, 0.17, 0.11), 0.74, 0.14
        ),
        "olive_light": make_material(
            "MAT_GL_LightOlive", (0.35, 0.42, 0.28), 0.62, 0.10
        ),
        "black": make_material(
            "MAT_GL_BlackGrip", (0.018, 0.020, 0.022), 0.86, 0.08
        ),
        "gunmetal": make_material(
            "MAT_GL_Gunmetal", (0.12, 0.14, 0.15), 0.44, 0.46
        ),
        "steel": make_material(
            "MAT_GL_Steel", (0.41, 0.44, 0.46), 0.36, 0.56
        ),
        "bore": make_material(
            "MAT_GL_DeepBore", (0.003, 0.004, 0.005), 0.95, 0.03
        ),
        "yellow": make_material(
            "MAT_GL_WarningYellow", (0.72, 0.60, 0.12), 0.58, 0.05
        ),
        "amber_glow": make_material(
            "MAT_GL_AmberGlow",
            (0.95, 0.75, 0.18),
            emission=(0.95, 0.58, 0.06),
            emission_strength=1.8,
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
    root["tool_category"] = "GrenadeLauncher"
    root["visual_style"] = "RevolvingOliveGrenadeLauncher"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "PrimaryHandGrip"
    root["projectile_spawn_node"] = "ProjectileSpawnPoint"
    root["secondary_hand_node"] = "SecondaryHandGrip"
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
    projectile.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    projectile["effect_role"] = "GrenadeProjectileOrigin"
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
# BUILD GRENADE LAUNCHER
# -----------------------------------------------------------------------------


def build_grenade_launcher():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    materials = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    projectile_point, secondary_grip = create_runtime_markers(root, collection)

    # Primary grip at origin.
    add_cube(
        "Grip_BlackPrimary",
        (0.0, 0.04, -0.22),
        (0.24, 0.28, 0.78),
        materials["black"],
        root,
        collection,
        bevel=0.028,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_OliveBackstrap",
        (0.0, 0.13, -0.17),
        (0.30, 0.10, 0.66),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.018,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )

    # Trigger housing.
    add_cube(
        "Receiver_LowerFrame",
        (0.0, -0.06, 0.16),
        (0.42, 0.56, 0.28),
        materials["olive"],
        root,
        collection,
        bevel=0.028,
    )
    add_cube(
        "TriggerGuard_Rear",
        (0.0, -0.20, -0.02),
        (0.34, 0.10, 0.24),
        materials["black"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "TriggerGuard_Front",
        (0.0, -0.34, 0.02),
        (0.34, 0.10, 0.34),
        materials["black"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "TriggerGuard_Bottom",
        (0.0, -0.27, -0.13),
        (0.32, 0.26, 0.08),
        materials["black"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Trigger_Steel",
        (0.0, -0.22, -0.04),
        (0.09, 0.05, 0.20),
        materials["steel"],
        root,
        collection,
        bevel=0.010,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )

    # Compact main receiver. The forward face ends before the drum, preventing
    # the old rear black ring from cutting through the olive receiver shell.
    add_cube(
        "Receiver_OliveMain",
        (0.0, -0.13, 0.45),
        (0.50, 0.62, 0.42),
        materials["olive"],
        root,
        collection,
        bevel=0.036,
    )
    add_cube(
        "Receiver_SidePlate_Left",
        (-0.27, -0.13, 0.47),
        (0.08, 0.56, 0.32),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Receiver_SidePlate_Right",
        (0.27, -0.13, 0.47),
        (0.08, 0.56, 0.32),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.012,
    )

    # Internal gunmetal neck physically joins receiver and revolving drum.
    # It replaces the former rear torus that visibly intersected the body.
    add_cylinder_between(
        "Drum_GunmetalRearNeck",
        (0.0, -0.41, 0.45),
        (0.0, -0.50, 0.45),
        0.20,
        materials["gunmetal"],
        root,
        collection,
        vertices=16,
        bevel=0.003,
    )

    # Compact revolving drum / breech block.
    add_cylinder_between(
        "Drum_OliveRevolverCore",
        (0.0, -0.46, 0.45),
        (0.0, -0.80, 0.45),
        0.28,
        materials["olive_light"],
        root,
        collection,
        vertices=12,
        bevel=0.004,
    )

    # A flat front flange gives a clean seam. It does not wrap around or cut
    # through the receiver like the removed rear torus.
    add_cylinder_between(
        "Drum_BlackFrontFlange",
        (0.0, -0.78, 0.45),
        (0.0, -0.82, 0.45),
        0.29,
        materials["black"],
        root,
        collection,
        vertices=18,
        bevel=0.002,
    )

    # Six shallow chamber details are moved outward so they read on the drum
    # surface instead of being buried inside it.
    for index, angle in enumerate((0.0, 60.0, 120.0, 180.0, 240.0, 300.0)):
        radians = math.radians(angle)
        x = math.cos(radians) * 0.245
        z = 0.45 + math.sin(radians) * 0.205
        add_cube(
            f"Drum_ChamberPort_{index:02d}",
            (x, -0.63, z),
            (0.075, 0.16, 0.075),
            materials["gunmetal"],
            root,
            collection,
            bevel=0.009,
            rotation=(0.0, 0.0, radians),
        )

    # Short barrel assembly. Total forward length is reduced by roughly one
    # third compared with REV2.
    add_cylinder_between(
        "Barrel_OliveOuter",
        (0.0, -0.80, 0.45),
        (0.0, -1.08, 0.45),
        0.17,
        materials["olive"],
        root,
        collection,
        vertices=18,
        bevel=0.004,
    )
    add_torus_y(
        "Barrel_YellowWarningRing",
        (0.0, -0.98, 0.45),
        0.172,
        0.016,
        materials["yellow"],
        root,
        collection,
    )
    add_cylinder_between(
        "Barrel_BlackSleeve",
        (0.0, -1.00, 0.45),
        (0.0, -1.19, 0.45),
        0.19,
        materials["black"],
        root,
        collection,
        vertices=20,
        bevel=0.004,
    )
    add_cylinder_between(
        "Muzzle_BlackOuter",
        (0.0, -1.16, 0.45),
        (0.0, -1.32, 0.45),
        0.205,
        materials["black"],
        root,
        collection,
        vertices=22,
        bevel=0.004,
    )
    add_cylinder_between(
        "Muzzle_DeepBore",
        (0.0, -1.28, 0.45),
        (0.0, -1.38, 0.45),
        0.13,
        materials["bore"],
        root,
        collection,
        vertices=20,
        bevel=0.002,
    )

    # Low-profile top rail. The old three stacked long green blocks / carry
    # handle are removed because they resembled a crude scope and floated.
    add_cube(
        "TopRail_OliveBase",
        (0.0, -0.14, 0.69),
        (0.22, 0.50, 0.08),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.010,
    )
    for index, y in enumerate((-0.34, -0.24, -0.14, -0.04, 0.06)):
        add_cube(
            f"TopRail_Tooth_{index:02d}",
            (0.0, y, 0.735),
            (0.24, 0.045, 0.045),
            materials["gunmetal"],
            root,
            collection,
            bevel=0.004,
        )

    # Rear iron sight is mounted directly on the rail.
    add_cube(
        "Sight_RearMount",
        (0.0, 0.02, 0.765),
        (0.16, 0.11, 0.07),
        materials["black"],
        root,
        collection,
        bevel=0.008,
    )
    add_cube(
        "Sight_RearNotch",
        (0.0, 0.02, 0.825),
        (0.10, 0.07, 0.08),
        materials["black"],
        root,
        collection,
        bevel=0.006,
    )

    # Front sight has its own barrel-mounted base, so it cannot float.
    add_cube(
        "Sight_FrontMount",
        (0.0, -1.00, 0.625),
        (0.16, 0.13, 0.08),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.008,
    )
    add_cube(
        "Sight_Front_Glow",
        (0.0, -1.00, 0.685),
        (0.08, 0.07, 0.08),
        materials["amber_glow"],
        root,
        collection,
        bevel=0.008,
    )

    # Front support mount overlaps both the drum underside and barrel underside.
    add_cube(
        "Handguard_OliveMount",
        (0.0, -0.82, 0.20),
        (0.30, 0.30, 0.20),
        materials["olive"],
        root,
        collection,
        bevel=0.016,
    )
    add_cube(
        "ForeGrip_BlackVertical",
        (0.0, -0.80, -0.13),
        (0.18, 0.22, 0.54),
        materials["black"],
        root,
        collection,
        bevel=0.026,
        rotation=(math.radians(4.0), 0.0, 0.0),
    )
    add_cube(
        "ForeGrip_OliveCap",
        (0.0, -0.80, 0.10),
        (0.22, 0.20, 0.10),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.010,
    )

    # Shoulder stock remains skeletal but all members overlap their neighbours.
    add_cube(
        "Stock_OliveBeam",
        (0.0, 0.36, 0.38),
        (0.24, 0.84, 0.16),
        materials["olive"],
        root,
        collection,
        bevel=0.022,
    )
    add_cube(
        "Stock_LeftStrut",
        (-0.10, 0.53, 0.47),
        (0.08, 0.50, 0.18),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.010,
        rotation=(math.radians(22.0), 0.0, 0.0),
    )
    add_cube(
        "Stock_RightStrut",
        (0.10, 0.53, 0.47),
        (0.08, 0.50, 0.18),
        materials["olive_dark"],
        root,
        collection,
        bevel=0.010,
        rotation=(math.radians(22.0), 0.0, 0.0),
    )
    add_cube(
        "Stock_BlackShoulderPad",
        (0.0, 0.77, 0.38),
        (0.34, 0.12, 0.36),
        materials["black"],
        root,
        collection,
        bevel=0.020,
    )

    # Side latches are embedded slightly into the receiver skin rather than
    # hovering outside it.
    add_cube(
        "Detail_LeftLatch",
        (-0.255, -0.08, 0.48),
        (0.06, 0.16, 0.10),
        materials["steel"],
        root,
        collection,
        bevel=0.006,
    )
    add_cube(
        "Detail_RightLatch",
        (0.255, -0.08, 0.48),
        (0.06, 0.16, 0.10),
        materials["steel"],
        root,
        collection,
        bevel=0.006,
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
        ("Grip_BlackPrimary", "Receiver_LowerFrame", 0.005),
        ("Grip_OliveBackstrap", "Grip_BlackPrimary", 0.005),
        ("TriggerGuard_Rear", "Receiver_LowerFrame", 0.005),
        ("TriggerGuard_Front", "Receiver_LowerFrame", 0.005),
        ("TriggerGuard_Bottom", "TriggerGuard_Rear", 0.005),
        ("Trigger_Steel", "TriggerGuard_Rear", 0.005),
        ("Receiver_OliveMain", "Receiver_LowerFrame", 0.005),
        ("Receiver_SidePlate_Left", "Receiver_OliveMain", 0.005),
        ("Receiver_SidePlate_Right", "Receiver_OliveMain", 0.005),
        ("Drum_GunmetalRearNeck", "Receiver_OliveMain", 0.005),
        ("Drum_GunmetalRearNeck", "Drum_OliveRevolverCore", 0.005),
        ("Drum_BlackFrontFlange", "Drum_OliveRevolverCore", 0.005),
        ("Barrel_OliveOuter", "Drum_BlackFrontFlange", 0.005),
        ("Barrel_BlackSleeve", "Barrel_OliveOuter", 0.005),
        ("Muzzle_BlackOuter", "Barrel_BlackSleeve", 0.005),
        ("Muzzle_DeepBore", "Muzzle_BlackOuter", 0.005),
        ("TopRail_OliveBase", "Receiver_OliveMain", 0.005),
        ("TopRail_Tooth_00", "TopRail_OliveBase", 0.005),
        ("TopRail_Tooth_04", "TopRail_OliveBase", 0.005),
        ("Sight_RearMount", "TopRail_OliveBase", 0.005),
        ("Sight_RearNotch", "Sight_RearMount", 0.005),
        ("Sight_FrontMount", "Barrel_BlackSleeve", 0.005),
        ("Sight_Front_Glow", "Sight_FrontMount", 0.005),
        ("Handguard_OliveMount", "Drum_OliveRevolverCore", 0.005),
        ("Handguard_OliveMount", "Barrel_OliveOuter", 0.005),
        ("ForeGrip_BlackVertical", "Handguard_OliveMount", 0.005),
        ("ForeGrip_OliveCap", "ForeGrip_BlackVertical", 0.005),
        ("Stock_OliveBeam", "Receiver_OliveMain", 0.005),
        ("Stock_LeftStrut", "Stock_OliveBeam", 0.005),
        ("Stock_RightStrut", "Stock_OliveBeam", 0.005),
        ("Stock_BlackShoulderPad", "Stock_OliveBeam", 0.005),
        ("Detail_LeftLatch", "Receiver_OliveMain", 0.005),
        ("Detail_RightLatch", "Receiver_OliveMain", 0.005),
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
        raise RuntimeError("SecondaryHandGrip moved away from foregrip.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(bad_scene))

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes under grenade launcher root.")

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

    forbidden_old_parts = [
        name for name in ("Drum_BlackRearRing", "Drum_BlackFrontRing", "CarryHandle_LeftPost", "CarryHandle_RightPost", "CarryHandle_Top")
        if bpy.data.objects.get(name) is not None
    ]
    if forbidden_old_parts:
        raise RuntimeError("Deprecated clipping/floating geometry remains: " + ", ".join(forbidden_old_parts))

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
        raise RuntimeError("Expected one merged grenade launcher visual mesh.")
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
    print(f"\n=== Generating Handheld Olive Grenade Launcher [{SCRIPT_REVISION}] ===\n")
    root, projectile_point, secondary_grip = build_grenade_launcher()
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
    print(" - ProjectileSpawnPoint: spawn grenade projectile or effect here.")
    print(" - SecondaryHandGrip: optional support-hand IK target.")
    print(" - REV3: shorter barrel, low rail, no rear body torus, connected details.")


if __name__ == "__main__":
    main()
