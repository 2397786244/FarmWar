# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Chef Chili Marker Sprayer
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_ChiliMarkerSprayer_RedBlack_v1.glb
#
# DESIGN
# - Chef-exclusive hand-held chili concentrate sprayer
# - Primarily marks enemies rather than dealing direct projectile damage
# - Red shell with black grip, frame, rails and diffuser nozzle
# - Transparent dark-red chili concentrate tank with glowing inner fluid
# - Small geometric chili emblem and restrained green stem accents
# - Chunky stylized game-prop silhouette, not a realistic firearm replica
#
# EXPORTED HIERARCHY
#   FTF_Tool_ChiliMarkerSprayer_RedBlack_v1
#   |-- FTF_Tool_ChiliMarkerSprayer_RedBlack_v1_Static
#   |-- ChiliTank_GlassShell
#   |-- ChiliTank_GlowCore
#   `-- SprayPoint
#
# ASSET STANDARD
# - Blender authoring forward / spray direction: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip: (0, 0, 0)
# - SprayPoint is an independent Empty at the diffuser outlet
# - No cameras, lights, text or collision meshes
# - Opaque static geometry is merged; transparent tank meshes stay separate
#
# Run:
#   blender --background --factory-startup --python chili_marker_sprayer.py
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
OUTPUT_FILE = "FTF_Tool_ChiliMarkerSprayer_RedBlack_v1.glb"

ROOT_NAME = "FTF_Tool_ChiliMarkerSprayer_RedBlack_v1"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_OPAQUE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

SPRAY_POINT_LOCATION = Vector((0.0, -1.955, 0.43))


# -----------------------------------------------------------------------------
# SCENE / MATERIALS
# -----------------------------------------------------------------------------

