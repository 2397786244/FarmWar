# Food-War BoomBuggy
# Compact black remote self-destruct buggy - Blender 4.4+ generator
#
# OUTPUT:
#   boom_buggy.glb   (saved beside this script)
#
# ASSET CONTRACT
# - Godot-ready GLB, stylized low-poly game asset.
# - Root origin is at ground center (0, 0, 0).
# - Blender visual front is local -Y; on Godot glTF import this is intended
#   to read as the vehicle's +Z forward direction.
# - Maximum footprint is under 1.0m:
#       width ~0.94m, length ~0.96m, height ~0.52m.
# - Black-only industrial palette, except a small emissive red front camera.
# - Compact rear-mounted radio antenna is mechanically attached to the rear control block.
# - No decorative floating parts: every piece is attached to chassis, wheel,
#   camera housing, or another visible structural piece.
# - Four wheels remain separate nodes for Godot control:
#       WheelFrontLeft, WheelFrontRight, WheelRearLeft, WheelRearRight
#   Rotate each wheel ROOT around its local X axis to animate wheel spin.
# - Static chassis parts are merged before export.
# - Each wheel's tire/rim/hub parts are merged into one mesh beneath its
#   own wheel root, so the wheels remain independently controllable.
#
# NODE HIERARCHY AFTER EXPORT
# BoomBuggy
# ├── ChassisStatic
# │   └── BoomBuggy_ChassisMesh
# ├── FrontCamera
# │   └── FrontCameraLens
# ├── WheelFrontLeft
# │   └── WheelFrontLeft_Mesh
# ├── WheelFrontRight
# │   └── WheelFrontRight_Mesh
# ├── WheelRearLeft
# │   └── WheelRearLeft_Mesh
# └── WheelRearRight
#     └── WheelRearRight_Mesh

import bpy
import os
from math import cos, sin, pi, radians
from mathutils import Vector


# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------

CLEAR_SCENE = True
JOIN_STATIC_CHASSIS_MESHES = True
JOIN_WHEEL_MESHES = True

ROOT_NAME = "BoomBuggy"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
EXPORT_PATH = os.path.join(SCRIPT_DIR, "boom_buggy_v2_with_antenna.glb")


# ---------------------------------------------------------------------
# MATERIALS
# ---------------------------------------------------------------------

def make_principled_material(
    name: str,
    color: tuple[float, float, float],
    metallic: float,
    roughness: float,
    emission_color: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)

    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness

    # Blender 4.x uses Emission Color / Emission Strength. Guarded for
    # compatibility with nearby Blender 4.x point releases.
    if emission_color is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (
                emission_color[0],
                emission_color[1],
                emission_color[2],
                1.0,
            )
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (
                emission_color[0],
                emission_color[1],
                emission_color[2],
                1.0,
            )

        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return mat


MAT_BLACK = make_principled_material(
    "MAT_BoomBuggy_Black",
    (0.015, 0.018, 0.022),
    metallic=0.36,
    roughness=0.32,
)

MAT_CHARCOAL = make_principled_material(
    "MAT_BoomBuggy_Charcoal",
    (0.055, 0.065, 0.075),
    metallic=0.48,
    roughness=0.38,
)

MAT_RUBBER = make_principled_material(
    "MAT_BoomBuggy_Rubber",
    (0.006, 0.008, 0.010),
    metallic=0.02,
    roughness=0.68,
)

MAT_RED_CAMERA = make_principled_material(
    "MAT_BoomBuggy_CameraRed",
    (0.45, 0.005, 0.006),
    metallic=0.10,
    roughness=0.22,
    emission_color=(1.0, 0.0, 0.0),
    emission_strength=6.0,
)


# ---------------------------------------------------------------------
# COLLECTION / OBJECT HELPERS
# ---------------------------------------------------------------------

