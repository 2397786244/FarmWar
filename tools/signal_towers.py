# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Signal Jammer Tower + Signal Booster Tower
#
# One script generates two independent GLB assets:
#   generated_farmtown_tools/FTF_Tool_SignalJammerTower_4m_v1.glb
#   generated_farmtown_tools/FTF_Tool_SignalBoosterTower_4m_v1.glb
#
# ASSET STANDARD
# - Stylized low-poly 3D game props
# - Maximum height: 4.0 m
# - Maximum footprint: 2.0 m x 2.0 m
# - Root/origin: ground centre at (0, 0, 0)
# - Blender authoring forward: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - No cameras, lights, text or collision meshes
# - Each asset is merged to one static visual mesh before export
#
# VISUAL LANGUAGE
# - Jammer: heavy black industrial truss, red interference core, four dark
#   directional panels and red warning details.
# - Booster: clean white/light-grey mast, cyan energy core, three friendly
#   directional panels, cyan signal halos and a bright top node.
#
# Run:
#   blender --background --factory-startup --python signal_towers.py
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

JAMMER_ROOT_NAME = "FTF_Tool_SignalJammerTower_4m_v1"
BOOSTER_ROOT_NAME = "FTF_Tool_SignalBoosterTower_4m_v1"

JAMMER_OUTPUT_FILE = JAMMER_ROOT_NAME + ".glb"
BOOSTER_OUTPUT_FILE = BOOSTER_ROOT_NAME + ".glb"

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

MAX_FOOTPRINT_X = 2.0
MAX_FOOTPRINT_Y = 2.0
MAX_HEIGHT = 4.0


# -----------------------------------------------------------------------------
# SCENE / MATERIALS
# -----------------------------------------------------------------------------