def clear_scene():
    """Delete startup objects and unused scene data."""
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
    alpha=1.0,
    emission=None,
    emission_strength=0.0,
):
    """Create an opaque, transparent or emissive GLB-friendly material."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")

    if emission is not None and emission_strength > 0.0:
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (*emission, alpha)
        emit.inputs["Strength"].default_value = emission_strength
        links.new(emit.outputs["Emission"], output.inputs["Surface"])
    else:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*color, alpha)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

        if alpha < 1.0:
            bsdf.inputs["Alpha"].default_value = alpha
            if hasattr(material, "surface_render_method"):
                try:
                    enum_items = material.bl_rna.properties[
                        "surface_render_method"
                    ].enum_items.keys()
                    if "DITHERED" in enum_items:
                        material.surface_render_method = "DITHERED"
                    elif "BLENDED" in enum_items:
                        material.surface_render_method = "BLENDED"
                except Exception as exc:
                    print(f"[WARN] Could not set transparency on {name}: {exc}")
            elif hasattr(material, "blend_method"):
                material.blend_method = "BLEND"

        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    material.diffuse_color = (*color, alpha)
    return material


def build_materials():
    return {
        "red": make_material(
            "MAT_CMS_ChiliRedShell", (0.68, 0.025, 0.018), 0.62, 0.10
        ),
        "red_bright": make_material(
            "MAT_CMS_BrightRedPanels", (0.95, 0.045, 0.025), 0.52, 0.06
        ),
        "red_dark": make_material(
            "MAT_CMS_DeepRedFrame", (0.26, 0.012, 0.010), 0.72, 0.16
        ),
        "black": make_material(
            "MAT_CMS_MatteBlack", (0.015, 0.018, 0.020), 0.86, 0.08
        ),
        "gunmetal": make_material(
            "MAT_CMS_DarkGunmetal", (0.10, 0.115, 0.12), 0.52, 0.42
        ),
        "green": make_material(
            "MAT_CMS_ChiliStemGreen", (0.10, 0.42, 0.12), 0.76, 0.02
        ),
        "orange": make_material(
            "MAT_CMS_ChiliOrangeMark", (1.0, 0.22, 0.025), 0.58, 0.02
        ),
        "gauge": make_material(
            "MAT_CMS_GaugeFace", (0.88, 0.90, 0.86), 0.42, 0.0
        ),
        "glass": make_material(
            "MAT_CMS_TransparentCrimsonTank",
            (0.68, 0.03, 0.025),
            roughness=0.16,
            metallic=0.02,
            alpha=0.42,
        ),
        "fluid_glow": make_material(
            "MAT_CMS_GlowingChiliConcentrate",
            (1.0, 0.06, 0.015),
            emission=(1.0, 0.035, 0.008),
            emission_strength=2.4,
        ),
    }


# -----------------------------------------------------------------------------
# COLLECTION / OBJECT HELPERS
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
    root.empty_display_size = 0.28
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "ChiliMarkerSprayer"
    root["character_role"] = "Cook"
    root["gameplay_purpose"] = "EnemyMarking"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "PrimaryHandGrip"
    root["spray_point_node"] = "SprayPoint"
    root["has_collision_mesh"] = False
    root["effects_baked_into_model"] = False

    collection.objects.link(root)
    return root


def create_spray_point(root, collection):
    marker = bpy.data.objects.new("SprayPoint", None)
    marker.empty_display_type = "SINGLE_ARROW"
    marker.empty_display_size = 0.13
    marker.location = SPRAY_POINT_LOCATION
    marker.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    marker.parent = root
    marker["effect_role"] = "EnemyMarkingSprayOrigin"
    marker["local_forward_axis"] = "-Y"
    collection.objects.link(marker)
    return marker


# -----------------------------------------------------------------------------
# GEOMETRY HELPERS
# -----------------------------------------------------------------------------

def finish_object(
    obj,
    name,
    material,
    parent,
    collection,
    bevel=0.0,
    no_merge=False,
):
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def add_cube(
    name,
    location,
    dimensions,
    material,
    parent,
    collection,
    bevel=0.0,
    rotation=(0.0, 0.0, 0.0),
    no_merge=False,
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(
        obj, name, material, parent, collection, bevel, no_merge
    )


def add_cylinder_between(
    name,
    p0,
    p1,
    radius,
    material,
    parent,
    collection,
    vertices=16,
    bevel=0.0,
    no_merge=False,
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
        bpy.context.object,
        name,
        material,
        parent,
        collection,
        bevel,
        no_merge,
    )


def add_cone_between(
    name,
    p0,
    p1,
    radius1,
    radius2,
    material,
    parent,
    collection,
    vertices=18,
    bevel=0.0,
):
    p0 = Vector(p0)
    p1 = Vector(p1)
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cone: {name}")

    midpoint = (p0 + p1) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=length,
        location=midpoint,
        rotation=rotation,
    )
    return finish_object(
        bpy.context.object, name, material, parent, collection, bevel
    )


def add_lowpoly_sphere(
    name,
    location,
    radius,
    scale,
    material,
    parent,
    collection,
    no_merge=False,
):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1, radius=radius, location=location
    )
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(
        obj, name, material, parent, collection, no_merge=no_merge
    )


def add_torus_y(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    parent,
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
    return finish_object(
        bpy.context.object, name, material, parent, collection
    )


# -----------------------------------------------------------------------------
# BUILD TOOL
# -----------------------------------------------------------------------------

def build_chili_marker_sprayer():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    spray_point = create_spray_point(root, collection)

    # Primary black grip. Root remains at the intended hand contact position.
    add_cube(
        "Grip_BlackCore",
        (0.0, 0.03, -0.32),
        (0.32, 0.34, 0.92),
        mats["black"],
        root,
        collection,
        bevel=0.035,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_RedBackPlate",
        (0.0, 0.16, -0.28),
        (0.40, 0.10, 0.82),
        mats["red_dark"],
        root,
        collection,
        bevel=0.020,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "Rear_GripSocket",
        (0.0, -0.02, 0.35),
        (0.60, 0.42, 0.48),
        mats["black"],
        root,
        collection,
        bevel=0.040,
    )

    # Red/black main pressure body.
    add_cube(
        "Body_RedMainShell",
        (0.0, -0.55, 0.43),
        (0.72, 1.08, 0.52),
        mats["red"],
        root,
        collection,
        bevel=0.060,
    )
    add_cube(
        "Body_BlackUpperSpine",
        (0.0, -0.52, 0.735),
        (0.54, 0.98, 0.13),
        mats["black"],
        root,
        collection,
        bevel=0.018,
    )
    add_cube(
        "Body_BlackBottomRail",
        (0.0, -0.56, 0.12),
        (0.48, 0.94, 0.13),
        mats["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "Body_RedSidePanelLeft",
        (-0.375, -0.54, 0.45),
        (0.055, 0.72, 0.34),
        mats["red_bright"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Body_RedSidePanelRight",
        (0.375, -0.54, 0.45),
        (0.055, 0.72, 0.34),
        mats["red_bright"],
        root,
        collection,
        bevel=0.012,
    )

    # Trigger and guard remain visibly connected to grip socket/body rail.
    add_cube(
        "TriggerGuard_Rear",
        (0.0, -0.17, -0.02),
        (0.46, 0.12, 0.34),
        mats["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "TriggerGuard_Front",
        (0.0, -0.43, -0.02),
        (0.46, 0.12, 0.34),
        mats["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "TriggerGuard_Bottom",
        (0.0, -0.30, -0.19),
        (0.44, 0.36, 0.10),
        mats["black"],
        root,
        collection,
        bevel=0.014,
    )
    add_cube(
        "Trigger_RedMarkerLever",
        (0.0, -0.24, -0.06),
        (0.15, 0.09, 0.29),
        mats["red_bright"],
        root,
        collection,
        bevel=0.024,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )

    # Transparent chili concentrate cylinder on top.
    add_cylinder_between(
        "ChiliTank_GlassShell",
        (0.0, -0.08, 0.98),
        (0.0, -0.92, 0.98),
        0.235,
        mats["glass"],
        root,
        collection,
        vertices=22,
        bevel=0.004,
        no_merge=True,
    )
    add_cylinder_between(
        "ChiliTank_GlowCore",
        (0.0, -0.12, 0.98),
        (0.0, -0.88, 0.98),
        0.155,
        mats["fluid_glow"],
        root,
        collection,
        vertices=18,
        bevel=0.002,
        no_merge=True,
    )
    add_cylinder_between(
        "ChiliTank_RearBlackCap",
        (0.0, -0.10, 0.98),
        (0.0, 0.10, 0.98),
        0.255,
        mats["black"],
        root,
        collection,
        vertices=20,
        bevel=0.003,
    )
    add_cylinder_between(
        "ChiliTank_FrontRedCap",
        (0.0, -0.90, 0.98),
        (0.0, -1.04, 0.98),
        0.255,
        mats["red_dark"],
        root,
        collection,
        vertices=20,
        bevel=0.003,
    )
    for index, y in enumerate((-0.18, -0.80)):
        add_cube(
            f"ChiliTank_BlackMountStrap_{index:02d}",
            (0.0, y, 0.79),
            (0.82, 0.12, 0.22),
            mats["black"],
            root,
            collection,
            bevel=0.014,
        )

    # Short diffuser barrel communicates spray/marking rather than bullets.
    add_cylinder_between(
        "Nozzle_BlackBodySocket",
        (0.0, -1.06, 0.43),
        (0.0, -1.25, 0.43),
        0.215,
        mats["black"],
        root,
        collection,
        vertices=18,
        bevel=0.004,
    )
    add_cylinder_between(
        "Nozzle_RedShortTube",
        (0.0, -1.24, 0.43),
        (0.0, -1.55, 0.43),
        0.135,
        mats["red"],
        root,
        collection,
        vertices=18,
        bevel=0.004,
    )
    add_torus_y(
        "Nozzle_BlackSealRing",
        (0.0, -1.48, 0.43),
        0.155,
        0.020,
        mats["black"],
        root,
        collection,
    )
    add_cone_between(
        "Nozzle_BlackDiffuserCone",
        (0.0, -1.52, 0.43),
        (0.0, -1.86, 0.43),
        0.235,
        0.125,
        mats["black"],
        root,
        collection,
        vertices=20,
        bevel=0.004,
    )
    add_cylinder_between(
        "Nozzle_RedMarkerFace",
        (0.0, -1.84, 0.43),
        (0.0, -1.91, 0.43),
        0.225,
        mats["red_bright"],
        root,
        collection,
        vertices=20,
        bevel=0.002,
    )

    # Five attached black outlet holes form a wide marking-spray pattern.
    for index, (x, z) in enumerate(
        ((0.0, 0.43), (0.085, 0.49), (-0.085, 0.49), (0.085, 0.37), (-0.085, 0.37))
    ):
        add_cylinder_between(
            f"Nozzle_Outlet_{index:02d}",
            (x, -1.91, z),
            (x, -1.94, z),
            0.024,
            mats["black"],
            root,
            collection,
            vertices=10,
        )

    # Right-side pressure gauge.
    add_cylinder_between(
        "Gauge_BlackRim",
        (0.35, -0.50, 0.52),
        (0.46, -0.50, 0.52),
        0.16,
        mats["black"],
        root,
        collection,
        vertices=18,
        bevel=0.002,
    )
    add_cylinder_between(
        "Gauge_WhiteFace",
        (0.45, -0.50, 0.52),
        (0.485, -0.50, 0.52),
        0.13,
        mats["gauge"],
        root,
        collection,
        vertices=18,
    )
    add_cube(
        "Gauge_RedNeedle",
        (0.491, -0.48, 0.55),
        (0.012, 0.018, 0.13),
        mats["red_bright"],
        root,
        collection,
        bevel=0.001,
        rotation=(math.radians(-26.0), 0.0, 0.0),
    )

    # Geometric chili emblem on the negative-X side of the red body.
    add_lowpoly_sphere(
        "ChiliEmblem_Body",
        (-0.385, -0.50, 0.53),
        0.14,
        (0.16, 1.05, 0.46),
        mats["orange"],
        root,
        collection,
    )
    add_lowpoly_sphere(
        "ChiliEmblem_Tip",
        (-0.387, -0.65, 0.47),
        0.09,
        (0.14, 0.78, 0.35),
        mats["red_bright"],
        root,
        collection,
    )
    add_cube(
        "ChiliEmblem_GreenStem",
        (-0.390, -0.36, 0.59),
        (0.035, 0.12, 0.055),
        mats["green"],
        root,
        collection,
        bevel=0.010,
        rotation=(math.radians(12.0), 0.0, math.radians(-12.0)),
    )

    # Rear service panel and compact top sight ridge.
    add_cube(
        "Rear_BlackServicePanel",
        (0.0, 0.225, 0.40),
        (0.48, 0.07, 0.30),
        mats["black"],
        root,
        collection,
        bevel=0.012,
    )
    add_cube(
        "Top_RedAimRidge",
        (0.0, -0.98, 0.755),
        (0.12, 0.15, 0.095),
        mats["red_bright"],
        root,
        collection,
        bevel=0.010,
    )

    return root, spray_point


# -----------------------------------------------------------------------------
# VALIDATION
# -----------------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def get_opaque_meshes_for_merge(root):
    return [
        obj for obj in get_meshes_under_root(root)
        if not obj.get("no_merge", False)
    ]


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
        ("Grip_BlackCore", "Rear_GripSocket", 0.05),
        ("Grip_RedBackPlate", "Grip_BlackCore", 0.04),
        ("Rear_GripSocket", "Body_RedMainShell", 0.04),
        ("Body_BlackUpperSpine", "Body_RedMainShell", 0.04),
        ("Body_BlackBottomRail", "Body_RedMainShell", 0.04),
        ("TriggerGuard_Rear", "Rear_GripSocket", 0.05),
        ("TriggerGuard_Front", "Body_BlackBottomRail", 0.05),
        ("TriggerGuard_Bottom", "TriggerGuard_Rear", 0.05),
        ("Trigger_RedMarkerLever", "TriggerGuard_Rear", 0.08),
        ("ChiliTank_GlassShell", "ChiliTank_BlackMountStrap_00", 0.04),
        ("ChiliTank_GlassShell", "ChiliTank_BlackMountStrap_01", 0.04),
        ("ChiliTank_GlowCore", "ChiliTank_GlassShell", 0.03),
        ("ChiliTank_RearBlackCap", "ChiliTank_GlassShell", 0.04),
        ("ChiliTank_FrontRedCap", "ChiliTank_GlassShell", 0.04),
        ("Nozzle_BlackBodySocket", "Body_RedMainShell", 0.05),
        ("Nozzle_RedShortTube", "Nozzle_BlackBodySocket", 0.04),
        ("Nozzle_BlackDiffuserCone", "Nozzle_RedShortTube", 0.04),
        ("Nozzle_RedMarkerFace", "Nozzle_BlackDiffuserCone", 0.04),
        ("Gauge_BlackRim", "Body_RedMainShell", 0.04),
        ("Gauge_WhiteFace", "Gauge_BlackRim", 0.03),
        ("ChiliEmblem_Body", "Body_RedMainShell", 0.04),
        ("ChiliEmblem_Tip", "ChiliEmblem_Body", 0.04),
        ("ChiliEmblem_GreenStem", "ChiliEmblem_Body", 0.05),
        ("Rear_BlackServicePanel", "Rear_GripSocket", 0.04),
        ("Top_RedAimRidge", "Body_BlackUpperSpine", 0.05),
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


def detect_collision_like_meshes():
    bad = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        lowered = obj.name.lower()
        if lowered.startswith("ucx") or "collision" in lowered:
            bad.append(obj.name)
    if bad:
        raise RuntimeError("Collision-like meshes found: " + ", ".join(bad))


def validate_before_merge(root, spray_point):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Root must remain an Empty at primary grip origin.")
    if spray_point.parent != root:
        raise RuntimeError("SprayPoint must be a direct child of root.")
    if (spray_point.location - SPRAY_POINT_LOCATION).length > 0.0001:
        raise RuntimeError("SprayPoint moved away from diffuser outlet.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("Cameras/lights remain: " + ", ".join(bad_scene))
    detect_collision_like_meshes()

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No meshes under root.")

    failures = []
    for obj in meshes:
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
        f"  Origin: primary hand grip at (0, 0, 0)\n"
        f"  SprayPoint: {tuple(round(v, 3) for v in spray_point.location)}\n"
    )


# -----------------------------------------------------------------------------
# MERGE / POST-MERGE VALIDATION / EXPORT
# -----------------------------------------------------------------------------

def merge_opaque_static_meshes(root):
    meshes = get_opaque_meshes_for_merge(root)
    if not meshes:
        raise RuntimeError("No opaque static meshes available for merge.")

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
    merged["no_merge"] = False
    set_flat_shading(merged)
    return merged


def validate_after_merge(root, spray_point):
    expected_meshes = (
        ROOT_NAME + "_Static",
        "ChiliTank_GlassShell",
        "ChiliTank_GlowCore",
    )
    for name in expected_meshes:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH" or obj.parent != root:
            raise RuntimeError(f"Missing or mis-parented export mesh: {name}")

    if spray_point.parent != root:
        raise RuntimeError("SprayPoint hierarchy damaged after merge.")

    meshes = get_meshes_under_root(root)
    low, high = bbox_world_all(meshes)
    dimensions = high - low
    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
        f"  Export mesh nodes: {len(meshes)}\n"
        f"  SprayPoint preserved: {spray_point.name}\n"
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
    print("\n=== Generating Chef Chili Marker Sprayer ===\n")

    root, spray_point = build_chili_marker_sprayer()
    validate_before_merge(root, spray_point)

    if MERGE_OPAQUE_STATIC_MESHES:
        merge_opaque_static_meshes(root)

    validate_after_merge(root, spray_point)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nGodot use:")
    print(" - Rotate/position the root from its primary hand grip.")
    print(" - Spawn marking spray or ray effects from child node SprayPoint.")
    print(" - Spray direction is local -Y in Blender and intended local -Z in Godot.")


if __name__ == "__main__":
    main()
