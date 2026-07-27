# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Food War / Farm Town - Handheld Fertilizer Injector
#
# Generates one GLB:
#   FTF_Tool_FertilizerInjector_White_v2.glb
#
# DESIGN
# - Handheld fertilizer injector / sprayer
# - White main shell
# - Chunky functional silhouette, can visually sit in the same family
#   as previous destroy-cannon / energy-gun style tools
# - Transparent green nutrient tank
# - Forward spray tube and flared nozzle
# - Grip, trigger, hose, gauge, tank caps, and connector rings
#
# ASSET STANDARD
# - Blender authoring forward: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at main hand grip position: (0, 0, 0)
# - No cameras / lights / text
# - No collision meshes
# - Static visual meshes are merged before export
#
# VALIDATION
# - Root remains at origin
# - No cameras/lights/collision meshes
# - No negative/zero scale
# - Attachment audit checks important parts are connected or close enough
#   so there are no obvious floating components.
#
# OUTPUT
#   generated_farmtown_tools/FTF_Tool_FertilizerInjector_White_v2.glb
#
# Run:
#   blender --background --factory-startup --python generate_foodwar_fertilizer_injector_v2.py
# ---------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector


# ---------------------------------------------------------------------
# PATHS / CONSTANTS
# ---------------------------------------------------------------------

SCRIPT_DIR = (
    os.path.dirname(os.path.abspath(__file__))
    if "__file__" in globals()
    else os.getcwd()
)
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_tools")
OUTPUT_FILE = "FTF_Tool_FertilizerInjector_White_v2.glb"

ROOT_NAME = "FTF_Tool_FertilizerInjector_White_v2"
COLLECTION_NAME = "COL_" + ROOT_NAME

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"


# ---------------------------------------------------------------------
# SCENE / MATERIALS
# ---------------------------------------------------------------------

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


def make_material(name, color, roughness=0.75, metallic=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, alpha)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        # Blender 4.2+ / 4.4 compatibility.
        if hasattr(mat, "surface_render_method"):
            try:
                enum_items = mat.bl_rna.properties["surface_render_method"].enum_items.keys()
                if "BLENDED" in enum_items:
                    mat.surface_render_method = "BLENDED"
                elif "DITHERED" in enum_items:
                    mat.surface_render_method = "DITHERED"
            except Exception as exc:
                print(f"[WARN] Could not set transparency mode on {name}: {exc}")
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"

    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def build_materials():
    return {
        "white": make_material("MAT_FI_WhiteShell", (0.92, 0.93, 0.90), 0.68),
        "white_alt": make_material("MAT_FI_WarmWhitePanel", (0.82, 0.84, 0.81), 0.72),
        "dark": make_material("MAT_FI_DarkFrame", (0.12, 0.14, 0.15), 0.78),
        "rubber": make_material("MAT_FI_RubberGrip", (0.035, 0.040, 0.040), 0.90),
        "metal": make_material("MAT_FI_Metal", (0.34, 0.36, 0.36), 0.56, 0.12),
        "green": make_material("MAT_FI_FertilizerGreen", (0.36, 0.82, 0.36), 0.58),
        "green_dark": make_material("MAT_FI_DarkGreen", (0.10, 0.35, 0.17), 0.72),
        "tank": make_material("MAT_FI_TranslucentTank", (0.62, 0.88, 0.66), 0.22, 0.02, alpha=0.55),
        "gauge": make_material("MAT_FI_GaugeFace", (0.86, 0.92, 0.88), 0.42),
        "black": make_material("MAT_FI_BlackDetails", (0.02, 0.025, 0.025), 0.84),
    }


# ---------------------------------------------------------------------
# COLLECTION / OBJECT HELPERS
# ---------------------------------------------------------------------

def get_or_create_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
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
    for poly in obj.data.polygons:
        poly.use_smooth = False