def ensure_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def add_empty(
    name: str,
    parent: bpy.types.Object | None,
    collection: bpy.types.Collection,
    location: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    return obj


def set_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_bevel(obj: bpy.types.Object, width: float, segments: int = 1) -> None:
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"


def cube_local(
    name: str,
    parent: bpy.types.Object,
    collection: bpy.types.Collection,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.01,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = rotation
    obj.dimensions = dimensions
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)
    set_material(obj, material)
    add_bevel(obj, bevel)
    return obj


def cylinder_local(
    name: str,
    parent: bpy.types.Object,
    collection: bpy.types.Collection,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 12,
    bevel: float = 0.008,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, collection)
    obj.parent = parent
    obj.location = location
    obj.rotation_euler = rotation
    set_material(obj, material)
    add_bevel(obj, bevel)
    return obj


def wedge_local(
    name: str,
    parent: bpy.types.Object,
    collection: bpy.types.Collection,
    location: tuple[float, float, float],
    width: float,
    length: float,
    front_height: float,
    back_height: float,
    material: bpy.types.Material,
    bevel: float = 0.01,
) -> bpy.types.Object:
    # Local front is -Y, rear is +Y.
    x = width * 0.5
    y = length * 0.5

    verts = [
        (-x, -y, 0.0),
        ( x, -y, 0.0),
        ( x,  y, 0.0),
        (-x,  y, 0.0),
        (-x, -y, front_height),
        ( x, -y, front_height),
        ( x,  y, back_height),
        (-x,  y, back_height),
    ]
    faces = [
        (0, 1, 2, 3),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
        (4, 7, 6, 5),
    ]

    mesh = bpy.data.meshes.new(f"{name}_MeshData")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    set_material(obj, material)
    add_bevel(obj, bevel)
    return obj


def apply_modifiers(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def join_meshes(
    meshes: list[bpy.types.Object],
    target_name: str,
    parent: bpy.types.Object,
) -> bpy.types.Object | None:
    valid = [obj for obj in meshes if obj is not None and obj.type == "MESH"]
    if not valid:
        return None

    for obj in valid:
        apply_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in valid:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = valid[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = target_name
    merged.parent = parent
    return merged


def descendant_meshes(parent: bpy.types.Object) -> list[bpy.types.Object]:
    return [obj for obj in parent.children_recursive if obj.type == "MESH"]


# ---------------------------------------------------------------------
# SCENE / ROOT
# ---------------------------------------------------------------------

if CLEAR_SCENE:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

collection = ensure_collection(ROOT_NAME)

root = add_empty(ROOT_NAME, None, collection)
root["asset_role"] = "FoodWar_BoomBuggy_RemoteSelfDestructCar"
root["root_origin"] = "ground_center_0_0_0"
root["blender_visual_front"] = "-Y"
root["godot_intended_forward"] = "+Z"
root["max_footprint_m"] = "0.94 x 0.96"
root["wheel_rotation_axis"] = "local X"
root["wheel_nodes"] = "WheelFrontLeft, WheelFrontRight, WheelRearLeft, WheelRearRight"
root["static_body_merged"] = True
root["no_decorative_floating_components"] = True

static_root = add_empty("ChassisStatic", root, collection)
camera_root = add_empty("FrontCamera", root, collection)

# ---------------------------------------------------------------------
# CHASSIS
# Overall footprint including wheels: width~0.94m, length~0.96m.
# Every visual piece attaches to a frame / body plate.
# ---------------------------------------------------------------------

# Main connected undercarriage. Wheel centers are z=0.14, so the chassis
# begins just above the wheel contact plane.
cube_local(
    "LowerChassisPlate",
    static_root,
    collection,
    location=(0.0, 0.0, 0.205),
    dimensions=(0.64, 0.72, 0.12),
    material=MAT_BLACK,
    bevel=0.028,
)

# Raised central self-destruct payload shell: visibly bolted into the deck.
cube_local(
    "PayloadHousing",
    static_root,
    collection,
    location=(0.0, 0.075, 0.355),
    dimensions=(0.48, 0.32, 0.20),
    material=MAT_CHARCOAL,
    bevel=0.035,
)

# Two structural rails attach the upper housing to the lower chassis.
for side, x in [("Left", -0.235), ("Right", 0.235)]:
    cube_local(
        f"PayloadRail_{side}",
        static_root,
        collection,
        location=(x, 0.075, 0.415),
        dimensions=(0.055, 0.38, 0.085),
        material=MAT_BLACK,
        bevel=0.018,
    )

# Low sloped nose creates a compact RC-buggy silhouette and connects directly
# to the front camera housing.
wedge_local(
    "FrontArmoredNose",
    static_root,
    collection,
    location=(0.0, -0.275, 0.245),
    width=0.60,
    length=0.31,
    front_height=0.08,
    back_height=0.20,
    material=MAT_CHARCOAL,
    bevel=0.022,
)

# Rear reinforcement block to visually anchor the payload housing.
cube_local(
    "RearBrace",
    static_root,
    collection,
    location=(0.0, 0.365, 0.275),
    dimensions=(0.54, 0.14, 0.16),
    material=MAT_BLACK,
    bevel=0.024,
)

# Bottom side rails connect front and rear of the chassis.
for side, x in [("Left", -0.315), ("Right", 0.315)]:
    cube_local(
        f"SideRail_{side}",
        static_root,
        collection,
        location=(x, 0.00, 0.225),
        dimensions=(0.045, 0.70, 0.085),
        material=MAT_CHARCOAL,
        bevel=0.014,
    )

# Front bumper and its two braced connectors. All are physically joined.
cube_local(
    "FrontBumper",
    static_root,
    collection,
    location=(0.0, -0.470, 0.165),
    dimensions=(0.62, 0.065, 0.075),
    material=MAT_BLACK,
    bevel=0.022,
)
for side, x in [("Left", -0.245), ("Right", 0.245)]:
    brace = cube_local(
        f"FrontBumperBrace_{side}",
        static_root,
        collection,
        location=(x, -0.405, 0.185),
        dimensions=(0.055, 0.16, 0.055),
        material=MAT_BLACK,
        rotation=(radians(26.0), 0.0, 0.0),
        bevel=0.012,
    )

# Compact top plate joins payload housing to nose. No loose visual panel.
cube_local(
    "TopAccessPlate",
    static_root,
    collection,
    location=(0.0, -0.095, 0.435),
    dimensions=(0.34, 0.24, 0.055),
    material=MAT_BLACK,
    bevel=0.018,
)

# Small structural bolts / studs are low-poly cylinders, visibly embedded into
# the top plate rather than floating.
for index, (x, y) in enumerate([
    (-0.13, -0.17),
    (0.13, -0.17),
    (-0.13, -0.02),
    (0.13, -0.02),
]):
    cylinder_local(
        f"TopBolt_{index+1}",
        static_root,
        collection,
        location=(x, y, 0.470),
        radius=0.018,
        depth=0.015,
        material=MAT_CHARCOAL,
        vertices=8,
        bevel=0.003,
    )

# Rear compact radio/control block is directly attached to the rear brace.
cube_local(
    "RearControlBlock",
    static_root,
    collection,
    location=(0.0, 0.385, 0.405),
    dimensions=(0.24, 0.12, 0.15),
    material=MAT_CHARCOAL,
    bevel=0.022,
)

# Small remote-control antenna. The base touches the rear control block,
# the mast enters the base, and the cap sits directly on the mast.
# No element is decorative or floating.
cylinder_local(
    "AntennaBase",
    static_root,
    collection,
    location=(0.0, 0.385, 0.493),
    radius=0.040,
    depth=0.055,
    material=MAT_BLACK,
    vertices=10,
    bevel=0.006,
)

cylinder_local(
    "AntennaMast",
    static_root,
    collection,
    location=(0.0, 0.385, 0.615),
    radius=0.012,
    depth=0.205,
    material=MAT_BLACK,
    vertices=8,
    bevel=0.003,
)

cylinder_local(
    "AntennaTip",
    static_root,
    collection,
    location=(0.0, 0.385, 0.728),
    radius=0.018,
    depth=0.034,
    material=MAT_CHARCOAL,
    vertices=8,
    bevel=0.004,
)

# ---------------------------------------------------------------------
# FRONT RED CAMERA
# Camera is recessed into an attached front housing, not floating.
# ---------------------------------------------------------------------

cube_local(
    "CameraHousing",
    camera_root,
    collection,
    location=(0.0, -0.408, 0.270),
    dimensions=(0.20, 0.105, 0.155),
    material=MAT_BLACK,
    bevel=0.024,
)

# Cylinder axis becomes -Y after X rotation. It is embedded into CameraHousing.
cylinder_local(
    "CameraBezel",
    camera_root,
    collection,
    location=(0.0, -0.470, 0.270),
    radius=0.064,
    depth=0.030,
    material=MAT_CHARCOAL,
    rotation=(radians(90.0), 0.0, 0.0),
    vertices=12,
    bevel=0.006,
)

cylinder_local(
    "FrontCameraLens",
    camera_root,
    collection,
    location=(0.0, -0.490, 0.270),
    radius=0.044,
    depth=0.018,
    material=MAT_RED_CAMERA,
    rotation=(radians(90.0), 0.0, 0.0),
    vertices=16,
    bevel=0.004,
)

# Small camera guard bars mechanically connect to the front bumper area.
for side, x in [("Left", -0.105), ("Right", 0.105)]:
    cube_local(
        f"CameraGuard_{side}",
        camera_root,
        collection,
        location=(x, -0.440, 0.220),
        dimensions=(0.030, 0.10, 0.10),
        material=MAT_BLACK,
        rotation=(radians(-17.0), 0.0, 0.0),
        bevel=0.008,
    )

# ---------------------------------------------------------------------
# WHEELS
# Each root pivot is exactly at the axle center. In Godot rotate the wheel
# root around local X for rolling. Wheels are intentionally not joined to
# ChassisStatic.
# ---------------------------------------------------------------------

WHEEL_RADIUS = 0.140
WHEEL_WIDTH = 0.105
WHEEL_CENTER_Z = WHEEL_RADIUS
WHEEL_X = 0.330
WHEEL_FRONT_Y = -0.275
WHEEL_REAR_Y = 0.275


def build_wheel(
    name: str,
    location: tuple[float, float, float],
    mirrored_side: int,
) -> bpy.types.Object:
    wheel_root = add_empty(name, root, collection, location=location)
    wheel_root["godot_rotation_axis"] = "X"
    wheel_root["role"] = "independent_wheel_control_node"
    wheel_root["front_pair"] = "true" if "Front" in name else "false"

    # Tire cylinder: default Z axis is turned to local X axle axis.
    cylinder_local(
        f"{name}_Tire",
        wheel_root,
        collection,
        location=(0.0, 0.0, 0.0),
        radius=WHEEL_RADIUS,
        depth=WHEEL_WIDTH,
        material=MAT_RUBBER,
        rotation=(0.0, radians(90.0), 0.0),
        vertices=16,
        bevel=0.010,
    )

    # Outer and inner rims are recessed into the tire, remaining fully attached.
    outer_x = mirrored_side * (WHEEL_WIDTH * 0.5 + 0.002)
    inner_x = -mirrored_side * (WHEEL_WIDTH * 0.5 + 0.002)

    for rim_name, x in [("OuterRim", outer_x), ("InnerRim", inner_x)]:
        cylinder_local(
            f"{name}_{rim_name}",
            wheel_root,
            collection,
            location=(x, 0.0, 0.0),
            radius=0.084,
            depth=0.010,
            material=MAT_CHARCOAL,
            rotation=(0.0, radians(90.0), 0.0),
            vertices=12,
            bevel=0.006,
        )

    cylinder_local(
        f"{name}_Hub",
        wheel_root,
        collection,
        location=(outer_x + mirrored_side * 0.007, 0.0, 0.0),
        radius=0.040,
        depth=0.016,
        material=MAT_BLACK,
        rotation=(0.0, radians(90.0), 0.0),
        vertices=10,
        bevel=0.004,
    )

    # Eight low-profile tread bars touch the tire surface. They are not floating.
    # The bars give wheel readability while keeping a compact low-poly count.
    for tread_index in range(8):
        angle = (2.0 * pi * tread_index) / 8.0
        y = cos(angle) * (WHEEL_RADIUS * 0.90)
        z = sin(angle) * (WHEEL_RADIUS * 0.90)

        tread = cube_local(
            f"{name}_Tread_{tread_index+1}",
            wheel_root,
            collection,
            location=(0.0, y, z),
            dimensions=(WHEEL_WIDTH + 0.010, 0.045, 0.034),
            material=MAT_RUBBER,
            rotation=(radians(angle), 0.0, 0.0),
            bevel=0.004,
        )

    return wheel_root


wheel_front_left = build_wheel(
    "WheelFrontLeft",
    (-WHEEL_X, WHEEL_FRONT_Y, WHEEL_CENTER_Z),
    mirrored_side=-1,
)
wheel_front_right = build_wheel(
    "WheelFrontRight",
    (WHEEL_X, WHEEL_FRONT_Y, WHEEL_CENTER_Z),
    mirrored_side=1,
)
wheel_rear_left = build_wheel(
    "WheelRearLeft",
    (-WHEEL_X, WHEEL_REAR_Y, WHEEL_CENTER_Z),
    mirrored_side=-1,
)
wheel_rear_right = build_wheel(
    "WheelRearRight",
    (WHEEL_X, WHEEL_REAR_Y, WHEEL_CENTER_Z),
    mirrored_side=1,
)

# Wheel suspension struts are chassis pieces. They end at the wheel-center
# region, visually connecting every wheel to the body without parenting
# wheel meshes into the static chassis.
for wheel_name, wx, wy in [
    ("FrontLeft", -WHEEL_X, WHEEL_FRONT_Y),
    ("FrontRight", WHEEL_X, WHEEL_FRONT_Y),
    ("RearLeft", -WHEEL_X, WHEEL_REAR_Y),
    ("RearRight", WHEEL_X, WHEEL_REAR_Y),
]:
    # Short axle housing directly reaches toward each wheel center.
    cube_local(
        f"AxleArm_{wheel_name}",
        static_root,
        collection,
        location=(wx * 0.74, wy, 0.205),
        dimensions=(0.18, 0.060, 0.065),
        material=MAT_CHARCOAL,
        bevel=0.012,
    )

    # Vertical/diagonal-looking support inside the wheel arch.
    cube_local(
        f"SuspensionLink_{wheel_name}",
        static_root,
        collection,
        location=(wx * 0.77, wy * 0.92, 0.255),
        dimensions=(0.045, 0.060, 0.145),
        material=MAT_BLACK,
        rotation=(0.0, radians(20.0 if wx > 0 else -20.0), 0.0),
        bevel=0.010,
    )

# ---------------------------------------------------------------------
# MERGE POLICY
# - All chassis meshes merge to one static chassis mesh.
# - Red lens remains separate under FrontCamera for easy glow / effects.
# - Camera housing + guard bars merge into one camera body mesh.
# - Each wheel merges into one mesh under that wheel's pivot.
# ---------------------------------------------------------------------

if JOIN_STATIC_CHASSIS_MESHES:
    chassis_mesh = join_meshes(
        descendant_meshes(static_root),
        "BoomBuggy_ChassisMesh",
        static_root,
    )

    camera_meshes = [
        obj for obj in descendant_meshes(camera_root)
        if obj.name != "FrontCameraLens"
    ]
    if camera_meshes:
        join_meshes(camera_meshes, "FrontCameraHousingMesh", camera_root)

if JOIN_WHEEL_MESHES:
    for wheel_root in [
        wheel_front_left,
        wheel_front_right,
        wheel_rear_left,
        wheel_rear_right,
    ]:
        join_meshes(
            descendant_meshes(wheel_root),
            f"{wheel_root.name}_Mesh",
            wheel_root,
        )

# ---------------------------------------------------------------------
# EXPORT
# ---------------------------------------------------------------------

bpy.context.view_layer.update()

bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for child in root.children_recursive:
    child.select_set(True)
bpy.context.view_layer.objects.active = root

output_dir = os.path.dirname(EXPORT_PATH)
if output_dir:
    os.makedirs(output_dir, exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=EXPORT_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT",
)

print(f"[BoomBuggy] Exported: {EXPORT_PATH}")
print("[BoomBuggy] Chassis static mesh merged; four wheel root nodes retained.")
