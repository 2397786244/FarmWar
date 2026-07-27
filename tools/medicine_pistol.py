# Blender 4.x / 5.x
# ---------------------------------------------------------------------
# Food War / Farm Town - Glock-Style Medicine Pistol V4
#
# Generates one GLB:
#   FTF_Tool_MedicinePistol_GlockStyle_BlackBlue_v4.glb
#
# DESIGN
# - Stylized medicine pistol inspired by a blocky polymer handgun silhouette
# - NOT a mechanically accurate firearm model
# - Black slide, black polymer-style frame and angled grip
# - Short barrel / muzzle as a game prop
# - Upper slide and lower frame meet as one continuous handgun body
# - Blue glowing medicine tube is half-recessed into the POSITIVE-X OUTER side
#   of the lower frame: clearly exposed, but not a detached tank
# - Front and rear sights overlap the slide top, so neither sight floats
# - No fertilizer-sprayer tank, no hose, no external pressure gauge
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
#   generated_farmtown_tools/FTF_Tool_MedicinePistol_GlockStyle_BlackBlue_v4.glb
#
# Run:
#   blender --background --factory-startup --python medicine_pistol.py
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
OUTPUT_FILE = "FTF_Tool_MedicinePistol_GlockStyle_BlackBlue_v4.glb"

ROOT_NAME = "FTF_Tool_MedicinePistol_GlockStyle_BlackBlue_v4"
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

    mat.diffuse_color = (*color, alpha)
    return mat


