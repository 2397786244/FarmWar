# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# FarmWar / Farm Town - Chef Drivable Field Kitchen Vehicle
#
# Generates:
#   generated_field_kitchen_vehicle/
#     FTF_Vehicle_FieldKitchen_Green_v3.glb
#     FTF_Vehicle_FieldKitchen_Green_v3.blend
#
# DESIGN
# - Green, low-poly farm utility vehicle adapted into a mobile field kitchen.
# - Front-facing direction in Blender: local -Y.
# - Open single-driver cab large enough for the previously designed character.
# - Rear open-air kitchen module with NO roof and NO canopy.
# - Worktop includes a wooden cutting board (no knife) and a soup pot.
# - Storage cabinet is mounted below the worktop and opens toward the rear.
# - Steering wheel and all four wheels are separate pivot nodes for animation.
#
# EXPORTED HIERARCHY
#   FTF_Vehicle_FieldKitchen_Green_v1
#   |-- FTF_Vehicle_FieldKitchen_Green_v1_Static
#   |-- SteeringWheel
#   |   `-- SteeringWheel_Mesh
#   |-- Wheel_FL
#   |   `-- Wheel_FL_Mesh
#   |-- Wheel_FR
#   |   `-- Wheel_FR_Mesh
#   |-- Wheel_RL
#   |   `-- Wheel_RL_Mesh
#   |-- Wheel_RR
#   |   `-- Wheel_RR_Mesh
#   |-- DriverSeatPoint
#   |-- DriverEntryPoint
#   `-- KitchenInteractionPoint
#
# ANIMATION NOTES
# - Rotate SteeringWheel around its local Z axis.
# - Rotate Wheel_FL / FR / RL / RR around their local X axes to roll.
# - Front wheel steering yaw can be added in Godot with an extra parent pivot if
#   required by the vehicle controller.
#
# Run:
#   blender --background --factory-startup --python generate_field_kitchen_vehicle.py
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
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_field_kitchen_vehicle")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Vehicle_FieldKitchen_Green_v3.glb")
OUTPUT_BLEND = os.path.join(OUTPUT_DIR, "FTF_Vehicle_FieldKitchen_Green_v3.blend")

ROOT_NAME = "FTF_Vehicle_FieldKitchen_Green_v3"
STATIC_NAME = ROOT_NAME + "_Static"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV3_EMBEDDED_LAMPS"

CLEAR_SCENE = True
MERGE_STATIC_MESHES = True

AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

# Vehicle is roughly 3.5 m wide, 5.7 m long and 3.0 m tall.
DRIVER_SEAT_LOCATION = Vector((-0.42, -0.92, 1.76))
DRIVER_ENTRY_LOCATION = Vector((-1.38, -0.88, 1.10))
KITCHEN_INTERACTION_LOCATION = Vector((0.0, 2.48, 1.10))

WHEEL_SPECS = {
    "Wheel_FL": (-1.62, -1.62, 0.72),
    "Wheel_FR": (1.62, -1.62, 0.72),
    "Wheel_RL": (-1.62, 1.52, 0.72),
    "Wheel_RR": (1.62, 1.52, 0.72),
}


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



