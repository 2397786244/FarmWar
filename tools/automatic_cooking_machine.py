# Blender 4.x / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Automatic Cooking Machine
#
# Generates:
#   generated_farmtown_tools/FTF_Tool_AutomaticCookingMachine_v1.glb
#
# DESIGN
# - Fixed automatic cooking machine for an indoor cooking/workshop scene
# - Silver/grey metal cabinet and structural frame
# - Separate transparent chamber shell
# - Black cage-style cooking drum, visible through the shell
# - Simplified green and brown vegetable chunks made from small cubes
# - RotatingDrum is an independent pivot node for Godot runtime rotation
#
# EXPORTED HIERARCHY
#   FTF_Tool_AutomaticCookingMachine_v1
#   |-- Body_Static
#   |-- TransparentShell
#   `-- RotatingDrum                 <- rotate this Node3D around local X
#       |-- Drum_BlackMesh
#       `-- Vegetables_Visual
#
# ASSET STANDARD
# - Approximate size: 1.55 m wide x 1.43 m deep x 1.99 m high
# - Root/origin at ground centre: (0, 0, 0)
# - Blender authoring forward: local -Y
# - Intended Godot forward after normal GLB import: local -Z
# - No cameras, lights, text or collision meshes
# - Transparent and opaque geometry remain separate for reliable rendering
#
# Run:
#   blender --background --factory-startup --python automatic_cooking_machine.py
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

ROOT_NAME = "FTF_Tool_AutomaticCookingMachine_v1"
COLLECTION_NAME = "COL_" + ROOT_NAME
OUTPUT_FILE = ROOT_NAME + ".glb"

CLEAR_SCENE = True
MERGE_VISUAL_GROUPS = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

DRUM_CENTER = Vector((0.0, 0.0, 1.29))
DRUM_ROTATION_AXIS = "X"

GROUP_BODY = "BODY"
GROUP_GLASS = "GLASS"
GROUP_DRUM = "DRUM"
GROUP_VEGETABLES = "VEGETABLES"


# -----------------------------------------------------------------------------
# SCENE / MATERIALS
# -----------------------------------------------------------------------------

def clear_scene():
    """Remove all scene objects and unused data from the startup file."""
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
    """Use metres and keep the scene free of animation-side assumptions."""
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
    """Create a GLB-compatible opaque, transparent or emissive material."""
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

            # Blender 4.2+ uses surface_render_method. Older Blender 4.x
            # versions may still expose blend_method.
            if hasattr(material, "surface_render_method"):
                try:
                    enum_items = material.bl_rna.properties["surface_render_method"].enum_items.keys()
                    if "DITHERED" in enum_items:
                        material.surface_render_method = "DITHERED"
                    elif "BLENDED" in enum_items:
                        material.surface_render_method = "BLENDED"
                except Exception as exc:
                    print(f"[WARN] Could not set transparency mode on {name}: {exc}")
            elif hasattr(material, "blend_method"):
                material.blend_method = "BLEND"

        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

    material.diffuse_color = (*color, alpha)
    return material