def build_materials():
    return {
        "slide": make_material("MAT_MP_GlockStyle_BlackSlide", (0.018, 0.020, 0.022), 0.66, 0.18),
        "frame": make_material("MAT_MP_GlockStyle_BlackFrame", (0.035, 0.038, 0.040), 0.86, 0.04),
        "frame_alt": make_material("MAT_MP_GlockStyle_SoftBlack", (0.075, 0.080, 0.082), 0.84, 0.02),
        "rubber": make_material("MAT_MP_GlockStyle_GripRubber", (0.020, 0.022, 0.022), 0.94, 0.0),
        "metal": make_material("MAT_MP_GlockStyle_DarkMetal", (0.20, 0.22, 0.23), 0.55, 0.30),
        "dark_metal": make_material("MAT_MP_GlockStyle_DeepGunmetal", (0.075, 0.082, 0.088), 0.58, 0.32),
        "muzzle_dark": make_material("MAT_MP_GlockStyle_MuzzleDark", (0.005, 0.006, 0.006), 0.82, 0.12),
        "blue": make_material("MAT_MP_GlockStyle_MedicineBlue", (0.08, 0.42, 1.00), 0.42, 0.02),
        "glass_blue": make_material("MAT_MP_GlockStyle_ClearBlueTubeShell", (0.22, 0.68, 1.0), 0.20, 0.02, alpha=0.55),
        "glow_blue": make_material(
            "MAT_MP_GlockStyle_GlowingBlueMedicine",
            (0.18, 0.75, 1.0),
            0.18,
            0.0,
            alpha=1.0,
            emission=(0.18, 0.72, 1.0),
            emission_strength=1.8,
        ),
        "white_mark": make_material("MAT_MP_GlockStyle_WhiteMedicalMark", (0.88, 0.94, 0.96), 0.62, 0.0),
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
    root["visual_reference"] = "stylized_blocky_polymer_pistol_silhouette"
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


def add_ring_along_y(name, y, z, radius_major, radius_minor, material, parent, collection, x=0.0):
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

    # -----------------------------------------------------------------
    # Grip: angled, blocky polymer style
    # -----------------------------------------------------------------
    add_cube(
        "Grip_MainAngledBlack",
        (0.0, 0.10, -0.34),
        (0.34, 0.42, 0.92),
        mats["rubber"],
        root, collection,
        bevel=0.030,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )
    add_cube(
        "Grip_BasePlate",
        (0.0, 0.06, -0.83),
        (0.42, 0.45, 0.12),
        mats["frame_alt"],
        root, collection,
        bevel=0.022,
        rotation=(math.radians(-9.0), 0.0, 0.0),
    )

    # Grip texture grooves, attached to front face.
    for i, z in enumerate((-0.58, -0.40, -0.22)):
        add_cube(
            f"Grip_FrontGroove_{i:02d}",
            (0.0, -0.095, z),
            (0.36, 0.035, 0.040),
            mats["frame_alt"],
            root, collection,
            bevel=0.004,
            rotation=(math.radians(-9.0), 0.0, 0.0),
        )

    # -----------------------------------------------------------------
    # Lower frame and trigger zone.
    #
    # The receiver reaches z=0.33 while the slide begins at z=0.32. This
    # deliberate 1 cm overlap makes the upper and lower gun body read as one
    # fitted shell after the static meshes are joined. The old version left a
    # visible gap between them.
    # -----------------------------------------------------------------
    add_cube(
        "Frame_LowerReceiver",
        (0.0, -0.42, 0.175),
        (0.56, 1.18, 0.31),
        mats["frame"],
        root, collection,
        bevel=0.026,
    )
    add_cube(
        "Frame_DustCoverFront",
        (0.0, -1.04, 0.175),
        (0.54, 0.48, 0.31),
        mats["frame"],
        root, collection,
        bevel=0.020,
    )

    # Trigger guard: connected loop under the frame.
    add_cube(
        "TriggerGuard_RearBridge",
        (0.0, -0.19, -0.05),
        (0.46, 0.12, 0.25),
        mats["frame"],
        root, collection,
        bevel=0.012,
    )
    add_cube(
        "TriggerGuard_FrontBridge",
        (0.0, -0.53, -0.05),
        (0.46, 0.12, 0.25),
        mats["frame"],
        root, collection,
        bevel=0.012,
    )
    add_cube(
        "TriggerGuard_BottomBridge",
        (0.0, -0.36, -0.21),
        (0.44, 0.44, 0.10),
        mats["frame"],
        root, collection,
        bevel=0.014,
    )
    add_cube(
        "Trigger_BlueMedicalLever",
        (0.0, -0.31, -0.10),
        (0.15, 0.08, 0.30),
        mats["blue"],
        root, collection,
        bevel=0.020,
        rotation=(math.radians(-8.0), 0.0, 0.0),
    )

    # -----------------------------------------------------------------
    # Slide: blocky top silhouette similar to polymer pistol profile
    # -----------------------------------------------------------------
    add_cube(
        "Slide_MainBlackBlock",
        (0.0, -0.70, 0.48),
        (0.62, 1.62, 0.32),
        mats["slide"],
        root, collection,
        bevel=0.026,
    )
    add_cube(
        "Slide_FrontBeveledCap",
        (0.0, -1.54, 0.46),
        (0.58, 0.18, 0.28),
        mats["slide"],
        root, collection,
        bevel=0.018,
    )
    add_cube(
        "Slide_RearPlate",
        (0.0, 0.14, 0.46),
        (0.58, 0.12, 0.30),
        mats["slide"],
        root, collection,
        bevel=0.014,
    )

    # Rear slide serrations as shallow raised strips.
    for i, y in enumerate((0.02, -0.05, -0.12, -0.19)):
        add_cube(
            f"Slide_RearSerration_Left_{i:02d}",
            (-0.325, y, 0.48),
            (0.035, 0.030, 0.32),
            mats["frame_alt"],
            root, collection,
            bevel=0.002,
            rotation=(0.0, 0.0, math.radians(-12.0)),
        )
        add_cube(
            f"Slide_RearSerration_Right_{i:02d}",
            (0.325, y, 0.48),
            (0.035, 0.030, 0.32),
            mats["frame_alt"],
            root, collection,
            bevel=0.002,
            rotation=(0.0, 0.0, math.radians(12.0)),
        )

    # Decorative ejection-port-like recess on top/side, still stylized and nonfunctional.
    add_cube(
        "Slide_EjectionPort_DarkPanel",
        (0.0, -0.82, 0.665),
        (0.34, 0.38, 0.035),
        mats["dark_metal"],
        root, collection,
        bevel=0.004,
    )

    # Barrel/muzzle as a simple game-prop aperture, not a detailed mechanism.
    add_cylinder_between(
        "Barrel_DarkShortTube",
        (0.0, -1.41, 0.45),
        (0.0, -1.78, 0.45),
        0.110,
        mats["metal"],
        root, collection,
        vertices=18,
        bevel=0.002,
    )
    add_cylinder_between(
        "Muzzle_BlackOpening",
        (0.0, -1.78, 0.45),
        (0.0, -1.84, 0.45),
        0.082,
        mats["muzzle_dark"],
        root, collection,
        vertices=18,
        bevel=0.001,
    )
    add_ring_along_y(
        "Muzzle_BlueDoseRing",
        -1.74,
        0.45,
        0.120,
        0.016,
        mats["blue"],
        root, collection,
    )

    # Sights attached to the slide.
    # Slide top is z=0.64 m. Both sight bases extend down to z=0.625 m,
    # producing a deliberate 1.5 cm overlap instead of a visible floating gap.
    add_cube(
        "Sight_Front",
        (0.0, -1.40, 0.6675),
        (0.10, 0.10, 0.085),
        mats["frame_alt"],
        root, collection,
        bevel=0.005,
    )
    add_cube(
        "Sight_Rear",
        (0.0, 0.02, 0.670),
        (0.18, 0.10, 0.090),
        mats["frame_alt"],
        root, collection,
        bevel=0.005,
    )

    # -----------------------------------------------------------------
    # Medicine tube: mirrored to the opposite outer side of the frame
    # -----------------------------------------------------------------
    # V3 used the negative-X side. V4 mirrors the complete tube assembly to
    # positive X. The receiver side wall is x=+0.28 m. With the tube centre
    # at x=+0.30 m and
    # a 0.11 m radius, roughly 40 percent of its diameter sinks into the body
    # while the outer glass arc stays clearly visible.
    #
    # The tube no longer separates the upper and lower body. It sits in a
    # shallow external cradle and is held by sockets, guard rails and straps.
    tube_x = 0.30
    tube_z = 0.175

    # Dark cradle behind the glass. It intersects the receiver and reads as a
    # recessed side channel rather than a floating tank.
    add_cube(
        "MedicineTube_SideCradle",
        (0.285, -0.53, tube_z),
        (0.055, 0.94, 0.245),
        mats["dark_metal"],
        root, collection,
        bevel=0.012,
    )

    add_cylinder_between(
        "MedicineTube_GlassShell_SideMounted",
        (tube_x, -0.91, tube_z),
        (tube_x, -0.17, tube_z),
        0.110,
        mats["glass_blue"],
        root, collection,
        vertices=24,
        bevel=0.002,
    )
    add_cylinder_between(
        "MedicineTube_GlowCore_SideMounted",
        (tube_x, -0.875, tube_z),
        (tube_x, -0.205, tube_z),
        0.064,
        mats["glow_blue"],
        root, collection,
        vertices=20,
        bevel=0.001,
    )
    add_cylinder_between(
        "MedicineTube_RearSocket",
        (tube_x, -0.17, tube_z),
        (tube_x, -0.06, tube_z),
        0.120,
        mats["metal"],
        root, collection,
        vertices=20,
        bevel=0.002,
    )
    add_cylinder_between(
        "MedicineTube_FrontSocket",
        (tube_x, -0.91, tube_z),
        (tube_x, -1.03, tube_z),
        0.120,
        mats["metal"],
        root, collection,
        vertices=20,
        bevel=0.002,
    )

    # Upper/lower rails border the exposed glass without covering its long
    # blue viewing area. Both rails overlap the receiver and cradle.
    add_cube(
        "MedicineTube_UpperGuardRail",
        (0.335, -0.53, 0.300),
        (0.150, 0.90, 0.045),
        mats["frame"],
        root, collection,
        bevel=0.009,
    )
    add_cube(
        "MedicineTube_LowerGuardRail",
        (0.335, -0.53, 0.050),
        (0.150, 0.90, 0.045),
        mats["frame"],
        root, collection,
        bevel=0.009,
    )

    # Narrow straps cross the exposed outer arc. Their short Y dimension
    # keeps most of the glowing medicine unobstructed.
    for i, y in enumerate((-0.27, -0.54, -0.81)):
        add_cube(
            f"MedicineTube_OuterClamp_{i:02d}",
            (0.355, y, tube_z),
            (0.175, 0.045, 0.275),
            mats["frame"],
            root, collection,
            bevel=0.007,
        )

    # A small status light on the opposite side balances the silhouette. It
    # is intentionally too small to be mistaken for a second medicine tube.
    add_cube(
        "MedicineStatus_LeftBlueInset",
        (-0.292, -0.62, 0.180),
        (0.035, 0.26, 0.075),
        mats["blue"],
        root, collection,
        bevel=0.004,
    )

    # Medical cross mark made from geometry, not text.
    add_cube(
        "MedicalCross_Vertical",
        (0.325, -0.88, 0.48),
        (0.028, 0.035, 0.160),
        mats["white_mark"],
        root, collection,
        bevel=0.002,
    )
    add_cube(
        "MedicalCross_Horizontal",
        (0.327, -0.88, 0.48),
        (0.030, 0.135, 0.043),
        mats["white_mark"],
        root, collection,
        bevel=0.002,
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
    pairs = [
        ("Grip_MainAngledBlack", "Frame_LowerReceiver", 0.10),
        ("Grip_BasePlate", "Grip_MainAngledBlack", 0.08),
        ("Grip_FrontGroove_00", "Grip_MainAngledBlack", 0.08),
        ("Grip_FrontGroove_01", "Grip_MainAngledBlack", 0.08),
        ("Grip_FrontGroove_02", "Grip_MainAngledBlack", 0.08),

        ("Frame_LowerReceiver", "Frame_DustCoverFront", 0.08),
        ("Frame_LowerReceiver", "Slide_MainBlackBlock", 0.10),
        ("Slide_MainBlackBlock", "Slide_FrontBeveledCap", 0.08),
        ("Slide_MainBlackBlock", "Slide_RearPlate", 0.08),
        ("Slide_MainBlackBlock", "Slide_EjectionPort_DarkPanel", 0.08),

        ("TriggerGuard_RearBridge", "Frame_LowerReceiver", 0.08),
        ("TriggerGuard_FrontBridge", "Frame_LowerReceiver", 0.08),
        ("TriggerGuard_BottomBridge", "TriggerGuard_RearBridge", 0.10),
        ("TriggerGuard_BottomBridge", "TriggerGuard_FrontBridge", 0.10),
        ("Trigger_BlueMedicalLever", "TriggerGuard_RearBridge", 0.12),

        ("Barrel_DarkShortTube", "Slide_FrontBeveledCap", 0.12),
        ("Muzzle_BlackOpening", "Barrel_DarkShortTube", 0.06),
        ("Muzzle_BlueDoseRing", "Barrel_DarkShortTube", 0.05),

        ("Sight_Front", "Slide_MainBlackBlock", 0.08),
        ("Sight_Rear", "Slide_MainBlackBlock", 0.08),

        ("MedicineTube_SideCradle", "Frame_LowerReceiver", 0.03),
        ("MedicineTube_GlassShell_SideMounted", "MedicineTube_SideCradle", 0.03),
        ("MedicineTube_GlowCore_SideMounted", "MedicineTube_GlassShell_SideMounted", 0.03),
        ("MedicineTube_RearSocket", "MedicineTube_GlassShell_SideMounted", 0.04),
        ("MedicineTube_FrontSocket", "MedicineTube_GlassShell_SideMounted", 0.04),
        ("MedicineTube_UpperGuardRail", "Frame_LowerReceiver", 0.03),
        ("MedicineTube_LowerGuardRail", "Frame_LowerReceiver", 0.03),
        ("MedicineTube_OuterClamp_00", "MedicineTube_SideCradle", 0.03),
        ("MedicineTube_OuterClamp_01", "MedicineTube_SideCradle", 0.03),
        ("MedicineTube_OuterClamp_02", "MedicineTube_SideCradle", 0.03),
        ("MedicineStatus_LeftBlueInset", "Frame_LowerReceiver", 0.03),

        ("MedicalCross_Vertical", "Slide_MainBlackBlock", 0.08),
        ("MedicalCross_Horizontal", "Slide_MainBlackBlock", 0.08),
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
    print("\n=== Generating Glock-Style Medicine Pistol ===\n")

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
    print(" - Stylized blocky polymer handgun silhouette, not a mechanical firearm replica.")
    print(" - Upper slide and lower frame are fitted together with no body gap.")
    print(" - Front and rear sights overlap the slide top; no sight is floating.")
    print(" - Blue glowing medicine tube and white medical cross are mirrored to the positive-X side.")
    print(" - No sprayer tank, hose, or pressure gauge.")
    print(" - Root/origin is at the hand grip.")
    print(" - Blender forward is -Y; intended Godot forward is -Z after GLB import.")
    print(" - Attachment audit passed before merge, so no obvious floating parts should remain.")
