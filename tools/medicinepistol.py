# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# FarmWar / Farm Town - Handheld Medicine Pistol
#
# Generates one GLB:
#   FTF_Tool_MedicinePistol_BlackBlue.glb
#
# DESIGN
# - Handheld medicine pistol for firing remote medicine bullets
# - Black gun body
# - A visible blue glowing medicine tube is embedded in the middle of the gun body
# - Forward medicine barrel / injector muzzle
# - Grip, trigger, trigger guard, top rail, rear cap, front cap, side clamps
#
# ASSET STANDARD
# - Blender authoring forward: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - Root/origin at primary hand grip position: (0, 0, 0)
# - No cameras / lights / text
# - No collision meshes
# - Static visual meshes are merged before export
#
# VALIDATION
# - Root remains at origin
# - No cameras/lights/collision meshes
# - No negative/zero scale
# - Attachment audit checks major components are connected or close enough
#   so there are no obvious floating components.
#
# OUTPUT
#   generated_farmtown_tools/FTF_Tool_MedicinePistol_BlackBlue.glb
#
# Run:
#   blender --background --factory-startup --python generate_farmwar_medicine_pistol.py
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
OUTPUT_FILE = "FTF_Tool_MedicinePistol_BlackBlue.glb"

ROOT_NAME = "FTF_Tool_MedicinePistol_BlackBlue"
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