def make_material(name, color, metallic=0.0, roughness=0.55, emission=None, emission_strength=0.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
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
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material



def build_materials():
    return {
        "green": make_material("MAT_FK_FieldGreen", (0.07, 0.42, 0.17), 0.08, 0.46),
        "green_light": make_material("MAT_FK_LightGreen", (0.18, 0.56, 0.25), 0.06, 0.50),
        "green_dark": make_material("MAT_FK_DarkGreen", (0.025, 0.16, 0.075), 0.18, 0.42),
        "cream": make_material("MAT_FK_WarmCream", (0.90, 0.78, 0.49), 0.02, 0.55),
        "black": make_material("MAT_FK_RubberBlack", (0.012, 0.016, 0.014), 0.0, 0.84),
        "metal": make_material("MAT_FK_FrameMetal", (0.11, 0.14, 0.13), 0.64, 0.32),
        "steel": make_material("MAT_FK_CounterSteel", (0.50, 0.55, 0.55), 0.58, 0.28),
        "wood": make_material("MAT_FK_CuttingBoardWood", (0.52, 0.27, 0.08), 0.02, 0.70),
        "seat": make_material("MAT_FK_DriverSeat", (0.16, 0.20, 0.16), 0.0, 0.76),
        "pot": make_material("MAT_FK_SoupPot", (0.10, 0.12, 0.12), 0.48, 0.34),
        "soup": make_material("MAT_FK_SoupSurface", (0.74, 0.25, 0.055), 0.0, 0.48),
        "lamp": make_material(
            "MAT_FK_Headlamp", (0.72, 0.93, 1.0), emission=(0.50, 0.80, 1.0), emission_strength=1.4
        ),
        "red_lamp": make_material(
            "MAT_FK_RearLamp", (0.94, 0.03, 0.035), emission=(0.85, 0.02, 0.02), emission_strength=1.2
        ),
        "orange": make_material("MAT_FK_SafetyOrange", (0.94, 0.25, 0.025), 0.04, 0.40),
        "glass": make_material("MAT_FK_WindshieldBlue", (0.22, 0.42, 0.48), 0.15, 0.22),
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



def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = False



def set_smooth_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True



def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)



def add_bevel(obj, width=0.02, segments=1):
    modifier = obj.modifiers.new("SoftGameEdges", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier



def finish_mesh(obj, name, material, collection, bevel=0.0, smooth=False):
    obj.name = name
    assign_material(obj, material)
    if smooth:
        set_smooth_shading(obj)
    else:
        set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel, 1)
    move_to_collection(obj, collection)
    return obj



def add_cube(name, location, dimensions, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel=bevel, smooth=False)



def add_cylinder(
    name,
    location,
    radius,
    depth,
    material,
    collection,
    rotation=(0.0, 0.0, 0.0),
    vertices=16,
    bevel=0.0,
    smooth=True,
):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return finish_mesh(
        bpy.context.object,
        name,
        material,
        collection,
        bevel=bevel,
        smooth=smooth,
    )



def add_torus(
    name,
    location,
    major_radius,
    minor_radius,
    material,
    collection,
    rotation=(0.0, 0.0, 0.0),
    major_segments=18,
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
    return finish_mesh(bpy.context.object, name, material, collection, smooth=True)



def add_cylinder_between(name, start, end, radius, material, collection, vertices=12, bevel=0.0):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    if direction.length <= 0.0001:
        raise RuntimeError(f"Cannot create zero-length cylinder: {name}")
    midpoint = (start_v + end_v) * 0.5
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    return add_cylinder(
        name,
        midpoint,
        radius,
        direction.length,
        material,
        collection,
        rotation=rotation,
        vertices=vertices,
        bevel=bevel,
    )



def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.20):
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    if parent is not None:
        obj.parent = parent
    collection.objects.link(obj)
    return obj



def parent_keep_local(obj, parent):
    obj.parent = parent



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



def join_meshes(meshes, result_name, parent):
    if not meshes:
        raise RuntimeError(f"No meshes supplied for join: {result_name}")
    for obj in meshes:
        apply_transforms_and_modifiers(obj)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

    merged = bpy.context.object
    merged.name = result_name
    merged.parent = parent
    set_flat_shading(merged)
    return merged


# -----------------------------------------------------------------------------
# RUNTIME PIVOT PARTS
# -----------------------------------------------------------------------------


def build_wheel(name, location, materials, collection, root):
    pivot = create_empty(name, location, collection, parent=root, display_type="CIRCLE", size=0.32)
    pivot["animation_role"] = "VehicleWheel"
    pivot["roll_axis"] = "LocalX"

    # Child geometry is authored around local origin, then moved by the pivot.
    meshes = []
    radius = 0.69
    width = 0.48

    meshes.append(add_cylinder(
        name + "_Tire",
        (0.0, 0.0, 0.0),
        radius,
        width,
        materials["black"],
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=18,
        bevel=0.035,
    ))
    meshes.append(add_cylinder(
        name + "_Hub",
        (0.0, 0.0, 0.0),
        0.31,
        width + 0.035,
        materials["cream"],
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=14,
        bevel=0.026,
    ))
    meshes.append(add_cylinder(
        name + "_HubCap",
        (0.0, 0.0, 0.0),
        0.12,
        width + 0.07,
        materials["green_dark"],
        collection,
        rotation=(0.0, math.radians(90.0), 0.0),
        vertices=12,
        bevel=0.012,
    ))

    # Large, readable tread blocks. All are part of the wheel pivot.
    for index in range(10):
        angle = index * math.tau / 10.0
        tread = add_cube(
            f"{name}_Tread_{index:02d}",
            (0.0, math.sin(angle) * 0.64, math.cos(angle) * 0.64),
            (width + 0.06, 0.18, 0.11),
            materials["black"],
            collection,
            bevel=0.012,
            rotation=(angle, 0.0, 0.0),
        )
        meshes.append(tread)

    for mesh in meshes:
        parent_keep_local(mesh, pivot)
    join_meshes(meshes, name + "_Mesh", pivot)
    return pivot



def build_steering_wheel(materials, collection, root):
    pivot = create_empty(
        "SteeringWheel",
        (-0.45, -1.35, 2.32),
        collection,
        parent=root,
        display_type="CIRCLE",
        size=0.24,
    )
    pivot.rotation_euler = (math.radians(-52.0), 0.0, 0.0)
    pivot["animation_role"] = "SteeringWheel"
    pivot["rotation_axis"] = "LocalZ"

    meshes = []
    meshes.append(add_torus(
        "SteeringWheel_Rim",
        (0.0, 0.0, 0.0),
        0.255,
        0.034,
        materials["green_dark"],
        collection,
        major_segments=18,
        minor_segments=6,
    ))
    meshes.append(add_cylinder(
        "SteeringWheel_Hub",
        (0.0, 0.0, 0.0),
        0.075,
        0.09,
        materials["orange"],
        collection,
        vertices=12,
        bevel=0.012,
    ))
    for index, angle in enumerate((0.0, 120.0, 240.0)):
        radians = math.radians(angle)
        length = 0.18
        mesh = add_cube(
            f"SteeringWheel_Spoke_{index:02d}",
            (math.cos(radians) * length * 0.5, math.sin(radians) * length * 0.5, 0.0),
            (length, 0.035, 0.035),
            materials["green_dark"],
            collection,
            bevel=0.006,
            rotation=(0.0, 0.0, radians),
        )
        meshes.append(mesh)

    for mesh in meshes:
        parent_keep_local(mesh, pivot)
    join_meshes(meshes, "SteeringWheel_Mesh", pivot)
    return pivot


# -----------------------------------------------------------------------------
# STATIC VEHICLE BODY
# -----------------------------------------------------------------------------


def build_static_body(materials, collection, root):
    parts = []

    # Main frame and front vehicle body. Front direction is -Y.
    parts += [
        add_cube("Chassis_MainFrame", (0.0, 0.05, 0.82), (3.15, 5.10, 0.30), materials["green_dark"], collection, 0.085),
        add_cube("Front_Nose", (0.0, -2.18, 1.28), (2.48, 0.72, 0.80), materials["green"], collection, 0.15),
        add_cube("Front_CreamBand", (0.0, -2.55, 1.12), (1.82, 0.08, 0.24), materials["cream"], collection, 0.024),
        add_cube("Front_Bumper", (0.0, -2.62, 0.80), (2.70, 0.20, 0.24), materials["metal"], collection, 0.045),
        add_cube("Cab_Floor", (0.0, -1.25, 1.22), (2.50, 1.36, 0.18), materials["green_dark"], collection, 0.050),
        add_cube("Cab_LeftSidePanel", (-1.12, -1.25, 1.68), (0.20, 1.24, 0.76), materials["green"], collection, 0.060),
        add_cube("Cab_RightSidePanel", (1.12, -1.25, 1.68), (0.20, 1.24, 0.76), materials["green"], collection, 0.060),
        add_cube("Dashboard", (0.0, -1.82, 1.98), (1.96, 0.32, 0.44), materials["cream"], collection, 0.070),
        add_cube("Dashboard_DarkPanel", (-0.42, -1.995, 2.03), (0.70, 0.045, 0.24), materials["green_dark"], collection, 0.012),
        add_cube("Cab_LowWindshield", (0.0, -2.00, 2.48), (2.06, 0.08, 0.72), materials["glass"], collection, 0.035),
        add_cube("Cab_WindshieldLowerFrame", (0.0, -1.99, 2.12), (2.20, 0.12, 0.10), materials["metal"], collection, 0.025),
        add_cube("Cab_WindshieldUpperFrame", (0.0, -1.99, 2.84), (2.20, 0.12, 0.10), materials["metal"], collection, 0.025),
        add_cube("Cab_WindshieldLeftFrame", (-1.05, -1.99, 2.48), (0.10, 0.12, 0.74), materials["metal"], collection, 0.025),
        add_cube("Cab_WindshieldRightFrame", (1.05, -1.99, 2.48), (0.10, 0.12, 0.74), materials["metal"], collection, 0.025),
        add_cube("Cab_LeftFootboard", (-1.30, -1.22, 1.08), (0.38, 1.04, 0.12), materials["metal"], collection, 0.025),
        add_cube("Cab_RightFootboard", (1.30, -1.22, 1.08), (0.38, 1.04, 0.12), materials["metal"], collection, 0.025),
    ]

    # Driver seat sized for the previously designed humanoid character.
    parts += [
        add_cube("DriverSeat_Cushion", (-0.42, -0.92, 1.55), (1.08, 0.62, 0.24), materials["seat"], collection, 0.090),
        add_cube(
            "DriverSeat_Back",
            (-0.42, -0.59, 2.03),
            (1.10, 0.20, 0.92),
            materials["seat"],
            collection,
            0.095,
            rotation=(math.radians(-7.0), 0.0, 0.0),
        ),
        add_cube("PassengerUtilityBox", (0.69, -0.87, 1.54), (0.74, 0.65, 0.42), materials["green"], collection, 0.055),
        add_cube("Driver_LeftPedal", (-0.28, -1.58, 1.40), (0.16, 0.22, 0.06), materials["metal"], collection, 0.014),
        add_cube("Driver_RightPedal", (0.02, -1.58, 1.40), (0.16, 0.22, 0.06), materials["metal"], collection, 0.014),
    ]

    # Steering column remains static. Only the wheel itself is a rotatable node.
    parts.append(add_cylinder_between(
        "SteeringColumn",
        (-0.45, -1.67, 1.90),
        (-0.45, -1.35, 2.32),
        0.045,
        materials["metal"],
        collection,
        vertices=10,
        bevel=0.010,
    ))

    # Transition between cab and open rear kitchen module.
    parts += [
        add_cube("Kitchen_ModuleFloor", (0.0, 0.82, 1.18), (2.88, 2.78, 0.20), materials["green"], collection, 0.060),
        add_cube("Kitchen_FrontPartition", (0.0, -0.43, 1.93), (2.70, 0.15, 1.46), materials["green_dark"], collection, 0.055),
        add_cube("Kitchen_LeftLowWall", (-1.34, 0.83, 1.56), (0.16, 2.58, 0.72), materials["green"], collection, 0.050),
        add_cube("Kitchen_RightLowWall", (1.34, 0.83, 1.56), (0.16, 2.58, 0.72), materials["green"], collection, 0.050),
        add_cube("Kitchen_RearStep", (0.0, 2.36, 0.98), (2.54, 0.36, 0.18), materials["metal"], collection, 0.035),
        add_cube("Kitchen_RearBumper", (0.0, 2.60, 0.74), (2.80, 0.22, 0.22), materials["metal"], collection, 0.045),
    ]

    # Large rear-facing storage cabinet below the worktop.
    parts += [
        add_cube("Kitchen_CabinetBody", (0.0, 1.04, 1.58), (2.42, 1.14, 0.82), materials["green_dark"], collection, 0.055),
        add_cube("Kitchen_CabinetLeftDoor", (-0.59, 1.615, 1.58), (1.13, 0.08, 0.70), materials["green_light"], collection, 0.035),
        add_cube("Kitchen_CabinetRightDoor", (0.59, 1.615, 1.58), (1.13, 0.08, 0.70), materials["green_light"], collection, 0.035),
        add_cube("Kitchen_CabinetCenterDivider", (0.0, 1.66, 1.58), (0.06, 0.10, 0.74), materials["metal"], collection, 0.012),
        add_cube("Kitchen_CabinetLeftHandle", (-0.12, 1.68, 1.62), (0.08, 0.06, 0.25), materials["metal"], collection, 0.010),
        add_cube("Kitchen_CabinetRightHandle", (0.12, 1.68, 1.62), (0.08, 0.06, 0.25), materials["metal"], collection, 0.010),
    ]

    # Stainless worktop and backsplash. There is intentionally no roof/canopy.
    parts += [
        add_cube("Kitchen_Worktop", (0.0, 1.02, 2.06), (2.55, 1.18, 0.16), materials["steel"], collection, 0.035),
        add_cube("Kitchen_BackSplash", (0.0, 0.46, 2.40), (2.45, 0.10, 0.62), materials["green_light"], collection, 0.030),
        add_cube("Kitchen_BackSplashSteelTrim", (0.0, 0.41, 2.70), (2.52, 0.08, 0.08), materials["steel"], collection, 0.016),
    ]

    # Wooden cutting board. No knife or blade geometry is created.
    parts += [
        add_cube("Kitchen_CuttingBoard", (-0.66, 1.10, 2.18), (0.82, 0.50, 0.09), materials["wood"], collection, 0.030),
        add_cube("Kitchen_CuttingBoardGrip", (-1.03, 1.10, 2.18), (0.16, 0.18, 0.09), materials["wood"], collection, 0.022),
    ]

    # Soup pot with visible rim, handles and soup surface.
    parts += [
        add_cylinder("Kitchen_SoupPotBody", (0.70, 1.10, 2.38), 0.36, 0.40, materials["pot"], collection, vertices=18, bevel=0.020),
        add_torus("Kitchen_SoupPotRim", (0.70, 1.10, 2.59), 0.34, 0.028, materials["steel"], collection, major_segments=18, minor_segments=6),
        add_cylinder("Kitchen_SoupSurface", (0.70, 1.10, 2.595), 0.285, 0.025, materials["soup"], collection, vertices=18, bevel=0.004),
        add_cube("Kitchen_SoupPotHandleLeft", (0.28, 1.10, 2.42), (0.18, 0.10, 0.10), materials["pot"], collection, 0.018),
        add_cube("Kitchen_SoupPotHandleRight", (1.12, 1.10, 2.42), (0.18, 0.10, 0.10), materials["pot"], collection, 0.018),
        add_cube("Kitchen_SoupPotBurnerBase", (0.70, 1.10, 2.17), (0.82, 0.64, 0.08), materials["green_dark"], collection, 0.025),
    ]

    # Small rear service shelf and safety rails, still leaving the kitchen open-air.
    parts += [
        add_cube("Kitchen_RearServiceShelf", (0.0, 1.88, 1.92), (2.40, 0.26, 0.13), materials["cream"], collection, 0.030),
        add_cylinder_between("Kitchen_LeftRearRail", (-1.25, 1.34, 1.25), (-1.25, 2.16, 1.25), 0.045, materials["metal"], collection, 10, 0.010),
        add_cylinder_between("Kitchen_RightRearRail", (1.25, 1.34, 1.25), (1.25, 2.16, 1.25), 0.045, materials["metal"], collection, 10, 0.010),
    ]

    # Dedicated lamp housings. Front pods project beyond the cream band so the
    # lights remain fully visible. Rear vertical towers connect the tail lamps
    # directly to the rear bumper instead of leaving them suspended in space.
    for side, x in (("L", -0.72), ("R", 0.72)):
        parts.append(add_cube(
            f"Front_HeadlampPod_{side}",
            (x, -2.56, 1.48),
            (0.34, 0.18, 0.32),
            materials["green_dark"],
            collection,
            0.025,
        ))
        parts.append(add_cylinder(
            "Front_Headlamp_L" if x < 0 else "Front_Headlamp_R",
            (x, -2.66, 1.48),
            0.14,
            0.10,
            materials["lamp"],
            collection,
            rotation=(math.radians(90.0), 0.0, 0.0),
            vertices=12,
            bevel=0.016,
        ))

    for side, x in (("L", -1.12), ("R", 1.12)):
        parts.append(add_cube(
            f"Rear_LampTower_{side}",
            (x, 2.47, 1.15),
            (0.26, 0.18, 0.66),
            materials["green_dark"],
            collection,
            0.025,
        ))
        parts.append(add_cylinder(
            "Rear_Lamp_L" if x < 0 else "Rear_Lamp_R",
            (x, 2.58, 1.32),
            0.11,
            0.10,
            materials["red_lamp"],
            collection,
            rotation=(math.radians(90.0), 0.0, 0.0),
            vertices=10,
            bevel=0.014,
        ))

    # Decorative green fenders stay static while wheels rotate independently.
    for side, x in (("L", -1.55), ("R", 1.55)):
        parts += [
            add_cube(f"FrontFender_{side}", (x, -1.62, 1.22), (0.34, 1.42, 0.16), materials["green"], collection, 0.055),
            add_cube(f"RearFender_{side}", (x, 1.52, 1.22), (0.34, 1.42, 0.16), materials["green"], collection, 0.055),
        ]

    for part in parts:
        part.parent = root
    return parts


# -----------------------------------------------------------------------------
# STATIC ATTACHMENT VALIDATION
# -----------------------------------------------------------------------------


def get_mesh_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "MESH":
        raise RuntimeError(f"Missing expected mesh before static merge: {name}")
    return obj


def object_world_bbox(obj):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def object_aabb_distance(obj_a, obj_b):
    a_min, a_max = object_world_bbox(obj_a)
    b_min, b_max = object_world_bbox(obj_b)
    dx = max(0.0, b_min.x - a_max.x, a_min.x - b_max.x)
    dy = max(0.0, b_min.y - a_max.y, a_min.y - b_max.y)
    dz = max(0.0, b_min.z - a_max.z, a_min.z - b_max.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def validate_lamp_attachments_before_merge():
    pairs = [
        ("Front_HeadlampPod_L", "Front_Nose", 0.005),
        ("Front_HeadlampPod_R", "Front_Nose", 0.005),
        ("Front_Headlamp_L", "Front_HeadlampPod_L", 0.005),
        ("Front_Headlamp_R", "Front_HeadlampPod_R", 0.005),
        ("Rear_LampTower_L", "Kitchen_RearBumper", 0.005),
        ("Rear_LampTower_R", "Kitchen_RearBumper", 0.005),
        ("Rear_Lamp_L", "Rear_LampTower_L", 0.005),
        ("Rear_Lamp_R", "Rear_LampTower_R", 0.005),
    ]
    failures = []
    for first_name, second_name, allowed_gap in pairs:
        first = get_mesh_object(first_name)
        second = get_mesh_object(second_name)
        distance = object_aabb_distance(first, second)
        if distance > allowed_gap:
            failures.append(
                f"{first_name} -> {second_name}: gap {distance:.4f} m > allowed {allowed_gap:.4f} m"
            )
    if failures:
        raise RuntimeError("LAMP ATTACHMENT AUDIT FAILED:\n- " + "\n- ".join(failures))
    print(f"[VALID] Lamp attachment audit passed: {len(pairs)} checks.")


# -----------------------------------------------------------------------------
# ROOT / MARKERS / VALIDATION
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.42)
    root["asset_type"] = "DrivableVehicle"
    root["vehicle_category"] = "FieldKitchen"
    root["role_owner"] = "Chef"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["steering_node"] = "SteeringWheel"
    root["wheel_nodes"] = "Wheel_FL,Wheel_FR,Wheel_RL,Wheel_RR"
    root["driver_seat_node"] = "DriverSeatPoint"
    root["kitchen_interaction_node"] = "KitchenInteractionPoint"
    root["has_roof"] = False
    root["has_canopy"] = False
    root["contains_knife"] = False
    root["revision"] = SCRIPT_REVISION
    return root



def create_runtime_markers(root, collection):
    driver_seat = create_empty(
        "DriverSeatPoint",
        DRIVER_SEAT_LOCATION,
        collection,
        parent=root,
        display_type="CUBE",
        size=0.18,
    )
    driver_seat["interaction_role"] = "DriverSeat"
    driver_seat["forward_axis"] = "-Y"

    driver_entry = create_empty(
        "DriverEntryPoint",
        DRIVER_ENTRY_LOCATION,
        collection,
        parent=root,
        display_type="ARROWS",
        size=0.22,
    )
    driver_entry["interaction_role"] = "VehicleEntry"

    kitchen_interaction = create_empty(
        "KitchenInteractionPoint",
        KITCHEN_INTERACTION_LOCATION,
        collection,
        parent=root,
        display_type="CUBE",
        size=0.22,
    )
    kitchen_interaction["interaction_role"] = "FieldKitchenWorkstation"
    kitchen_interaction["forward_axis"] = "-Y"
    return driver_seat, driver_entry, kitchen_interaction



def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)