def clear_scene():
    """Remove all objects and unused scene datablocks."""
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
    """Use metres as the Blender scene unit."""
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
    """Create a GLB-friendly Principled or emission material."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
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

    mat.diffuse_color = (*color, 1.0)
    return mat


def build_jammer_materials():
    """Materials for the hostile industrial jammer tower."""
    return {
        "base": make_material("MAT_Jammer_BaseBlack", (0.025, 0.030, 0.032), 0.84, 0.16),
        "frame": make_material("MAT_Jammer_DarkFrame", (0.070, 0.080, 0.085), 0.70, 0.34),
        "panel": make_material("MAT_Jammer_AbsorberPanel", (0.018, 0.022, 0.024), 0.91, 0.08),
        "metal": make_material("MAT_Jammer_Gunmetal", (0.18, 0.20, 0.21), 0.52, 0.48),
        "red": make_material("MAT_Jammer_WarningRed", (0.72, 0.035, 0.025), 0.46, 0.08),
        "red_glow": make_material(
            "MAT_Jammer_InterferenceGlow",
            (1.0, 0.035, 0.015),
            emission=(1.0, 0.025, 0.008),
            emission_strength=3.2,
        ),
        "orange": make_material(
            "MAT_Jammer_StatusOrange",
            (1.0, 0.24, 0.025),
            emission=(1.0, 0.18, 0.01),
            emission_strength=2.2,
        ),
    }


def build_booster_materials():
    """Materials for the clean friendly signal booster tower."""
    return {
        "base": make_material("MAT_Booster_BaseGrey", (0.16, 0.19, 0.20), 0.72, 0.22),
        "white": make_material("MAT_Booster_WarmWhite", (0.74, 0.79, 0.80), 0.64, 0.12),
        "frame": make_material("MAT_Booster_LightFrame", (0.36, 0.42, 0.43), 0.58, 0.36),
        "panel": make_material("MAT_Booster_SignalPanel", (0.08, 0.16, 0.18), 0.62, 0.24),
        "cyan": make_material("MAT_Booster_CyanTrim", (0.02, 0.56, 0.76), 0.34, 0.08),
        "cyan_glow": make_material(
            "MAT_Booster_SignalGlow",
            (0.04, 0.82, 1.0),
            emission=(0.025, 0.76, 1.0),
            emission_strength=2.8,
        ),
        "green": make_material(
            "MAT_Booster_StatusGreen",
            (0.10, 0.92, 0.42),
            emission=(0.06, 0.85, 0.30),
            emission_strength=2.0,
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


def create_root(name, category, collection):
    """Create a ground-centred export root with Godot import metadata."""
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.35
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "DeployableTower"
    root["tool_category"] = category
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "GroundCenter"
    root["nominal_height_m"] = 4.0
    root["max_footprint_m"] = "2x2"
    root["has_collision_mesh"] = False
    root["effects_baked_into_model"] = False
    root["static_meshes_merged_on_export"] = MERGE_STATIC_MESHES

    collection.objects.link(root)
    return root


# -----------------------------------------------------------------------------
# GEOMETRY HELPERS
# -----------------------------------------------------------------------------

def finish_object(obj, name, material, parent, collection, bevel=0.0):
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    obj.parent = parent
    obj["no_merge"] = False
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
):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, material, parent, collection, bevel)


def add_cylinder_between(
    name,
    p0,
    p1,
    radius,
    material,
    parent,
    collection,
    vertices=12,
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
    return finish_object(bpy.context.object, name, material, parent, collection, bevel)


def add_sphere(
    name,
    location,
    radius,
    material,
    parent,
    collection,
    segments=16,
    rings=8,
):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=radius,
        location=location,
    )
    return finish_object(bpy.context.object, name, material, parent, collection)


def add_torus(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    parent,
    collection,
    rotation=(0.0, 0.0, 0.0),
    major_segments=20,
    minor_segments=6,
):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation,
    )
    return finish_object(bpy.context.object, name, material, parent, collection)


# -----------------------------------------------------------------------------
# SHARED STRUCTURAL HELPERS
# -----------------------------------------------------------------------------

def add_square_truss_level(prefix, z, half_width, radius, material, root, collection):
    """Create one square horizontal truss ring from four cylinders."""
    corners = [
        (-half_width, -half_width, z),
        (half_width, -half_width, z),
        (half_width, half_width, z),
        (-half_width, half_width, z),
    ]
    for index in range(4):
        add_cylinder_between(
            f"{prefix}_Edge_{index:02d}",
            corners[index],
            corners[(index + 1) % 4],
            radius,
            material,
            root,
            collection,
            vertices=8,
        )


def add_radial_feet(prefix, count, radius, z, foot_size, material, root, collection):
    """Add evenly spaced square stabilizer feet within the footprint."""
    for index in range(count):
        angle = math.tau * index / count
        x = math.cos(angle) * radius
        y = math.sin(angle) * radius
        add_cube(
            f"{prefix}_{index:02d}",
            (x, y, z),
            foot_size,
            material,
            root,
            collection,
            bevel=0.025,
            rotation=(0.0, 0.0, angle),
        )


# -----------------------------------------------------------------------------
# BUILD: SIGNAL JAMMER TOWER
# -----------------------------------------------------------------------------

def build_signal_jammer_tower():
    """Build the dark, heavy, red-emitting interference tower."""
    mats = build_jammer_materials()
    collection = get_or_create_collection("COL_" + JAMMER_ROOT_NAME)
    root = create_root(JAMMER_ROOT_NAME, "SignalJammerTower", collection)

    # 1.72 m square base is the widest part of the asset.
    add_cube(
        "Jammer_BaseSlab",
        (0.0, 0.0, 0.10),
        (1.72, 1.72, 0.20),
        mats["base"],
        root,
        collection,
        bevel=0.055,
    )
    add_cube(
        "Jammer_BaseUpperPlate",
        (0.0, 0.0, 0.27),
        (1.36, 1.36, 0.18),
        mats["metal"],
        root,
        collection,
        bevel=0.035,
        rotation=(0.0, 0.0, math.radians(45.0)),
    )
    add_radial_feet(
        "Jammer_StabilizerFoot",
        4,
        0.66,
        0.12,
        (0.26, 0.26, 0.24),
        mats["frame"],
        root,
        collection,
    )

    # Central mast and four inward-tapering structural legs.
    add_cylinder_between(
        "Jammer_CentralMast",
        (0.0, 0.0, 0.30),
        (0.0, 0.0, 3.72),
        0.12,
        mats["frame"],
        root,
        collection,
        vertices=10,
        bevel=0.008,
    )

    bottom_points = [(-0.58, -0.58, 0.34), (0.58, -0.58, 0.34), (0.58, 0.58, 0.34), (-0.58, 0.58, 0.34)]
    top_points = [(-0.22, -0.22, 2.56), (0.22, -0.22, 2.56), (0.22, 0.22, 2.56), (-0.22, 0.22, 2.56)]
    for index, (bottom, top) in enumerate(zip(bottom_points, top_points)):
        add_cylinder_between(
            f"Jammer_TrussLeg_{index:02d}",
            bottom,
            top,
            0.045,
            mats["metal"],
            root,
            collection,
            vertices=8,
        )

    for level_index, (z, half_width) in enumerate(((0.82, 0.50), (1.38, 0.41), (1.94, 0.32), (2.50, 0.23))):
        add_square_truss_level(
            f"Jammer_TrussLevel_{level_index:02d}",
            z,
            half_width,
            0.035,
            mats["frame"],
            root,
            collection,
        )

    # Armoured electronics cabinet and warning strips.
    add_cube(
        "Jammer_ControlCabinet",
        (0.0, -0.03, 1.22),
        (0.76, 0.64, 0.52),
        mats["panel"],
        root,
        collection,
        bevel=0.045,
    )
    add_cube(
        "Jammer_ControlCabinet_RedBand",
        (0.0, -0.358, 1.22),
        (0.56, 0.025, 0.085),
        mats["red"],
        root,
        collection,
        bevel=0.006,
    )
    for index, x in enumerate((-0.17, 0.0, 0.17)):
        add_cube(
            f"Jammer_StatusLight_{index:02d}",
            (x, -0.375, 1.07),
            (0.055, 0.022, 0.055),
            mats["orange" if index == 1 else "red_glow"],
            root,
            collection,
            bevel=0.008,
        )

    # Red interference core with three mutually perpendicular cage rings.
    add_sphere(
        "Jammer_InterferenceCore",
        (0.0, 0.0, 2.72),
        0.24,
        mats["red_glow"],
        root,
        collection,
        segments=16,
        rings=8,
    )
    add_torus(
        "Jammer_CoreRing_Horizontal",
        (0.0, 0.0, 2.72),
        0.36,
        0.027,
        mats["red"],
        root,
        collection,
    )
    add_torus(
        "Jammer_CoreRing_VerticalX",
        (0.0, 0.0, 2.72),
        0.36,
        0.027,
        mats["red"],
        root,
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    add_torus(
        "Jammer_CoreRing_VerticalY",
        (0.0, 0.0, 2.72),
        0.36,
        0.027,
        mats["red"],
        root,
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
    )

    # Four directional jammer panels. Their dark faces and red centre bars
    # distinguish them from the booster tower's three cyan panels.
    panel_specs = [
        ("North", (0.0, -0.48, 3.30), (0.66, 0.12, 0.72), 0.0, (0.0, -0.547, 3.30), (0.42, 0.025, 0.075)),
        ("South", (0.0, 0.48, 3.30), (0.66, 0.12, 0.72), 0.0, (0.0, 0.547, 3.30), (0.42, 0.025, 0.075)),
        ("West", (-0.48, 0.0, 3.30), (0.12, 0.66, 0.72), 0.0, (-0.547, 0.0, 3.30), (0.025, 0.42, 0.075)),
        ("East", (0.48, 0.0, 3.30), (0.12, 0.66, 0.72), 0.0, (0.547, 0.0, 3.30), (0.025, 0.42, 0.075)),
    ]
    jammer_arm_ends = {
        "North": (0.0, -0.44, 3.30),
        "South": (0.0, 0.44, 3.30),
        "West": (-0.44, 0.0, 3.30),
        "East": (0.44, 0.0, 3.30),
    }
    for side, location, dimensions, rotation_z, strip_location, strip_dimensions in panel_specs:
        add_cylinder_between(
            f"Jammer_PanelSupportArm_{side}",
            (0.0, 0.0, 3.30),
            jammer_arm_ends[side],
            0.045,
            mats["metal"],
            root,
            collection,
            vertices=8,
        )
        add_cube(
            f"Jammer_DirectionalPanel_{side}",
            location,
            dimensions,
            mats["panel"],
            root,
            collection,
            bevel=0.035,
            rotation=(0.0, 0.0, rotation_z),
        )
        add_cube(
            f"Jammer_DirectionalPanel_{side}_RedStrip",
            strip_location,
            strip_dimensions,
            mats["red_glow"],
            root,
            collection,
            bevel=0.005,
        )

    # Top warning beacon reaches exactly 4.0 m.
    add_cylinder_between(
        "Jammer_TopAntenna",
        (0.0, 0.0, 3.55),
        (0.0, 0.0, 3.86),
        0.055,
        mats["metal"],
        root,
        collection,
        vertices=10,
    )
    add_sphere(
        "Jammer_TopBeacon",
        (0.0, 0.0, 3.92),
        0.08,
        mats["red_glow"],
        root,
        collection,
        segments=12,
        rings=6,
    )

    return root


# -----------------------------------------------------------------------------
# BUILD: SIGNAL BOOSTER TOWER
# -----------------------------------------------------------------------------

def build_signal_booster_tower():
    """Build the clean white/cyan friendly communication booster."""
    mats = build_booster_materials()
    collection = get_or_create_collection("COL_" + BOOSTER_ROOT_NAME)
    root = create_root(BOOSTER_ROOT_NAME, "SignalBoosterTower", collection)

    # Compact 1.52 m diameter octagonal base.
    add_cylinder_between(
        "Booster_BaseOctagonal",
        (0.0, 0.0, 0.0),
        (0.0, 0.0, 0.20),
        0.76,
        mats["base"],
        root,
        collection,
        vertices=8,
        bevel=0.025,
    )
    add_cylinder_between(
        "Booster_BaseUpperRing",
        (0.0, 0.0, 0.18),
        (0.0, 0.0, 0.34),
        0.56,
        mats["white"],
        root,
        collection,
        vertices=12,
        bevel=0.018,
    )
    add_radial_feet(
        "Booster_StabilizerFoot",
        3,
        0.60,
        0.11,
        (0.25, 0.31, 0.22),
        mats["frame"],
        root,
        collection,
    )

    # Slim central mast and three swept support legs.
    # The support feet begin at z=0.18 m, deliberately overlapping the
    # octagonal base (top z=0.20 m) and the upper base ring (bottom z=0.18 m).
    # This prevents the 7.25 cm floating gap present in the previous version.
    add_cylinder_between(
        "Booster_CentralMast",
        (0.0, 0.0, 0.28),
        (0.0, 0.0, 3.82),
        0.105,
        mats["white"],
        root,
        collection,
        vertices=12,
        bevel=0.008,
    )
    for index in range(3):
        angle = math.tau * index / 3.0
        bottom = (math.cos(angle) * 0.58, math.sin(angle) * 0.58, 0.18)
        top = (math.cos(angle) * 0.16, math.sin(angle) * 0.16, 2.48)
        add_cylinder_between(
            f"Booster_SweptSupport_{index:02d}",
            bottom,
            top,
            0.040,
            mats["frame"],
            root,
            collection,
            vertices=8,
        )

    # Central communication/energy capsule.
    add_cylinder_between(
        "Booster_EnergyHousing",
        (0.0, 0.0, 0.82),
        (0.0, 0.0, 1.70),
        0.30,
        mats["panel"],
        root,
        collection,
        vertices=12,
        bevel=0.018,
    )
    add_cylinder_between(
        "Booster_EnergyCore",
        (0.0, 0.0, 0.94),
        (0.0, 0.0, 1.58),
        0.17,
        mats["cyan_glow"],
        root,
        collection,
        vertices=16,
    )
    for index, z in enumerate((0.90, 1.26, 1.62)):
        add_torus(
            f"Booster_EnergyBand_{index:02d}",
            (0.0, 0.0, z),
            0.305,
            0.030,
            mats["cyan"],
            root,
            collection,
            major_segments=18,
        )

    # Small front status console faces Blender forward (-Y).
    add_cube(
        "Booster_StatusConsole",
        (0.0, -0.325, 1.24),
        (0.34, 0.055, 0.26),
        mats["white"],
        root,
        collection,
        bevel=0.025,
    )
    add_cube(
        "Booster_StatusGreenLight",
        (0.0, -0.357, 1.24),
        (0.10, 0.020, 0.075),
        mats["green"],
        root,
        collection,
        bevel=0.012,
    )

    # Three panels at 120 degrees. Each panel's thin axis points radially and
    # a glowing cyan inset sits on its outer face.
    for index in range(3):
        angle = -math.pi / 2.0 + math.tau * index / 3.0
        radial_x = math.cos(angle)
        radial_y = math.sin(angle)
        centre = (radial_x * 0.42, radial_y * 0.42, 3.22)

        add_cylinder_between(
            f"Booster_PanelSupportArm_{index:02d}",
            (0.0, 0.0, 3.22),
            (radial_x * 0.38, radial_y * 0.38, 3.22),
            0.038,
            mats["frame"],
            root,
            collection,
            vertices=8,
        )

        add_cube(
            f"Booster_DirectionalPanel_{index:02d}",
            centre,
            (0.14, 0.54, 0.82),
            mats["white"],
            root,
            collection,
            bevel=0.045,
            rotation=(0.0, 0.0, angle),
        )

        inset_centre = (
            radial_x * 0.495,
            radial_y * 0.495,
            3.22,
        )
        add_cube(
            f"Booster_DirectionalPanel_{index:02d}_CyanInset",
            inset_centre,
            (0.025, 0.34, 0.53),
            mats["cyan_glow"],
            root,
            collection,
            bevel=0.025,
            rotation=(0.0, 0.0, angle),
        )

    # Horizontal signal halos communicate upward broadcast and stay compact.
    add_torus(
        "Booster_SignalHalo_Lower",
        (0.0, 0.0, 3.54),
        0.45,
        0.025,
        mats["cyan_glow"],
        root,
        collection,
        major_segments=24,
    )
    add_torus(
        "Booster_SignalHalo_Upper",
        (0.0, 0.0, 3.73),
        0.32,
        0.022,
        mats["cyan_glow"],
        root,
        collection,
        major_segments=20,
    )

    # Bright top node reaches exactly 4.0 m.
    add_sphere(
        "Booster_TopSignalNode",
        (0.0, 0.0, 3.90),
        0.10,
        mats["cyan_glow"],
        root,
        collection,
        segments=14,
        rings=7,
    )

    return root


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


def validate_attachment_pairs(asset_label, pairs):
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
            f"{asset_label} FLOATING-PART AUDIT FAILED:\n- " + "\n- ".join(failures)
        )

    print(f"[VALID] {asset_label}: {len(pairs)} attachment checks passed.")


def validate_jammer_attachments():
    pairs = [
        ("Jammer_BaseUpperPlate", "Jammer_BaseSlab", 0.03),
        ("Jammer_CentralMast", "Jammer_BaseUpperPlate", 0.03),
        ("Jammer_TrussLeg_00", "Jammer_BaseUpperPlate", 0.04),
        ("Jammer_TrussLeg_01", "Jammer_BaseUpperPlate", 0.04),
        ("Jammer_TrussLeg_02", "Jammer_BaseUpperPlate", 0.04),
        ("Jammer_TrussLeg_03", "Jammer_BaseUpperPlate", 0.04),
        ("Jammer_ControlCabinet", "Jammer_CentralMast", 0.03),
        ("Jammer_InterferenceCore", "Jammer_CentralMast", 0.03),
        ("Jammer_CoreRing_Horizontal", "Jammer_InterferenceCore", 0.15),
        ("Jammer_DirectionalPanel_North", "Jammer_PanelSupportArm_North", 0.03),
        ("Jammer_DirectionalPanel_South", "Jammer_PanelSupportArm_South", 0.03),
        ("Jammer_DirectionalPanel_West", "Jammer_PanelSupportArm_West", 0.03),
        ("Jammer_DirectionalPanel_East", "Jammer_PanelSupportArm_East", 0.03),
        ("Jammer_TopAntenna", "Jammer_CentralMast", 0.03),
        ("Jammer_TopBeacon", "Jammer_TopAntenna", 0.03),
    ]
    validate_attachment_pairs("Signal Jammer Tower", pairs)


def validate_booster_attachments():
    pairs = [
        ("Booster_BaseUpperRing", "Booster_BaseOctagonal", 0.03),
        ("Booster_CentralMast", "Booster_BaseUpperRing", 0.03),
        ("Booster_SweptSupport_00", "Booster_BaseOctagonal", 0.04),
        ("Booster_SweptSupport_01", "Booster_BaseOctagonal", 0.04),
        ("Booster_SweptSupport_02", "Booster_BaseOctagonal", 0.04),
        ("Booster_EnergyHousing", "Booster_CentralMast", 0.03),
        ("Booster_EnergyCore", "Booster_EnergyHousing", 0.03),
        ("Booster_StatusConsole", "Booster_EnergyHousing", 0.04),
        ("Booster_DirectionalPanel_00", "Booster_PanelSupportArm_00", 0.03),
        ("Booster_DirectionalPanel_01", "Booster_PanelSupportArm_01", 0.03),
        ("Booster_DirectionalPanel_02", "Booster_PanelSupportArm_02", 0.03),
        ("Booster_SignalHalo_Lower", "Booster_CentralMast", 0.35),
        ("Booster_SignalHalo_Upper", "Booster_CentralMast", 0.22),
        ("Booster_TopSignalNode", "Booster_CentralMast", 0.03),
    ]
    validate_attachment_pairs("Signal Booster Tower", pairs)


def validate_asset(root, stage):
    """Validate hierarchy, scale, bounds and approximate triangle count."""
    if root.type != "EMPTY":
        raise RuntimeError(f"{root.name}: root must be an Empty.")
    if root.location.length > 0.0001:
        raise RuntimeError(f"{root.name}: root must remain at ground origin.")

    forbidden = [obj.name for obj in iter_hierarchy(root) if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError(f"{root.name}: cameras/lights found: {', '.join(forbidden)}")

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError(f"{root.name}: no meshes under root.")

    scale_failures = []
    collision_names = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            scale_failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            scale_failures.append("negative scale: " + obj.name)

        lowered_name = obj.name.lower()
        if lowered_name.startswith("ucx") or "collision" in lowered_name:
            collision_names.append(obj.name)

    if scale_failures:
        raise RuntimeError(f"{root.name} scale validation failed:\n- " + "\n- ".join(scale_failures))
    if collision_names:
        raise RuntimeError(f"{root.name}: collision-like meshes found: {', '.join(collision_names)}")

    low, high = bbox_world_all(meshes)
    dimensions = high - low

    tolerance = 0.012
    bound_failures = []
    if dimensions.x > MAX_FOOTPRINT_X + tolerance:
        bound_failures.append(f"width X {dimensions.x:.3f} m exceeds {MAX_FOOTPRINT_X:.2f} m")
    if dimensions.y > MAX_FOOTPRINT_Y + tolerance:
        bound_failures.append(f"depth Y {dimensions.y:.3f} m exceeds {MAX_FOOTPRINT_Y:.2f} m")
    if high.z > MAX_HEIGHT + tolerance:
        bound_failures.append(f"top Z {high.z:.3f} m exceeds {MAX_HEIGHT:.2f} m")
    if low.z < -tolerance:
        bound_failures.append(f"asset extends below ground: low Z {low.z:.3f} m")
    if high.z < 3.95:
        bound_failures.append(f"asset is shorter than intended: top Z {high.z:.3f} m")

    if bound_failures:
        raise RuntimeError(f"{root.name} SIZE VALIDATION FAILED:\n- " + "\n- ".join(bound_failures))

    triangle_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangle_count += len(obj.data.loop_triangles)

    print(
        f"[VALID {stage}] {root.name}\n"
        f"  Bounds: {dimensions.x:.3f} m x {dimensions.y:.3f} m\n"
        f"  Ground-to-top: {low.z:.3f} m to {high.z:.3f} m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangle_count}\n"
        f"  Origin: ground centre (0, 0, 0)\n"
    )


# -----------------------------------------------------------------------------
# MERGE / EXPORT
# -----------------------------------------------------------------------------

def merge_static_meshes(root):
    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError(f"{root.name}: no meshes available for merge.")

    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = root.name + "_Static"
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


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

def main():
    print("\n=== Generating Signal Jammer + Signal Booster Towers ===\n")

    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    jammer_root = build_signal_jammer_tower()
    booster_root = build_signal_booster_tower()

    validate_jammer_attachments()
    validate_booster_attachments()
    validate_asset(jammer_root, "BEFORE MERGE")
    validate_asset(booster_root, "BEFORE MERGE")

    if MERGE_STATIC_MESHES:
        merge_static_meshes(jammer_root)
        merge_static_meshes(booster_root)

    validate_asset(jammer_root, "AFTER MERGE")
    validate_asset(booster_root, "AFTER MERGE")

    jammer_path = os.path.join(OUTPUT_DIR, JAMMER_OUTPUT_FILE)
    booster_path = os.path.join(OUTPUT_DIR, BOOSTER_OUTPUT_FILE)
    export_glb(jammer_root, jammer_path)
    export_glb(booster_root, booster_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + jammer_path)
    print(" - " + booster_path)
    print("\nNotes:")
    print(" - Both tower roots are at the ground centre (0, 0, 0).")
    print(" - Both assets are 4 m tall and remain inside a 2 m x 2 m footprint.")
    print(" - Jammer uses black/red hostile industrial styling.")
    print(" - Booster uses white/cyan friendly communication styling.")
    print(" - Blender forward is -Y; intended Godot forward is -Z after GLB import.")
    print(" - No cameras, lights, text or collision meshes are exported.")


if __name__ == "__main__":
    main()
