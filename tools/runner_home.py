# FarmWar FarmRunner Dock
# Low-profile visual marker / charging-dock style base for FarmRunner
# Blender 4.4+ Python script
#
# ASSET CONTRACT:
# - Godot 4.x GLB-ready
# - Root origin at ground-center (0, 0, 0)
# - Z up; visual forward = local -Y
# - Exact maximum footprint: 1.50 m x 1.50 m
# - Low-profile, static, non-destructible visual base
# - Orange + black palette matching FarmRunner
# - No floating visible components
# - No lights, no collision shell, no textures, no gameplay logic
# - All static mesh pieces join before GLB export
#
# Intended gameplay usage:
# - Spawn this Dock at FarmRunner's initial placement location when activate_tool()
#   starts the runner.
# - It does not recharge, collide, or take damage.
# - It only tells players where the FarmRunner belongs / is active.
#
# OUTPUT:
# farm_runner_dock.glb beside this script.

import bpy
import os
from mathutils import Vector

# ---------------------------------------------------------------------
# SETTINGS
# ---------------------------------------------------------------------

CLEAR_SCENE = True
ROOT_NAME = "FarmRunnerDock"
JOIN_STATIC_MESHES_FOR_EXPORT = True

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
EXPORT_GLB_PATH = os.path.join(SCRIPT_DIR, "farm_runner_dock.glb")

# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_material(name, color, metallic=0.0, roughness=0.55):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


MAT_ORANGE = make_material("MAT_DockOrange", (0.92, 0.26, 0.045), 0.18, 0.42)
MAT_BLACK = make_material("MAT_DockBlack", (0.025, 0.035, 0.042), 0.35, 0.34)
MAT_DARK_GRAY = make_material("MAT_DockDarkGray", (0.11, 0.13, 0.14), 0.45, 0.42)
MAT_STEEL = make_material("MAT_DockSteel", (0.26, 0.31, 0.32), 0.42, 0.45)
MAT_STATUS_GREEN = make_material("MAT_DockStatusGreen", (0.16, 0.55, 0.23), 0.04, 0.30)

# ---------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------

def get_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for previous in list(obj.users_collection):
        previous.objects.unlink(obj)
    collection.objects.link(obj)


def set_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_bevel(obj, width=0.02):
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"


def add_empty(name, parent, collection, location=(0.0, 0.0, 0.0)):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=location)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cube(name, location, dimensions, material, parent, collection,
         rotation=(0.0, 0.0, 0.0), bevel_width=0.02):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    set_material(obj, material)
    if bevel_width > 0.0:
        add_bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def cylinder(name, location, radius, depth, material, parent, collection,
             vertices=12, rotation=(0.0, 0.0, 0.0), bevel_width=0.014):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    set_material(obj, material)
    if bevel_width > 0.0:
        add_bevel(obj, bevel_width)
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


def beam_between(name, start, end, radius, material, parent, collection, vertices=8):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    length = direction.length
    if length <= 0.0001:
        return None

    midpoint = (start + end) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=length,
        location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    obj.rotation_mode = "XYZ"
    set_material(obj, material)
    add_bevel(obj, min(radius * 0.35, 0.015))
    obj.parent = parent
    move_to_collection(obj, collection)
    return obj


# ---------------------------------------------------------------------
# ROOT
# ---------------------------------------------------------------------

if CLEAR_SCENE:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

collection = get_collection(ROOT_NAME)

bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
root = bpy.context.object
root.name = ROOT_NAME
move_to_collection(root, collection)

base_root = add_empty("DockBase", root, collection)
guide_root = add_empty("DockGuides", root, collection)
console_root = add_empty("RearDockConsole", root, collection)

root["asset_role"] = "FarmRunner_VisualDockMarker"
root["forward_axis"] = "-Y"
root["ground_origin"] = "0,0,0"
root["max_footprint_m"] = "1.50 x 1.50"
root["intended_use"] = "indestructible_visual_marker_only"
root["static_meshes_merged_on_export"] = True
root["no_collision_shell_generated"] = True

# ---------------------------------------------------------------------
# MAIN BASE: exact 1.50 x 1.50 footprint
# ---------------------------------------------------------------------

# Main low platform. Bottom rests on world ground.
cube(
    "DockBasePlatform",
    (0.0, 0.0, 0.075),
    (1.50, 1.50, 0.15),
    MAT_DARK_GRAY,
    base_root,
    collection,
    bevel_width=0.055
)

# Central black docking surface, recessed visually but physically attached.
# FarmRunner hovers over it; it is not an actual charging socket.
cylinder(
    "CentralDockPad",
    (0.0, 0.0, 0.162),
    0.43,
    0.025,
    MAT_BLACK,
    base_root,
    collection,
    vertices=12,
    bevel_width=0.010
)

# Orange center marker: a low attached ring surrogate built from four bars.
# The open center keeps the dock readable under FarmRunner.
for name, loc, size in [
    ("CenterMarkerFront", (0.0, -0.31, 0.180), (0.44, 0.055, 0.026)),
    ("CenterMarkerBack",  (0.0,  0.31, 0.180), (0.44, 0.055, 0.026)),
    ("CenterMarkerLeft",  (-0.31, 0.0, 0.180), (0.055, 0.44, 0.026)),
    ("CenterMarkerRight", (0.31, 0.0, 0.180), (0.055, 0.44, 0.026)),
]:
    cube(name, loc, size, MAT_ORANGE, base_root, collection, bevel_width=0.012)