def add_bevel(obj, width=0.01, segments=1):
    mod = obj.modifiers.new("LowPolyBevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return mod


def apply_transforms_and_modifiers(obj):
    if obj.type != "MESH":
        return
    set_active(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for mod in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError as exc:
            print(f"[WARN] Could not apply modifier {mod.name} on {obj.name}: {exc}")


def create_root(collection):
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.30
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "HandheldTool"
    root["tool_category"] = "FertilizerInjector"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "PrimaryHandGrip"
    root["has_collision_mesh"] = False
    root["effects_baked_into_model"] = False
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES

    collection.objects.link(root)
    return root


# ---------------------------------------------------------------------
# GEOMETRY HELPERS
# ---------------------------------------------------------------------

def add_cube(name, location, dimensions, material, parent, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), no_merge=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj.parent = parent
    obj["no_merge"] = bool(no_merge)
    move_to_collection(obj, collection)
    return obj


def add_cylinder_between(name, p0, p1, radius, material, parent, collection, vertices=16, bevel=0.0):
    p0 = Vector(p0)
    p1 = Vector(p1)
    mid = (p0 + p1) * 0.5
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")

    quat = direction.to_track_quat("Z", "Y")
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        location=mid,
        rotation=quat.to_euler(),
    )
    obj = bpy.context.object
    obj.name = name

    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_cone_between(name, p0, p1, radius1, radius2, material, parent, collection, vertices=20, bevel=0.0):
    p0 = Vector(p0)
    p1 = Vector(p1)
    mid = (p0 + p1) * 0.5
    direction = p1 - p0
    length = direction.length
    if length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cone: {name}")

    quat = direction.to_track_quat("Z", "Y")
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius1,
        radius2=radius2,
        depth=length,
        location=mid,
        rotation=quat.to_euler(),
    )
    obj = bpy.context.object
    obj.name = name

    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_lowpoly_sphere(name, location, radius, material, parent, collection, subdivisions=1, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=radius,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def add_ring_along_y(name, y, z, radius_major, radius_minor, material, parent, collection, x=0.0):
    # Torus default hole axis is Z. Rotate 90 degrees around X to make hole axis Y.
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius_major,
        minor_radius=radius_minor,
        major_segments=20,
        minor_segments=6,
        location=(x, y, z),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name

    assign_material(obj, material)
    set_flat_shading(obj)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


# ---------------------------------------------------------------------
# BUILD TOOL
# ---------------------------------------------------------------------

def build_fertilizer_injector():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    # Blender -Y is forward / spray direction.
    # Root is at primary grip position.

    # Hand grip and socket.
    add_cube(
        "Grip_RubberCore",
        (0.0, 0.00, -0.30),
        (0.34, 0.36, 0.98),
        mats["rubber"],
        root, collection,
        bevel=0.035,
        rotation=(math.radians(-6.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_WhiteBackPlate",
        (0.0, 0.12, -0.25),
        (0.42, 0.11, 0.90),
        mats["white_alt"],
        root, collection,
        bevel=0.020,
        rotation=(math.radians(-6.0), 0.0, 0.0),
    )
    add_cube(
        "RearBody_GripSocket",
        (0.0, -0.02, 0.42),
        (0.64, 0.40, 0.52),
        mats["white_alt"],
        root, collection,
        bevel=0.040,
    )

    # Main pressure housing.
    add_cube(
        "MainBody_WhitePressureHousing",
        (0.0, -0.74, 0.46),
        (0.76, 1.46, 0.54),
        mats["white"],
        root, collection,
        bevel=0.055,
    )

    # Bottom rail connects grip socket and main body.
    add_cube(
        "Bottom_DarkUtilityRail",
        (0.0, -0.69, 0.16),
        (0.46, 1.16, 0.13),
        mats["dark"],
        root, collection,
        bevel=0.012,
    )

    # Trigger guard and trigger.
    add_cube(
        "Trigger_Guard_TopBridge",
        (0.0, -0.22, 0.18),
        (0.50, 0.14, 0.12),
        mats["dark"],
        root, collection,
        bevel=0.010,
    )
    add_cube(
        "Trigger_Guard_FrontLeg",
        (0.0, -0.42, -0.04),
        (0.42, 0.11, 0.48),
        mats["dark"],
        root, collection,
        bevel=0.012,
    )
    add_cube(
        "Trigger_CurvedBlock",
        (0.0, -0.24, -0.03),
        (0.18, 0.10, 0.36),
        mats["green_dark"],
        root, collection,
        bevel=0.030,
        rotation=(math.radians(-10.0), 0.0, 0.0),
    )

    # Transparent fertilizer tank on top.
    add_cylinder_between(
        "Tank_TranslucentNutrientCylinder",
        (0.0, 0.02, 1.02),
        (0.0, -1.10, 1.02),
        0.32,
        mats["tank"],
        root, collection,
        vertices=20,
        bevel=0.006,
    )
    add_cylinder_between(
        "Tank_RearWhiteCap",
        (0.0, 0.04, 1.02),
        (0.0, 0.18, 1.02),
        0.33,
        mats["white"],
        root, collection,
        vertices=20,
        bevel=0.004,
    )
    add_cylinder_between(
        "Tank_FrontGreenCap",
        (0.0, -1.08, 1.02),
        (0.0, -1.23, 1.02),
        0.33,
        mats["green"],
        root, collection,
        vertices=20,
        bevel=0.004,
    )

    # Tank straps connect tank to body.
    add_cube(
        "TankMount_RearStrap",
        (0.0, -0.12, 0.79),
        (0.90, 0.13, 0.24),
        mats["white_alt"],
        root, collection,
        bevel=0.016,
    )
    add_cube(
        "TankMount_FrontStrap",
        (0.0, -0.88, 0.79),
        (0.90, 0.13, 0.24),
        mats["white_alt"],
        root, collection,
        bevel=0.016,
    )

    # Forward barrel, rings and nozzle.
    # Front connector socket attaches to the front of the white body.
    # The spray tube starts outside this socket, so it no longer embeds into the main shell.
    add_cylinder_between(
        "FrontBarrelSocket_WhiteConnector",
        (0.0, -1.45, 0.46),
        (0.0, -1.62, 0.46),
        0.220,
        mats["white_alt"],
        root, collection,
        vertices=18,
        bevel=0.004,
    )
    add_cylinder_between(
        "Barrel_WhiteSprayTube",
        (0.0, -1.62, 0.46),
        (0.0, -2.12, 0.46),
        0.145,
        mats["white"],
        root, collection,
        vertices=18,
        bevel=0.004,
    )
    add_ring_along_y(
        "Barrel_GreenFlowRing",
        -1.47,
        0.46,
        0.176,
        0.020,
        mats["green"],
        root, collection,
    )
    add_ring_along_y(
        "Barrel_DarkSealRing",
        -1.84,
        0.46,
        0.168,
        0.018,
        mats["dark"],
        root, collection,
    )
    add_cylinder_between(
        "Nozzle_Neck",
        (0.0, -2.06, 0.46),
        (0.0, -2.34, 0.46),
        0.105,
        mats["metal"],
        root, collection,
        vertices=18,
        bevel=0.004,
    )
    add_cone_between(
        "Nozzle_FlaredSprayHead",
        (0.0, -2.30, 0.46),
        (0.0, -2.67, 0.46),
        0.23,
        0.11,
        mats["white_alt"],
        root, collection,
        vertices=22,
        bevel=0.004,
    )
    add_cylinder_between(
        "Nozzle_FrontGreenFace",
        (0.0, -2.67, 0.46),
        (0.0, -2.735, 0.46),
        0.22,
        mats["green"],
        root, collection,
        vertices=22,
        bevel=0.002,
    )

    # Outlet holes.
    outlet_positions = [
        (0.00, 0.00),
        (0.09, 0.06),
        (-0.09, 0.06),
        (0.09, -0.06),
        (-0.09, -0.06),
    ]
    for i, (x, z_off) in enumerate(outlet_positions):
        add_cylinder_between(
            f"Nozzle_OutletDot_{i:02d}",
            (x, -2.735, 0.46 + z_off),
            (x, -2.765, 0.46 + z_off),
            0.022,
            mats["black"],
            root, collection,
            vertices=10,
        )

    # Side pressure gauge, attached on right side.
    add_cylinder_between(
        "Gauge_DarkRim",
        (0.355, -0.54, 0.58),
        (0.462, -0.54, 0.58),
        0.185,
        mats["dark"],
        root, collection,
        vertices=20,
        bevel=0.002,
    )
    add_cylinder_between(
        "Gauge_Face",
        (0.456, -0.54, 0.58),
        (0.492, -0.54, 0.58),
        0.150,
        mats["gauge"],
        root, collection,
        vertices=20,
    )
    # Needle sits directly on the gauge face plane.
    # Gauge face normal is along X, so the needle must rotate in the YZ plane
    # around the X axis instead of rotating around Z.
    add_cube(
        "Gauge_Needle",
        (0.498, -0.515, 0.615),
        (0.012, 0.018, 0.155),
        mats["green_dark"],
        root, collection,
        bevel=0.0015,
        rotation=(math.radians(-28.0), 0.0, 0.0),
    )

    # Hose and ports.
    hose_points = [
        Vector((0.28, -0.96, 0.93)),
        Vector((0.42, -0.93, 0.75)),
        Vector((0.42, -1.30, 0.58)),
        Vector((0.24, -1.60, 0.46)),
    ]
    for i in range(len(hose_points) - 1):
        add_cylinder_between(
            f"HoseSegment_{i:02d}",
            hose_points[i],
            hose_points[i + 1],
            0.046,
            mats["rubber"],
            root, collection,
            vertices=10,
            bevel=0.002,
        )
    for i, p in enumerate(hose_points):
        add_lowpoly_sphere(
            f"HoseJoint_{i:02d}",
            p,
            0.064,
            mats["rubber"],
            root, collection,
            subdivisions=1,
        )

    add_cylinder_between(
        "TankOutlet_GreenPort",
        (0.24, -0.96, 0.99),
        (0.34, -0.96, 0.90),
        0.060,
        mats["green_dark"],
        root, collection,
        vertices=12,
        bevel=0.002,
    )
    add_cylinder_between(
        "BodyHosePort",
        (0.34, -1.54, 0.46),
        (0.18, -1.60, 0.46),
        0.060,
        mats["metal"],
        root, collection,
        vertices=12,
        bevel=0.002,
    )

    # Raised leaf mark, geometric not text.
    add_lowpoly_sphere(
        "SideLeafMark_Left",
        (-0.386, -0.58, 0.60),
        0.105,
        mats["green"],
        root, collection,
        subdivisions=1,
        scale=(0.16, 0.95, 0.52),
    )
    add_lowpoly_sphere(
        "SideLeafMark_Right",
        (-0.388, -0.46, 0.53),
        0.085,
        mats["green_dark"],
        root, collection,
        subdivisions=1,
        scale=(0.16, 0.95, 0.52),
    )

    # Rear service panel.
    add_cube(
        "Rear_ServicePanel",
        (0.0, 0.225, 0.46),
        (0.50, 0.08, 0.36),
        mats["green_dark"],
        root, collection,
        bevel=0.012,
    )

    return root


# ---------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def get_static_meshes_for_merge(root):
    result = []
    for obj in get_meshes_under_root(root):
        if obj.get("no_merge", False):
            continue
        result.append(obj)
    return result


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


def aabb_distance(obj_a, obj_b):
    a_min, a_max = world_bbox(obj_a)
    b_min, b_max = world_bbox(obj_b)

    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)

    return math.sqrt(dx * dx + dy * dy + dz * dz)


def validate_attachment_pairs():
    # Practical floating-part audit.
    # Major pieces must overlap or be very close to their intended connector.
    pairs = [
        ("Grip_RubberCore", "RearBody_GripSocket", 0.06),
        ("Grip_WhiteBackPlate", "RearBody_GripSocket", 0.06),
        ("RearBody_GripSocket", "MainBody_WhitePressureHousing", 0.04),
        ("Bottom_DarkUtilityRail", "MainBody_WhitePressureHousing", 0.08),
        ("Bottom_DarkUtilityRail", "RearBody_GripSocket", 0.08),

        ("Trigger_Guard_TopBridge", "MainBody_WhitePressureHousing", 0.06),
        ("Trigger_Guard_FrontLeg", "Trigger_Guard_TopBridge", 0.08),
        ("Trigger_CurvedBlock", "Trigger_Guard_TopBridge", 0.08),

        ("Tank_TranslucentNutrientCylinder", "TankMount_RearStrap", 0.06),
        ("Tank_TranslucentNutrientCylinder", "TankMount_FrontStrap", 0.06),
        ("TankMount_RearStrap", "MainBody_WhitePressureHousing", 0.08),
        ("TankMount_FrontStrap", "MainBody_WhitePressureHousing", 0.08),
        ("Tank_RearWhiteCap", "Tank_TranslucentNutrientCylinder", 0.05),
        ("Tank_FrontGreenCap", "Tank_TranslucentNutrientCylinder", 0.05),

        ("FrontBarrelSocket_WhiteConnector", "MainBody_WhitePressureHousing", 0.08),
        ("Barrel_WhiteSprayTube", "FrontBarrelSocket_WhiteConnector", 0.08),
        ("Nozzle_Neck", "Barrel_WhiteSprayTube", 0.08),
        ("Nozzle_FlaredSprayHead", "Nozzle_Neck", 0.08),
        ("Nozzle_FrontGreenFace", "Nozzle_FlaredSprayHead", 0.05),

        ("Gauge_DarkRim", "MainBody_WhitePressureHousing", 0.05),
        ("Gauge_Face", "Gauge_DarkRim", 0.05),
        ("Gauge_Needle", "Gauge_Face", 0.07),

        ("TankOutlet_GreenPort", "Tank_TranslucentNutrientCylinder", 0.10),
        ("TankOutlet_GreenPort", "HoseJoint_00", 0.10),
        ("BodyHosePort", "FrontBarrelSocket_WhiteConnector", 0.10),
        ("BodyHosePort", "HoseJoint_03", 0.10),

        ("HoseSegment_00", "HoseJoint_00", 0.04),
        ("HoseSegment_00", "HoseJoint_01", 0.04),
        ("HoseSegment_01", "HoseJoint_01", 0.04),
        ("HoseSegment_01", "HoseJoint_02", 0.04),
        ("HoseSegment_02", "HoseJoint_02", 0.04),
        ("HoseSegment_02", "HoseJoint_03", 0.04),

        ("SideLeafMark_Left", "MainBody_WhitePressureHousing", 0.04),
        ("SideLeafMark_Right", "MainBody_WhitePressureHousing", 0.04),
        ("Rear_ServicePanel", "RearBody_GripSocket", 0.05),
    ]

    failures = []
    for a_name, b_name, allowed_gap in pairs:
        a = get_mesh_by_name(a_name)
        b = get_mesh_by_name(b_name)
        dist = aabb_distance(a, b)
        if dist > allowed_gap:
            failures.append(f"{a_name} -> {b_name}: gap {dist:.4f}m > allowed {allowed_gap:.4f}m")

    if failures:
        raise RuntimeError("FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures))

    print(f"[VALID] Attachment audit passed: {len(pairs)} connection checks.")


def detect_suspicious_collision_names():
    bad = []
    for obj in bpy.context.scene.objects:
        n = obj.name.lower()
        if n.startswith("ucx") or "collision" in n or n.startswith("col_"):
            # The collection name starts with COL_, but no mesh collision objects should.
            if obj.type == "MESH":
                bad.append(obj.name)
    if bad:
        raise RuntimeError("VALIDATION FAILED: collision-like mesh names found: " + ", ".join(bad))


def bbox_world_all(meshes):
    lows = []
    highs = []
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lows.append(p)
            highs.append(p)
    low = Vector((min(v.x for v in lows), min(v.y for v in lows), min(v.z for v in lows)))
    high = Vector((max(v.x for v in highs), max(v.y for v in highs), max(v.z for v in highs)))
    return low, high


def validate_asset_before_merge(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root/origin must remain at main hand grip position (0,0,0).")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain: " + ", ".join(bad_scene))

    detect_suspicious_collision_names()

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root.")

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0 or obj.scale.y < 0 or obj.scale.z < 0:
            failures.append("negative scale: " + obj.name)
    if failures:
        raise RuntimeError("VALIDATION FAILED:\n- " + "\n- ".join(failures))

    validate_attachment_pairs()

    bpy.context.view_layer.update()
    low, high = bbox_world_all(meshes)
    dims = high - low

    tri_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tri_count += len(obj.data.loop_triangles)

    print(
        f"[VALID BEFORE MERGE] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {tri_count}\n"
        f"  Forward: Blender {AUTHORING_FORWARD_AXIS}, intended Godot {INTENDED_GODOT_FORWARD_AXIS}\n"
        f"  Origin: primary hand grip at root (0,0,0)\n"
    )


def validate_asset_after_merge(root):
    if root.type != "EMPTY":
        raise RuntimeError("VALIDATION FAILED: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError("VALIDATION FAILED: root/origin moved after merge.")

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("VALIDATION FAILED: no meshes under root after merge.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("VALIDATION FAILED: cameras/lights remain after merge: " + ", ".join(bad_scene))

    detect_suspicious_collision_names()

    bpy.context.view_layer.update()
    low, high = bbox_world_all(meshes)
    dims = high - low

    tri_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tri_count += len(obj.data.loop_triangles)

    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dims.x:.2f}m x {dims.y:.2f}m x {dims.z:.2f}m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {tri_count}\n"
    )


# ---------------------------------------------------------------------
# MERGE / EXPORT
# ---------------------------------------------------------------------

def merge_static_meshes(root):
    meshes = get_static_meshes_for_merge(root)
    if not meshes:
        raise RuntimeError("No static meshes available for merge.")

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


# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------

if __name__ == "__main__":
    print("\n=== Generating Handheld Fertilizer Injector ===\n")

    root = build_fertilizer_injector()

    validate_asset_before_merge(root)

    if MERGE_STATIC_MESHES:
        merge_static_meshes(root)

    validate_asset_after_merge(root)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nNotes:")
    print(" - White handheld fertilizer injector.")
    print(" - Root/origin is at the hand grip.")
    print(" - Blender forward is -Y; intended Godot forward is -Z after GLB import.")
    print(" - Attachment audit passed before merge, so no obvious floating parts should remain.")