def get_meshes_under_root(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]



def world_bbox(objects):
    points = []
    bpy.context.view_layer.update()
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("No mesh points available for bounds calculation.")
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high



def validate_before_export(root, steering, wheels, markers):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Vehicle root must remain an Empty at world origin.")

    required_children = {
        STATIC_NAME,
        "SteeringWheel",
        "Wheel_FL",
        "Wheel_FR",
        "Wheel_RL",
        "Wheel_RR",
        "DriverSeatPoint",
        "DriverEntryPoint",
        "KitchenInteractionPoint",
    }
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required vehicle nodes: " + ", ".join(missing))

    if steering.parent != root:
        raise RuntimeError("SteeringWheel must be a direct child of the vehicle root.")
    for wheel in wheels:
        if wheel.parent != root:
            raise RuntimeError(f"{wheel.name} must be a direct child of the vehicle root.")
        wheel_meshes = [child for child in wheel.children if child.type == "MESH"]
        if len(wheel_meshes) != 1:
            raise RuntimeError(f"{wheel.name} must contain exactly one merged wheel mesh.")

    for marker in markers:
        if marker.parent != root:
            raise RuntimeError(f"Marker hierarchy invalid: {marker.name}")

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("Cameras/lights must not remain in export scene: " + ", ".join(forbidden))

    knife_like = [obj.name for obj in bpy.context.scene.objects if "knife" in obj.name.lower() or "blade" in obj.name.lower()]
    if knife_like:
        raise RuntimeError("Knife/blade geometry is forbidden: " + ", ".join(knife_like))

    meshes = get_meshes_under_root(root)
    low, high = world_bbox(meshes)
    dimensions = high - low
    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
        f"  Mesh objects: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Separate steering node: {steering.name}\n"
        f"  Separate wheel nodes: {', '.join(w.name for w in wheels)}\n"
        f"  Roof/canopy: NONE\n"
        f"  Cutting board: present; knife: absent\n"
        f"  Soup pot: present\n"
        f"  Storage cabinet: present\n"
    )