def build_materials():
    """Build the silver machine, black drum, glass and food materials."""
    return {
        "silver": make_material(
            "MAT_ACM_SilverBody",
            (0.42, 0.47, 0.49),
            roughness=0.42,
            metallic=0.58,
        ),
        "silver_light": make_material(
            "MAT_ACM_LightSilverFrame",
            (0.66, 0.71, 0.72),
            roughness=0.38,
            metallic=0.52,
        ),
        "dark_grey": make_material(
            "MAT_ACM_DarkGreyPanels",
            (0.08, 0.095, 0.10),
            roughness=0.72,
            metallic=0.24,
        ),
        "black_drum": make_material(
            "MAT_ACM_BlackCookingDrum",
            (0.012, 0.015, 0.016),
            roughness=0.64,
            metallic=0.32,
        ),
        "glass": make_material(
            "MAT_ACM_TransparentSafetyShell",
            (0.58, 0.76, 0.79),
            roughness=0.13,
            metallic=0.0,
            alpha=0.24,
        ),
        "glass_edge": make_material(
            "MAT_ACM_GlassEdgeTint",
            (0.18, 0.48, 0.54),
            roughness=0.28,
            metallic=0.06,
            alpha=0.72,
        ),
        "vegetable_green": make_material(
            "MAT_ACM_GreenVegetables",
            (0.16, 0.52, 0.12),
            roughness=0.88,
            metallic=0.0,
        ),
        "vegetable_brown": make_material(
            "MAT_ACM_BrownVegetables",
            (0.38, 0.19, 0.065),
            roughness=0.92,
            metallic=0.0,
        ),
        "screen": make_material(
            "MAT_ACM_ControlScreen",
            (0.025, 0.34, 0.48),
            emission=(0.018, 0.42, 0.62),
            emission_strength=1.7,
        ),
        "green_light": make_material(
            "MAT_ACM_ReadyLight",
            (0.06, 0.82, 0.24),
            emission=(0.035, 0.75, 0.16),
            emission_strength=2.2,
        ),
        "orange_light": make_material(
            "MAT_ACM_HeatLight",
            (1.0, 0.24, 0.025),
            emission=(1.0, 0.17, 0.01),
            emission_strength=2.2,
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


def parent_keep_world(obj, parent):
    """Parent an object without changing its current world-space transform."""
    world_matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world_matrix


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
    """Create the ground-centred asset root."""
    root = bpy.data.objects.new(ROOT_NAME, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.28
    root.location = (0.0, 0.0, 0.0)

    root["asset_type"] = "FixedCookingMachine"
    root["tool_category"] = "AutomaticCookingMachine"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["origin_role"] = "GroundCenter"
    root["has_collision_mesh"] = False
    root["has_runtime_rotating_part"] = True
    root["runtime_rotating_node"] = "RotatingDrum"

    collection.objects.link(root)
    return root


def create_rotating_drum_pivot(root, collection):
    """Create the independent Node3D pivot exported for runtime rotation."""
    pivot = bpy.data.objects.new("RotatingDrum", None)
    pivot.empty_display_type = "ARROWS"
    pivot.empty_display_size = 0.28

    pivot["runtime_controlled"] = True
    pivot["rotation_axis_local"] = DRUM_ROTATION_AXIS
    pivot["rotation_purpose"] = "AutomaticCookingDrum"
    pivot["suggested_speed_degrees_per_second"] = 65.0

    collection.objects.link(pivot)
    # Root is guaranteed to be at the world origin. Parent first, then assign
    # the pivot's LOCAL position. The previous order assigned a world position
    # and immediately read matrix_world before Blender's dependency graph had
    # refreshed it; in background mode that matrix could still be identity,
    # which silently moved the pivot back to (0, 0, 0).
    pivot.parent = root
    pivot.location = DRUM_CENTER
    return pivot


# -----------------------------------------------------------------------------
# GEOMETRY HELPERS
# -----------------------------------------------------------------------------

def finish_object(
    obj,
    name,
    material,
    parent,
    collection,
    merge_group,
    bevel=0.0,
):
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)

    if bevel > 0.0:
        add_bevel(obj, bevel)

    obj["merge_group"] = merge_group
    parent_keep_world(obj, parent)
    move_to_collection(obj, collection)
    return obj


def add_cube(
    name,
    location,
    dimensions,
    material,
    parent,
    collection,
    merge_group,
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
        parent,
        collection,
        merge_group,
        bevel,
    )


def add_cylinder_between(
    name,
    p0,
    p1,
    radius,
    material,
    parent,
    collection,
    merge_group,
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
    return finish_object(
        bpy.context.object,
        name,
        material,
        parent,
        collection,
        merge_group,
        bevel,
    )


def add_torus(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    parent,
    collection,
    merge_group,
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
    return finish_object(
        bpy.context.object,
        name,
        material,
        parent,
        collection,
        merge_group,
    )


# -----------------------------------------------------------------------------
# BUILD: STATIC SILVER/GREY MACHINE BODY
# -----------------------------------------------------------------------------

def build_static_body(root, collection, mats):
    """Build the fixed cabinet, chamber frame, bearings and controls."""
    # Four rubber/metal feet touch the ground at z=0.
    for index, (x, y) in enumerate(((-0.61, -0.47), (0.61, -0.47), (-0.61, 0.47), (0.61, 0.47))):
        add_cube(
            f"Body_Foot_{index:02d}",
            (x, y, 0.06),
            (0.17, 0.17, 0.12),
            mats["dark_grey"],
            root,
            collection,
            GROUP_BODY,
            bevel=0.025,
        )

    add_cube(
        "Body_BasePlinth",
        (0.0, 0.0, 0.14),
        (1.55, 1.25, 0.18),
        mats["silver"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.055,
    )
    add_cube(
        "Body_LowerCabinet",
        (0.0, 0.02, 0.40),
        (1.43, 1.12, 0.48),
        mats["silver"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.045,
    )
    add_cube(
        "Body_FrontServicePanel",
        (0.0, -0.555, 0.40),
        (0.82, 0.030, 0.30),
        mats["dark_grey"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.025,
    )
    add_cube(
        "Body_ChamberFloor",
        (0.0, 0.0, 0.69),
        (1.43, 1.12, 0.16),
        mats["silver_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.035,
    )

    # Four vertical pillars and top beams define the transparent chamber.
    pillar_positions = (
        (-0.67, -0.53),
        (0.67, -0.53),
        (-0.67, 0.53),
        (0.67, 0.53),
    )
    for index, (x, y) in enumerate(pillar_positions):
        add_cube(
            f"Body_ChamberPillar_{index:02d}",
            (x, y, 1.28),
            (0.095, 0.095, 1.08),
            mats["silver_light"],
            root,
            collection,
            GROUP_BODY,
            bevel=0.018,
        )

    add_cube(
        "Body_TopBeamFront",
        (0.0, -0.53, 1.80),
        (1.43, 0.11, 0.12),
        mats["silver_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.020,
    )
    add_cube(
        "Body_TopBeamRear",
        (0.0, 0.53, 1.80),
        (1.43, 0.11, 0.12),
        mats["silver_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.020,
    )
    add_cube(
        "Body_TopBeamLeft",
        (-0.67, 0.0, 1.80),
        (0.11, 1.02, 0.12),
        mats["silver_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.020,
    )
    add_cube(
        "Body_TopBeamRight",
        (0.67, 0.0, 1.80),
        (0.11, 1.02, 0.12),
        mats["silver_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.020,
    )

    # Low top hood gives the machine a complete industrial appliance shape.
    add_cube(
        "Body_TopHood",
        (0.0, 0.0, 1.925),
        (1.22, 0.92, 0.13),
        mats["silver"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.045,
    )

    # Fixed bearing blocks meet the rotating axle at both sides.
    add_cube(
        "Body_DrumBearingLeft",
        (-0.61, 0.0, DRUM_CENTER.z),
        (0.20, 0.22, 0.22),
        mats["dark_grey"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.040,
    )
    add_cube(
        "Body_DrumBearingRight",
        (0.61, 0.0, DRUM_CENTER.z),
        (0.20, 0.22, 0.22),
        mats["dark_grey"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.040,
    )

    # Slanted front-right control console.
    add_cube(
        "Body_ControlConsole",
        (0.43, -0.625, 0.78),
        (0.45, 0.16, 0.29),
        mats["dark_grey"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.035,
        rotation=(math.radians(-12.0), 0.0, 0.0),
    )
    add_cube(
        "Body_ControlScreen",
        (0.37, -0.716, 0.81),
        (0.22, 0.025, 0.105),
        mats["screen"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.015,
        rotation=(math.radians(-12.0), 0.0, 0.0),
    )
    add_cube(
        "Body_ReadyButton",
        (0.53, -0.713, 0.80),
        (0.055, 0.022, 0.055),
        mats["green_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.012,
    )
    add_cube(
        "Body_HeatButton",
        (0.60, -0.713, 0.80),
        (0.055, 0.022, 0.055),
        mats["orange_light"],
        root,
        collection,
        GROUP_BODY,
        bevel=0.012,
    )


# -----------------------------------------------------------------------------
# BUILD: TRANSPARENT CHAMBER SHELL
# -----------------------------------------------------------------------------

def build_transparent_shell(root, collection, mats):
    """Build thin transparent panels as a dedicated renderable node."""
    # Front, rear and side safety-glass panels.
    add_cube(
        "Glass_FrontPanel",
        (0.0, -0.585, 1.28),
        (1.27, 0.025, 0.92),
        mats["glass"],
        root,
        collection,
        GROUP_GLASS,
        bevel=0.008,
    )
    add_cube(
        "Glass_RearPanel",
        (0.0, 0.585, 1.28),
        (1.27, 0.025, 0.92),
        mats["glass"],
        root,
        collection,
        GROUP_GLASS,
        bevel=0.008,
    )
    add_cube(
        "Glass_LeftPanel",
        (-0.715, 0.0, 1.28),
        (0.025, 1.05, 0.92),
        mats["glass"],
        root,
        collection,
        GROUP_GLASS,
        bevel=0.008,
    )
    add_cube(
        "Glass_RightPanel",
        (0.715, 0.0, 1.28),
        (0.025, 1.05, 0.92),
        mats["glass"],
        root,
        collection,
        GROUP_GLASS,
        bevel=0.008,
    )
    add_cube(
        "Glass_TopPanel",
        (0.0, 0.0, 1.845),
        (1.27, 1.05, 0.025),
        mats["glass"],
        root,
        collection,
        GROUP_GLASS,
        bevel=0.008,
    )

    # Cyan-tinted door edges make the transparent front readable in-game.
    for index, x in enumerate((-0.625, 0.625)):
        add_cube(
            f"Glass_FrontEdgeVertical_{index:02d}",
            (x, -0.602, 1.28),
            (0.025, 0.018, 0.88),
            mats["glass_edge"],
            root,
            collection,
            GROUP_GLASS,
            bevel=0.005,
        )
    for index, z in enumerate((0.84, 1.72)):
        add_cube(
            f"Glass_FrontEdgeHorizontal_{index:02d}",
            (0.0, -0.602, z),
            (1.25, 0.018, 0.025),
            mats["glass_edge"],
            root,
            collection,
            GROUP_GLASS,
            bevel=0.005,
        )


# -----------------------------------------------------------------------------
# BUILD: INDEPENDENT ROTATING DRUM + VEGETABLES
# -----------------------------------------------------------------------------

def build_rotating_drum(pivot, collection, mats):
    """Build a black open cage drum whose parent pivot rotates around X."""
    drum_half_length = 0.48
    drum_radius = 0.37

    # Two circular side rings. A torus normally lies in XY, so a 90-degree Y
    # rotation makes its ring plane YZ and its axis local/world X.
    for side_name, x in (("Left", -drum_half_length), ("Right", drum_half_length)):
        add_torus(
            f"Drum_EndRing{side_name}",
            (x, DRUM_CENTER.y, DRUM_CENTER.z),
            drum_radius,
            0.038,
            mats["black_drum"],
            pivot,
            collection,
            GROUP_DRUM,
            rotation=(0.0, math.radians(90.0), 0.0),
            major_segments=20,
            minor_segments=6,
        )

    # Eight longitudinal cage rails leave the food visible through the drum.
    for index in range(8):
        angle = math.tau * index / 8.0
        y = DRUM_CENTER.y + math.cos(angle) * drum_radius
        z = DRUM_CENTER.z + math.sin(angle) * drum_radius
        add_cylinder_between(
            f"Drum_LongitudinalRail_{index:02d}",
            (-drum_half_length, y, z),
            (drum_half_length, y, z),
            0.027,
            mats["black_drum"],
            pivot,
            collection,
            GROUP_DRUM,
            vertices=8,
        )

    # Central axle reaches into the fixed bearing blocks.
    add_cylinder_between(
        "Drum_CentralAxle",
        (-0.60, DRUM_CENTER.y, DRUM_CENTER.z),
        (0.60, DRUM_CENTER.y, DRUM_CENTER.z),
        0.055,
        mats["black_drum"],
        pivot,
        collection,
        GROUP_DRUM,
        vertices=12,
        bevel=0.004,
    )

    # Three internal paddles reinforce the tumbler silhouette.
    for index, angle in enumerate((0.0, math.tau / 3.0, 2.0 * math.tau / 3.0)):
        y = DRUM_CENTER.y + math.cos(angle) * 0.19
        z = DRUM_CENTER.z + math.sin(angle) * 0.19
        add_cube(
            f"Drum_InternalPaddle_{index:02d}",
            (0.0, y, z),
            (0.76, 0.055, 0.12),
            mats["black_drum"],
            pivot,
            collection,
            GROUP_DRUM,
            bevel=0.012,
            rotation=(angle, 0.0, 0.0),
        )

    # Simplified vegetable chunks. They are kept as a separate child mesh but
    # share RotatingDrum as parent, so they follow the drum at runtime.
    vegetable_specs = [
        ("Green", (-0.29, -0.05, 1.14), (0.16, 0.15, 0.13), (0.20, 0.10, 0.32)),
        ("Brown", (-0.10, 0.10, 1.10), (0.15, 0.13, 0.14), (-0.18, 0.28, 0.08)),
        ("Green", (0.09, -0.10, 1.13), (0.14, 0.17, 0.12), (0.12, -0.22, 0.18)),
        ("Brown", (0.28, 0.06, 1.15), (0.16, 0.14, 0.13), (-0.24, 0.06, -0.20)),
        ("Green", (-0.22, 0.02, 1.29), (0.13, 0.14, 0.12), (0.32, -0.12, 0.05)),
        ("Brown", (0.00, -0.04, 1.27), (0.17, 0.13, 0.12), (-0.08, 0.20, 0.30)),
        ("Green", (0.22, 0.08, 1.28), (0.15, 0.13, 0.14), (0.18, 0.24, -0.12)),
        ("Brown", (-0.03, 0.13, 1.40), (0.13, 0.15, 0.12), (0.28, -0.20, 0.16)),
        ("Green", (0.15, -0.13, 1.40), (0.12, 0.14, 0.13), (-0.22, 0.12, -0.24)),
    ]

    for index, (kind, location, dimensions, rotation) in enumerate(vegetable_specs):
        material = mats["vegetable_green"] if kind == "Green" else mats["vegetable_brown"]
        add_cube(
            f"Vegetable_{kind}_{index:02d}",
            location,
            dimensions,
            material,
            pivot,
            collection,
            GROUP_VEGETABLES,
            bevel=0.022,
            rotation=rotation,
        )


# -----------------------------------------------------------------------------
# HIERARCHY / VALIDATION HELPERS
# -----------------------------------------------------------------------------

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def get_group_meshes(root, group_name):
    return [
        obj
        for obj in get_meshes_under_root(root)
        if obj.get("merge_group", "") == group_name
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
    """Audit important structural connections before grouped meshes merge."""
    pairs = [
        ("Body_BasePlinth", "Body_LowerCabinet", 0.03),
        ("Body_LowerCabinet", "Body_ChamberFloor", 0.03),
        ("Body_ChamberPillar_00", "Body_ChamberFloor", 0.03),
        ("Body_ChamberPillar_01", "Body_ChamberFloor", 0.03),
        ("Body_ChamberPillar_02", "Body_ChamberFloor", 0.03),
        ("Body_ChamberPillar_03", "Body_ChamberFloor", 0.03),
        ("Body_TopBeamFront", "Body_ChamberPillar_00", 0.03),
        ("Body_TopBeamRear", "Body_ChamberPillar_02", 0.03),
        ("Body_TopHood", "Body_TopBeamFront", 0.08),
        ("Body_ControlConsole", "Body_LowerCabinet", 0.05),
        ("Body_DrumBearingLeft", "Drum_CentralAxle", 0.03),
        ("Body_DrumBearingRight", "Drum_CentralAxle", 0.03),
        ("Drum_EndRingLeft", "Drum_LongitudinalRail_00", 0.04),
        ("Drum_EndRingRight", "Drum_LongitudinalRail_00", 0.04),
        ("Glass_FrontPanel", "Body_TopBeamFront", 0.03),
        ("Glass_LeftPanel", "Body_ChamberPillar_00", 0.04),
        ("Glass_RightPanel", "Body_ChamberPillar_01", 0.04),
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


def validate_before_merge(root, rotating_drum):
    """Validate dimensions, node hierarchy and export-safe object types."""
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Root must be an Empty at ground centre (0, 0, 0).")

    if rotating_drum.type != "EMPTY":
        raise RuntimeError("RotatingDrum must remain an independent Empty/Node3D pivot.")
    if rotating_drum.parent != root:
        raise RuntimeError("RotatingDrum must be a direct child of the asset root.")
    if (rotating_drum.location - DRUM_CENTER).length > 0.0001:
        raise RuntimeError("RotatingDrum pivot moved away from the cooking drum centre.")

    bad_scene = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if bad_scene:
        raise RuntimeError("Cameras/lights remain in scene: " + ", ".join(bad_scene))

    meshes = get_meshes_under_root(root)
    if not meshes:
        raise RuntimeError("No mesh objects found under asset root.")

    required_groups = (GROUP_BODY, GROUP_GLASS, GROUP_DRUM, GROUP_VEGETABLES)
    missing_groups = [group for group in required_groups if not get_group_meshes(root, group)]
    if missing_groups:
        raise RuntimeError("Missing visual merge groups: " + ", ".join(missing_groups))

    failures = []
    for obj in meshes:
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale: " + obj.name)

        lowered = obj.name.lower()
        if lowered.startswith("ucx") or "collision" in lowered:
            failures.append("collision-like mesh name: " + obj.name)

    if failures:
        raise RuntimeError("ASSET VALIDATION FAILED:\n- " + "\n- ".join(failures))

    validate_attachment_pairs()

    low, high = bbox_world_all(meshes)
    dimensions = high - low
    if low.z < -0.01:
        raise RuntimeError(f"Asset extends below ground: low z={low.z:.3f} m")
    if dimensions.x > 1.65 or dimensions.y > 1.55 or high.z > 2.05:
        raise RuntimeError(
            "Asset exceeded intended cooking-machine bounds: "
            f"{dimensions.x:.3f} x {dimensions.y:.3f} x {high.z:.3f} m"
        )

    triangle_count = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangle_count += len(obj.data.loop_triangles)

    print(
        f"[VALID BEFORE MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.3f} m x {dimensions.y:.3f} m x {dimensions.z:.3f} m\n"
        f"  Meshes: {len(meshes)}\n"
        f"  Triangles: {triangle_count}\n"
        f"  Rotating node: {rotating_drum.name}, local axis {DRUM_ROTATION_AXIS}\n"
    )


# -----------------------------------------------------------------------------
# GROUP MERGE / POST-MERGE VALIDATION / EXPORT
# -----------------------------------------------------------------------------

def merge_mesh_group(root, group_name, merged_name, required_parent):
    """Merge one visual group while preserving its intended parent node."""
    meshes = get_group_meshes(root, group_name)
    if not meshes:
        raise RuntimeError(f"No meshes found for merge group {group_name}")

    for obj in meshes:
        if obj.parent != required_parent:
            raise RuntimeError(
                f"{obj.name} has wrong parent before merge; expected {required_parent.name}"
            )
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = merged_name
    merged["merge_group"] = group_name
    if merged.parent != required_parent:
        parent_keep_world(merged, required_parent)
    set_flat_shading(merged)
    return merged


def merge_visual_groups(root, rotating_drum):
    body = merge_mesh_group(root, GROUP_BODY, "Body_Static", root)
    glass = merge_mesh_group(root, GROUP_GLASS, "TransparentShell", root)
    drum = merge_mesh_group(root, GROUP_DRUM, "Drum_BlackMesh", rotating_drum)
    vegetables = merge_mesh_group(
        root,
        GROUP_VEGETABLES,
        "Vegetables_Visual",
        rotating_drum,
    )
    return body, glass, drum, vegetables


def validate_after_merge(root, rotating_drum):
    """Ensure the exported hierarchy still exposes the runtime drum pivot."""
    expected = {
        "Body_Static": root,
        "TransparentShell": root,
        "Drum_BlackMesh": rotating_drum,
        "Vegetables_Visual": rotating_drum,
    }

    for name, expected_parent in expected.items():
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"Missing merged export mesh: {name}")
        if obj.parent != expected_parent:
            raise RuntimeError(f"{name} has wrong parent after merge")

    if rotating_drum.parent != root:
        raise RuntimeError("RotatingDrum hierarchy was damaged during merge.")

    meshes = get_meshes_under_root(root)
    low, high = bbox_world_all(meshes)
    dimensions = high - low

    print(
        f"[VALID AFTER MERGE] {root.name}\n"
        f"  Bounds: {dimensions.x:.3f} m x {dimensions.y:.3f} m x {dimensions.z:.3f} m\n"
        f"  Export mesh nodes: {len(meshes)}\n"
        f"  Runtime pivot preserved: {rotating_drum.name}\n"
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
    print("\n=== Generating Automatic Cooking Machine ===\n")

    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    mats = build_materials()
    collection = get_or_create_collection(COLLECTION_NAME)
    root = create_root(collection)
    rotating_drum = create_rotating_drum_pivot(root, collection)

    build_static_body(root, collection, mats)
    build_transparent_shell(root, collection, mats)
    build_rotating_drum(rotating_drum, collection, mats)

    validate_before_merge(root, rotating_drum)

    if MERGE_VISUAL_GROUPS:
        merge_visual_groups(root, rotating_drum)

    validate_after_merge(root, rotating_drum)

    output_path = os.path.join(OUTPUT_DIR, OUTPUT_FILE)
    export_glb(root, output_path)

    print("\n=== Finished ===")
    print("Generated:")
    print(" - " + output_path)
    print("\nGodot hierarchy:")
    print(" - FTF_Tool_AutomaticCookingMachine_v1")
    print("   - Body_Static")
    print("   - TransparentShell")
    print("   - RotatingDrum  <- rotate around local X")
    print("     - Drum_BlackMesh")
    print("     - Vegetables_Visual")
    print("\nNotes:")
    print(" - Root is at ground centre (0, 0, 0).")
    print(" - Silver/grey body and transparent safety shell remain separate meshes.")
    print(" - RotatingDrum is an independent runtime Node3D at the drum axle centre.")
    print(" - Green and brown vegetable cubes follow the RotatingDrum parent.")
    print(" - Blender forward is -Y; intended Godot forward is -Z after GLB import.")


if __name__ == "__main__":
    main()