def make_material(name, color, roughness=0.75, metallic=0.0, alpha=1.0, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")

    if emission is not None and emission_strength > 0.0:
        # Use a true emission shader for a reliable blue glow material in GLB.
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (*emission, alpha)
        emit.inputs["Strength"].default_value = emission_strength
        links.new(emit.outputs["Emission"], out.inputs["Surface"])
    else:
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

    if alpha < 1.0:
        mat.diffuse_color = (*color, alpha)
    else:
        mat.diffuse_color = (*color, 1.0)

    return mat


def build_materials():
    return {
        "black": make_material("MAT_MP_BlackBody", (0.018, 0.020, 0.022), 0.80, 0.08),
        "black_alt": make_material("MAT_MP_SoftBlackPanel", (0.055, 0.060, 0.065), 0.82, 0.04),
        "rubber": make_material("MAT_MP_RubberGrip", (0.025, 0.027, 0.028), 0.92, 0.0),
        "metal": make_material("MAT_MP_Gunmetal", (0.28, 0.31, 0.33), 0.55, 0.22),
        "dark_metal": make_material("MAT_MP_DarkMetal", (0.10, 0.11, 0.12), 0.60, 0.28),
        "blue": make_material("MAT_MP_MedicineBlue", (0.10, 0.48, 0.95), 0.35, 0.02),
        "blue_dark": make_material("MAT_MP_DarkMedicalBlue", (0.035, 0.16, 0.36), 0.55, 0.08),
        "glow_blue": make_material(
            "MAT_MP_GlowingBlueMedicine",
            (0.18, 0.70, 1.0),
            0.18,
            0.0,
            alpha=1.0,
            emission=(0.18, 0.72, 1.0),
            emission_strength=1.8,
        ),
        "glass_blue": make_material("MAT_MP_ClearBlueTubeShell", (0.24, 0.72, 1.0), 0.20, 0.02, alpha=0.55),
        "white_mark": make_material("MAT_MP_WhiteMedicalMark", (0.88, 0.94, 0.96), 0.62, 0.0),
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
    root["tool_category"] = "MedicinePistol"
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


def add_cone_between(name, p0, p1, radius1, radius2, material, parent, collection, vertices=16, bevel=0.0):
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

def build_medicine_pistol():
    if CLEAR_SCENE:
        clear_scene()

    configure_scene()
    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)

    # Blender -Y is forward / firing direction.
    # Root is at the primary hand grip.

    # Grip and lower frame.
    add_cube(
        "Grip_RubberCore",
        (0.0, 0.03, -0.30),
        (0.31, 0.34, 0.92),
        mats["rubber"],
        root, collection,
        bevel=0.035,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_Backstrap",
        (0.0, 0.17, -0.27),
        (0.38, 0.10, 0.80),
        mats["black_alt"],
        root, collection,
        bevel=0.018,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_BaseCap",
        (0.0, 0.12, -0.79),
        (0.42, 0.36, 0.12),
        mats["black_alt"],
        root, collection,
        bevel=0.025,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )

    # Rear receiver block attached to grip.
    add_cube(
        "RearReceiver_Black",
        (0.0, -0.12, 0.35),
        (0.62, 0.48, 0.50),
        mats["black"],
        root, collection,
        bevel=0.040,
    )

    # Middle body built as a visible open frame around the blue medicine tube.
    # It should look like the tube is embedded into the gun body but still visible.
    add_cube(
        "Body_UpperRail",
        (0.0, -0.58, 0.66),
        (0.70, 1.20, 0.22),
        mats["black"],
        root, collection,
        bevel=0.030,
    )
    add_cube(
        "Body_LowerRail",
        (0.0, -0.58, 0.21),
        (0.64, 1.12, 0.18),
        mats["black"],
        root, collection,
        bevel=0.025,
    )
    add_cube(
        "Body_LeftSideFrame",
        (-0.36, -0.58, 0.43),
        (0.10, 1.10, 0.42),
        mats["black_alt"],
        root, collection,
        bevel=0.018,
    )
    add_cube(
        "Body_RightSideFrame",
        (0.36, -0.58, 0.43),
        (0.10, 1.10, 0.42),
        mats["black_alt"],
        root, collection,
        bevel=0.018,
    )

    # Front receiver and barrel socket.
    add_cube(
        "FrontReceiver_BlackSocket",
        (0.0, -1.18, 0.42),
        (0.66, 0.36, 0.46),
        mats["black"],
        root, collection,
        bevel=0.035,
    )

    # Blue medicine storage tube embedded in the middle body.
    add_cylinder_between(
        "MedicineTube_GlassShell",
        (0.0, 0.00, 0.43),
        (0.0, -1.07, 0.43),
        0.175,
        mats["glass_blue"],
        root, collection,
        vertices=22,
        bevel=0.004,
    )
    add_cylinder_between(
        "MedicineTube_GlowingBlueCore",
        (0.0, -0.05, 0.43),
        (0.0, -1.02, 0.43),
        0.115,
        mats["glow_blue"],
        root, collection,
        vertices=18,
        bevel=0.002,
    )
    add_cylinder_between(
        "MedicineTube_RearCap",
        (0.0, 0.02, 0.43),
        (0.0, 0.12, 0.43),
        0.185,
        mats["dark_metal"],
        root, collection,
        vertices=20,
        bevel=0.003,
    )
    add_cylinder_between(
        "MedicineTube_FrontCap",
        (0.0, -1.07, 0.43),
        (0.0, -1.18, 0.43),
        0.185,
        mats["dark_metal"],
        root, collection,
        vertices=20,
        bevel=0.003,
    )

    # Tube clamp rings / braces.
    for i, y in enumerate((-0.18, -0.58, -0.96)):
        add_ring_along_y(
            f"TubeClamp_BlackRing_{i:02d}",
            y,
            0.43,
            0.190,
            0.020,
            mats["black"],
            root, collection,
        )
        add_cube(
            f"TubeClamp_TopBrace_{i:02d}",
            (0.0, y, 0.615),
            (0.42, 0.055, 0.075),
            mats["black"],
            root, collection,
            bevel=0.006,
        )
        add_cube(
            f"TubeClamp_BottomBrace_{i:02d}",
            (0.0, y, 0.245),
            (0.38, 0.055, 0.065),
            mats["black"],
            root, collection,
            bevel=0.006,
        )

    # Forward medicine barrel and injector muzzle.
    add_cylinder_between(
        "Barrel_DarkMedicineTube",
        (0.0, -1.36, 0.42),
        (0.0, -1.95, 0.42),
        0.120,
        mats["dark_metal"],
        root, collection,
        vertices=18,
        bevel=0.003,
    )
    add_ring_along_y(
        "Barrel_BlueDoseRing",
        -1.52,
        0.42,
        0.132,
        0.018,
        mats["blue"],
        root, collection,
    )
    add_ring_along_y(
        "Barrel_BlackSealRing",
        -1.78,
        0.42,
        0.130,
        0.017,
        mats["black"],
        root, collection,
    )
    add_cone_between(
        "Muzzle_InjectorCone",
        (0.0, -1.90, 0.42),
        (0.0, -2.18, 0.42),
        0.185,
        0.105,
        mats["metal"],
        root, collection,
        vertices=20,
        bevel=0.003,
    )
    add_cylinder_between(
        "Muzzle_BlueExitCore",
        (0.0, -2.18, 0.42),
        (0.0, -2.24, 0.42),
        0.082,
        mats["glow_blue"],
        root, collection,
        vertices=18,
        bevel=0.001,
    )

    # Small front sight and rear sight.
    add_cube(
        "FrontSight_Black",
        (0.0, -1.78, 0.72),
        (0.10, 0.12, 0.09),
        mats["black_alt"],
        root, collection,
        bevel=0.006,
    )
    add_cube(
        "RearSight_Black",
        (0.0, 0.08, 0.68),
        (0.16, 0.09, 0.08),
        mats["black_alt"],
        root, collection,
        bevel=0.006,
    )

    # Trigger and trigger guard.
    add_cube(
        "TriggerGuard_TopBridge",
        (0.0, -0.17, 0.07),
        (0.48, 0.16, 0.10),
        mats["black"],
        root, collection,
        bevel=0.010,
    )
    add_cube(
        "TriggerGuard_FrontLeg",
        (0.0, -0.42, -0.12),
        (0.42, 0.10, 0.42),
        mats["black"],
        root, collection,
        bevel=0.012,
    )
    add_cube(
        "Trigger_BlueDoseLever",
        (0.0, -0.23, -0.10),
        (0.16, 0.08, 0.32),
        mats["blue_dark"],
        root, collection,
        bevel=0.026,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )

    # Side medicine fill port and dose dial.
    add_cylinder_between(
        "SideFillPort_Blue",
        (0.355, -0.82, 0.54),
        (0.455, -0.82, 0.54),
        0.075,
        mats["blue"],
        root, collection,
        vertices=14,
        bevel=0.002,
    )
    add_cylinder_between(
        "DoseDial_Rim",
        (-0.355, -0.28, 0.50),
        (-0.455, -0.28, 0.50),
        0.120,
        mats["dark_metal"],
        root, collection,
        vertices=16,
        bevel=0.002,
    )
    add_cylinder_between(
        "DoseDial_BlueFace",
        (-0.455, -0.28, 0.50),
        (-0.492, -0.28, 0.50),
        0.088,
        mats["blue"],
        root, collection,
        vertices=16,
    )

    # Medical cross mark made from geometry, not text, on the left side.
    add_cube(
        "MedicalCross_Vertical",
        (-0.416, -0.66, 0.66),
        (0.026, 0.035, 0.185),
        mats["white_mark"],
        root, collection,
        bevel=0.002,
    )
    add_cube(
        "MedicalCross_Horizontal",
        (-0.418, -0.66, 0.66),
        (0.028, 0.150, 0.045),
        mats["white_mark"],
        root, collection,
        bevel=0.002,
    )

    # Rear battery/dose pack attached to rear receiver.
    add_cube(
        "RearDosePack",
        (0.0, 0.23, 0.42),
        (0.52, 0.16, 0.38),
        mats["black_alt"],
        root, collection,
        bevel=0.025,
    )
    add_cylinder_between(
        "RearDosePack_BlueCell",
        (-0.16, 0.315, 0.42),
        (0.16, 0.315, 0.42),
        0.055,
        mats["glow_blue"],
        root, collection,
        vertices=12,
        bevel=0.001,
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
    # Important pieces must overlap or be very close to their intended connector.
    pairs = [
        ("Grip_RubberCore", "RearReceiver_Black", 0.08),
        ("Grip_Backstrap", "Grip_RubberCore", 0.05),
        ("Grip_BaseCap", "Grip_RubberCore", 0.08),

        ("RearReceiver_Black", "Body_UpperRail", 0.08),
        ("RearReceiver_Black", "Body_LowerRail", 0.08),
        ("Body_UpperRail", "Body_LeftSideFrame", 0.08),
        ("Body_UpperRail", "Body_RightSideFrame", 0.08),
        ("Body_LowerRail", "Body_LeftSideFrame", 0.08),
        ("Body_LowerRail", "Body_RightSideFrame", 0.08),
        ("Body_UpperRail", "FrontReceiver_BlackSocket", 0.08),
        ("Body_LowerRail", "FrontReceiver_BlackSocket", 0.08),

        ("MedicineTube_GlassShell", "MedicineTube_RearCap", 0.05),
        ("MedicineTube_GlassShell", "MedicineTube_FrontCap", 0.05),
        ("MedicineTube_GlowingBlueCore", "MedicineTube_GlassShell", 0.03),
        ("MedicineTube_FrontCap", "FrontReceiver_BlackSocket", 0.08),
        ("MedicineTube_RearCap", "RearReceiver_Black", 0.08),

        ("TubeClamp_BlackRing_00", "MedicineTube_GlassShell", 0.04),
        ("TubeClamp_BlackRing_01", "MedicineTube_GlassShell", 0.04),
        ("TubeClamp_BlackRing_02", "MedicineTube_GlassShell", 0.04),
        ("TubeClamp_TopBrace_00", "Body_UpperRail", 0.06),
        ("TubeClamp_BottomBrace_00", "Body_LowerRail", 0.06),
        ("TubeClamp_TopBrace_01", "Body_UpperRail", 0.06),
        ("TubeClamp_BottomBrace_01", "Body_LowerRail", 0.06),
        ("TubeClamp_TopBrace_02", "Body_UpperRail", 0.06),
        ("TubeClamp_BottomBrace_02", "Body_LowerRail", 0.06),

        ("Barrel_DarkMedicineTube", "FrontReceiver_BlackSocket", 0.08),
        ("Muzzle_InjectorCone", "Barrel_DarkMedicineTube", 0.08),
        ("Muzzle_BlueExitCore", "Muzzle_InjectorCone", 0.05),
        ("Barrel_BlueDoseRing", "Barrel_DarkMedicineTube", 0.04),
        ("Barrel_BlackSealRing", "Barrel_DarkMedicineTube", 0.04),

        ("TriggerGuard_TopBridge", "RearReceiver_Black", 0.08),
        ("TriggerGuard_FrontLeg", "TriggerGuard_TopBridge", 0.08),
        ("Trigger_BlueDoseLever", "TriggerGuard_TopBridge", 0.08),

        ("FrontSight_Black", "Body_UpperRail", 0.08),
        ("RearSight_Black", "RearReceiver_Black", 0.08),
        ("SideFillPort_Blue", "Body_RightSideFrame", 0.06),
        ("DoseDial_Rim", "Body_LeftSideFrame", 0.06),
        ("DoseDial_BlueFace", "DoseDial_Rim", 0.05),

        ("MedicalCross_Vertical", "Body_LeftSideFrame", 0.04),
        ("MedicalCross_Horizontal", "Body_LeftSideFrame", 0.04),
        ("RearDosePack", "RearReceiver_Black", 0.08),
        ("RearDosePack_BlueCell", "RearDosePack", 0.06),
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
            # Collection name starts with COL_, but no mesh collision objects should.
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
    print("\n=== Generating Handheld Medicine Pistol ===\n")

    root = build_medicine_pistol()

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
    print(" - Black handheld medicine pistol.")
    print(" - Blue glowing medicine tube is embedded visibly in the middle frame.")
    print(" - Root/origin is at the hand grip.")
    print(" - Blender forward is -Y; intended Godot forward is -Z after GLB import.")
    print(" - Attachment audit passed before merge, so no obvious floating parts should remain.")