# -----------------------------------------------------------------------------
# BUILD / EXPORT
# -----------------------------------------------------------------------------


def build_vehicle():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)

    static_parts = build_static_body(materials, collection, root)
    validate_lamp_attachments_before_merge()
    static_mesh = join_meshes(static_parts, STATIC_NAME, root) if MERGE_STATIC_MESHES else None

    steering = build_steering_wheel(materials, collection, root)
    wheels = [
        build_wheel(name, location, materials, collection, root)
        for name, location in WHEEL_SPECS.items()
    ]
    markers = create_runtime_markers(root, collection)

    if static_mesh is None:
        raise RuntimeError("This asset requires MERGE_STATIC_MESHES=True.")

    validate_before_export(root, steering, wheels, markers)
    return root



def select_hierarchy(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root



def export_assets(root):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    select_hierarchy(root)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
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
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print("[EXPORT] GLB=" + OUTPUT_GLB)
    print("[EXPORT] BLEND=" + OUTPUT_BLEND)



def main():
    print(f"\n=== Generating Chef Field Kitchen Vehicle [{SCRIPT_REVISION}] ===\n")
    root = build_vehicle()
    export_assets(root)
    print("\n=== Finished ===")
    print("Godot animation nodes:")
    print(" - SteeringWheel: rotate around local Z.")
    print(" - Wheel_FL / Wheel_FR / Wheel_RL / Wheel_RR: rotate around local X.")
    print("Interaction markers:")
    print(" - DriverSeatPoint")
    print(" - DriverEntryPoint")
    print(" - KitchenInteractionPoint")


if __name__ == "__main__":
    main()