# ---------------------------------------------------------------------
# LOW DOCKING GUIDE FRAME
# ---------------------------------------------------------------------

# Outer guide strips are intentionally low so the hovering FarmRunner is
# visually centered but not enclosed by walls.
for name, loc, size in [
    ("GuideFront", (0.0, -0.66, 0.205), (1.18, 0.09, 0.11)),
    ("GuideLeft",  (-0.66, 0.0, 0.205), (0.09, 1.18, 0.11)),
    ("GuideRight", (0.66, 0.0, 0.205), (0.09, 1.18, 0.11)),
]:
    cube(name, loc, size, MAT_ORANGE, guide_root, collection, bevel_width=0.026)

# Back guide has a centered gap to visually point toward the rear console.
cube(
    "GuideBackLeft",
    (-0.38, 0.66, 0.205),
    (0.40, 0.09, 0.11),
    MAT_ORANGE,
    guide_root,
    collection,
    bevel_width=0.026
)
cube(
    "GuideBackRight",
    (0.38, 0.66, 0.205),
    (0.40, 0.09, 0.11),
    MAT_ORANGE,
    guide_root,
    collection,
    bevel_width=0.026
)

# Four small black bumper pads attached at the guide corners.
for index, (x, y) in enumerate([
    (-0.60, -0.60),
    (0.60, -0.60),
    (-0.60, 0.60),
    (0.60, 0.60),
]):
    cube(
        f"DockCornerBumper_{index+1}",
        (x, y, 0.245),
        (0.16, 0.16, 0.10),
        MAT_BLACK,
        guide_root,
        collection,
        bevel_width=0.026
    )

# ---------------------------------------------------------------------
# REAR LOW CONSOLE
# ---------------------------------------------------------------------

# Fixed to the rear edge, kept inside the 1.50m square footprint.
# It gives a "charging dock" silhouette but has no actual gameplay charging.
cube(
    "RearConsoleBase",
    (0.0, 0.60, 0.245),
    (0.50, 0.20, 0.20),
    MAT_BLACK,
    console_root,
    collection,
    bevel_width=0.040
)

cube(
    "RearConsoleOrangeCap",
    (0.0, 0.60, 0.380),
    (0.42, 0.16, 0.09),
    MAT_ORANGE,
    console_root,
    collection,
    bevel_width=0.026
)

# The display panel is attached to the front face of the rear console.
cube(
    "RearConsolePanel",
    (0.0, 0.486, 0.315),
    (0.25, 0.024, 0.12),
    MAT_STEEL,
    console_root,
    collection,
    bevel_width=0.008
)

# One small status indicator, embedded into the panel.
cylinder(
    "RearConsoleStatus",
    (0.0, 0.470, 0.315),
    0.034,
    0.018,
    MAT_STATUS_GREEN,
    console_root,
    collection,
    vertices=10,
    rotation=(1.57079632679, 0.0, 0.0),
    bevel_width=0.006
)

# Two solid side braces; visibly join the rear console to the base.
beam_between(
    "ConsoleBraceLeft",
    (-0.19, 0.54, 0.19),
    (-0.19, 0.46, 0.34),
    0.028,
    MAT_STEEL,
    console_root,
    collection,
    vertices=8
)
beam_between(
    "ConsoleBraceRight",
    (0.19, 0.54, 0.19),
    (0.19, 0.46, 0.34),
    0.028,
    MAT_STEEL,
    console_root,
    collection,
    vertices=8
)

# ---------------------------------------------------------------------
# FRONT ALIGNMENT MARKERS
# ---------------------------------------------------------------------

# Three low orange rectangles clearly show where FarmRunner faces.
# All are attached to the top surface of the base.
for index, x in enumerate([-0.16, 0.0, 0.16]):
    cube(
        f"FrontAlignmentMark_{index+1}",
        (x, -0.48, 0.180),
        (0.08, 0.18, 0.026),
        MAT_ORANGE,
        base_root,
        collection,
        bevel_width=0.008
    )

# ---------------------------------------------------------------------
# EXPORT
# ---------------------------------------------------------------------

def merge_static_meshes_for_export():
    meshes = [obj for obj in collection.objects if obj.type == "MESH"]
    if len(meshes) <= 1:
        return meshes[0] if meshes else None

    # Apply all static bevel geometry before joining.
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = "FarmRunnerDock_Mesh"
    merged.parent = root
    return merged


if JOIN_STATIC_MESHES_FOR_EXPORT:
    merge_static_meshes_for_export()

bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for child in root.children_recursive:
    child.select_set(True)
bpy.context.view_layer.objects.active = root

output_dir = os.path.dirname(EXPORT_GLB_PATH)
if output_dir:
    os.makedirs(output_dir, exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=EXPORT_GLB_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT"
)

print(f"[FarmRunnerDock] GLB exported: {EXPORT_GLB_PATH}")
print("[FarmRunnerDock] Generated: 1.50m x 1.50m low-profile visual dock marker.")
