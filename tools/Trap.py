# Blender 4.4+ / 5.x
# -----------------------------------------------------------------------------
# Food War / Farm Town - Hinged Leg Clamp Trap (Green) [REV5]
#
# Correct mechanical layout:
# - A permanent 4 m x 4 m outer square frame.
# - Two hollow semi-circular spiked jaws lie flat inside the frame.
# - Each semi-circle is closed by its own straight diameter bar.
# - Each diameter bar contains its own Y-axis axle near the center of the trap.
# - The two axles are parallel and separated in X, so they never overlap.
# - Left jaw rotates +Y and right jaw rotates -Y to rise and clamp inward.
#
# Export hierarchy:
#   FTF_Trap_LegClamp_Green_v5
#   |-- FTF_Trap_LegClamp_Green_v5_BaseStatic
#   |-- Jaw_Left
#   |   `-- Jaw_Left_Mesh
#   |-- Jaw_Right
#   |   `-- Jaw_Right_Mesh
#   `-- TrapBounds
# -----------------------------------------------------------------------------

import bpy
import math
import os
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "generated_farmtown_traps")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "FTF_Trap_LegClamp_Green_v5.glb")

ROOT_NAME = "FTF_Trap_LegClamp_Green_v5"
BASE_STATIC_NAME = ROOT_NAME + "_BaseStatic"
LEFT_PIVOT_NAME = "Jaw_Left"
RIGHT_PIVOT_NAME = "Jaw_Right"
LEFT_MESH_NAME = "Jaw_Left_Mesh"
RIGHT_MESH_NAME = "Jaw_Right_Mesh"
COLLECTION_NAME = "COL_" + ROOT_NAME
SCRIPT_REVISION = "REV5_CONTINUOUS_ARC_SEPARATE_CENTER_AXLES"

CLEAR_SCENE = True
AUTHORING_FORWARD_AXIS = "-Y"
INTENDED_GODOT_FORWARD_AXIS = "-Z"

FRAME_SIZE = 4.0
FRAME_RAIL_WIDTH = 0.24
AXLE_OFFSET_X = 0.16
AXLE_RADIUS = 0.050
AXLE_CLEARANCE_MIN = 0.08
JAW_RADIUS = 1.25
ARC_TUBE_RADIUS = 0.085
ARC_Z = 0.24
ARC_SEGMENT_COUNT = 12
DIAMETER_BAR_WIDTH = 0.15
DIAMETER_BAR_HEIGHT = 0.15
CLOSED_ANGLE_DEG = 72.0
TRAP_BOUNDS_CENTER = Vector((0.0, 0.0, 0.45))


# -----------------------------------------------------------------------------
# Scene and materials
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


def make_material(name, color, metallic=0.0, roughness=0.6, emission=None, emission_strength=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = (*color, 1.0)
    return material


def build_materials():
    return {
        "green": make_material("MAT_LC5_Green", (0.22, 0.42, 0.23), metallic=0.68, roughness=0.34),
        "green_dark": make_material("MAT_LC5_GreenDark", (0.13, 0.25, 0.14), metallic=0.62, roughness=0.42),
        "green_light": make_material("MAT_LC5_GreenLight", (0.32, 0.53, 0.29), metallic=0.50, roughness=0.36),
        "steel": make_material("MAT_LC5_Steel", (0.58, 0.61, 0.63), metallic=0.82, roughness=0.23),
        "dark": make_material("MAT_LC5_Dark", (0.07, 0.08, 0.09), metallic=0.28, roughness=0.72),
        "amber": make_material(
            "MAT_LC5_Amber",
            (0.83, 0.67, 0.18),
            metallic=0.08,
            roughness=0.32,
            emission=(0.88, 0.61, 0.13),
            emission_strength=1.0,
        ),
    }


# -----------------------------------------------------------------------------
# Object helpers
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


def assign_material(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def set_flat_shading(obj):
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = False


def add_bevel(obj, width=0.01, segments=1):
    modifier = obj.modifiers.new("Bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    return modifier


def finish_mesh(obj, name, material, collection, bevel=0.0):
    obj.name = name
    assign_material(obj, material)
    set_flat_shading(obj)
    if bevel > 0.0:
        add_bevel(obj, bevel)
    move_to_collection(obj, collection)
    return obj


def add_cube(name, location, dimensions, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, name, material, collection, bevel)


def add_cylinder(name, location, radius, depth, material, collection, rotation=(0.0, 0.0, 0.0), vertices=14, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    return finish_mesh(bpy.context.object, name, material, collection, bevel)


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


def add_pyramid_spike(name, location, base_size, height, material, collection):
    bpy.ops.mesh.primitive_cone_add(
        vertices=4,
        radius1=base_size * 0.5,
        radius2=0.0,
        depth=height,
        location=(location[0], location[1], location[2] + height * 0.5),
        rotation=(0.0, 0.0, math.radians(45.0)),
    )
    return finish_mesh(bpy.context.object, name, material, collection, bevel=0.003)


def create_empty(name, location, collection, parent=None, display_type="PLAIN_AXES", size=0.18):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    collection.objects.link(obj)
    return obj


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


def join_meshes(meshes, new_name, parent):
    if not meshes:
        raise RuntimeError(f"No meshes to join for {new_name}")
    for obj in meshes:
        apply_transforms_and_modifiers(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = new_name
    merged.parent = parent
    set_flat_shading(merged)
    return merged


# -----------------------------------------------------------------------------
# Base construction
# -----------------------------------------------------------------------------


def build_base(materials, collection, root):
    parts = []
    half = FRAME_SIZE * 0.5
    rail_center = half - FRAME_RAIL_WIDTH * 0.5

    # Permanent hollow outer square frame.
    parts.extend([
        add_cube("Base_Frame_N", (0.0, -rail_center, 0.12), (FRAME_SIZE, FRAME_RAIL_WIDTH, 0.18), materials["green"], collection, bevel=0.016),
        add_cube("Base_Frame_S", (0.0, rail_center, 0.12), (FRAME_SIZE, FRAME_RAIL_WIDTH, 0.18), materials["green"], collection, bevel=0.016),
        add_cube("Base_Frame_W", (-rail_center, 0.0, 0.12), (FRAME_RAIL_WIDTH, FRAME_SIZE, 0.18), materials["green"], collection, bevel=0.016),
        add_cube("Base_Frame_E", (rail_center, 0.0, 0.12), (FRAME_RAIL_WIDTH, FRAME_SIZE, 0.18), materials["green"], collection, bevel=0.016),
    ])

    # Two transverse rails support both axle ends and connect to the outer frame.
    support_y = JAW_RADIUS + 0.14
    support_span_x = FRAME_SIZE - FRAME_RAIL_WIDTH * 2.0
    parts.extend([
        add_cube("Base_AxleRail_N", (0.0, -support_y, 0.11), (support_span_x, 0.22, 0.14), materials["green_dark"], collection, bevel=0.010),
        add_cube("Base_AxleRail_S", (0.0, support_y, 0.11), (support_span_x, 0.22, 0.14), materials["green_dark"], collection, bevel=0.010),
    ])

    # Four separate bearing blocks: two for each non-overlapping axle.
    for prefix, x in (("Left", -AXLE_OFFSET_X), ("Right", AXLE_OFFSET_X)):
        parts.extend([
            add_cube(f"Bearing_{prefix}_N", (x, -support_y, 0.20), (0.20, 0.25, 0.22), materials["green_light"], collection, bevel=0.010),
            add_cube(f"Bearing_{prefix}_S", (x, support_y, 0.20), (0.20, 0.25, 0.22), materials["green_light"], collection, bevel=0.010),
        ])

    # Small trigger plate with two narrow supports, leaving the center mostly hollow.
    parts.extend([
        add_cube("Trigger_Bridge_N", (0.0, -0.73, 0.09), (0.16, 1.12, 0.08), materials["dark"], collection, bevel=0.006),
        add_cube("Trigger_Bridge_S", (0.0, 0.73, 0.09), (0.16, 1.12, 0.08), materials["dark"], collection, bevel=0.006),
        add_cube("Trigger_Frame", (0.0, 0.0, 0.10), (0.78, 0.78, 0.07), materials["dark"], collection, bevel=0.009),
        add_cube("Trigger_Plate", (0.0, 0.0, 0.145), (0.56, 0.56, 0.04), materials["amber"], collection, bevel=0.007),
    ])

    for part in parts:
        part.parent = root
    return parts


# -----------------------------------------------------------------------------
# Jaw construction
# -----------------------------------------------------------------------------


def arc_points_for_side(side):
    """Return local-space points for one continuous semi-circle."""
    side_sign = -1.0 if side == "L" else 1.0
    points = []
    for index in range(ARC_SEGMENT_COUNT + 1):
        angle = -math.pi * 0.5 + math.pi * index / ARC_SEGMENT_COUNT
        x = side_sign * JAW_RADIUS * math.cos(angle)
        y = JAW_RADIUS * math.sin(angle)
        points.append(Vector((x, y, ARC_Z)))
    return points


def build_jaw(prefix, side, materials, collection, root):
    pivot_x = -AXLE_OFFSET_X if side == "L" else AXLE_OFFSET_X
    pivot = create_empty(prefix, (pivot_x, 0.0, 0.0), collection, parent=root, display_type="SINGLE_ARROW", size=0.22)
    pivot["rotation_axis_blender"] = "Y"
    pivot["rotation_axis_godot_expected"] = "Z"
    pivot["open_angle_deg"] = 0.0
    pivot["closed_angle_deg"] = CLOSED_ANGLE_DEG if side == "L" else -CLOSED_ANGLE_DEG

    parts = []
    points = arc_points_for_side(side)

    # Separate axle at local X=0; world X comes from the pivot position.
    axle_length = JAW_RADIUS * 2.0 + 0.28
    axle = add_cylinder(
        f"{prefix}_AxleRod",
        (0.0, 0.0, ARC_Z - 0.02),
        AXLE_RADIUS,
        axle_length,
        materials["steel"],
        collection,
        rotation=(math.radians(90.0), 0.0, 0.0),
        vertices=16,
        bevel=0.004,
    )
    axle.parent = pivot
    parts.append(axle)

    # Straight diameter bar connected to the axle and to both arc endpoints.
    diameter = add_cube(
        f"{prefix}_DiameterBar",
        (0.0, 0.0, ARC_Z),
        (DIAMETER_BAR_WIDTH, JAW_RADIUS * 2.0 + 0.08, DIAMETER_BAR_HEIGHT),
        materials["green_dark"],
        collection,
        bevel=0.010,
    )
    diameter.parent = pivot
    parts.append(diameter)

    # Continuous semi-circular rail made from endpoint-sharing cylinders.
    for index in range(ARC_SEGMENT_COUNT):
        segment = add_cylinder_between(
            f"{prefix}_Arc_{index:02d}",
            points[index],
            points[index + 1],
            ARC_TUBE_RADIUS,
            materials["green"],
            collection,
            vertices=12,
            bevel=0.003,
        )
        segment.parent = pivot
        parts.append(segment)

    # Radial braces connect the diameter to the arc at three real contact points.
    brace_indices = (2, ARC_SEGMENT_COUNT // 2, ARC_SEGMENT_COUNT - 2)
    side_sign = -1.0 if side == "L" else 1.0
    for brace_number, point_index in enumerate(brace_indices):
        target = points[point_index]
        start = Vector((side_sign * 0.03, target.y, ARC_Z))
        end = Vector((target.x - side_sign * ARC_TUBE_RADIUS * 0.35, target.y, ARC_Z))
        brace = add_cylinder_between(
            f"{prefix}_Brace_{brace_number:02d}",
            start,
            end,
            0.035,
            materials["green_light"],
            collection,
            vertices=10,
            bevel=0.002,
        )
        brace.parent = pivot
        parts.append(brace)

    # Moderate spikes placed at arc segment midpoints; each spike overlaps its arc segment.
    spike_segment_indices = (0, 2, 4, 6, 8, 10, 11)
    for spike_number, segment_index in enumerate(spike_segment_indices):
        midpoint = (points[segment_index] + points[segment_index + 1]) * 0.5
        spike = add_pyramid_spike(
            f"{prefix}_Spike_{spike_number:02d}",
            (midpoint.x, midpoint.y, ARC_Z + ARC_TUBE_RADIUS - 0.018),
            0.17,
            0.30,
            materials["steel"],
            collection,
        )
        spike.parent = pivot
        parts.append(spike)

    return pivot, parts


# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------


def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def get_meshes_under(root):
    return [obj for obj in iter_hierarchy(root) if obj.type == "MESH"]


def world_bbox(objects):
    bpy.context.view_layer.update()
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("No mesh points available for bounds calculation.")
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def get_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Missing expected object: {name}")
    return obj


def aabb_distance(obj_a, obj_b):
    a_low, a_high = world_bbox([obj_a])
    b_low, b_high = world_bbox([obj_b])
    dx = max(0.0, b_low.x - a_high.x, a_low.x - b_high.x)
    dy = max(0.0, b_low.y - a_high.y, a_low.y - b_high.y)
    dz = max(0.0, b_low.z - a_high.z, a_low.z - b_high.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def add_attachment_failure(failures, first_name, second_name, allowed_gap):
    distance = aabb_distance(get_object(first_name), get_object(second_name))
    if distance > allowed_gap:
        failures.append(
            f"{first_name} -> {second_name}: gap {distance:.4f} m > allowed {allowed_gap:.4f} m"
        )


def validate_premerge():
    failures = []

    # Outer frame is a connected square.
    for first, second in (
        ("Base_Frame_N", "Base_Frame_W"),
        ("Base_Frame_N", "Base_Frame_E"),
        ("Base_Frame_S", "Base_Frame_W"),
        ("Base_Frame_S", "Base_Frame_E"),
        ("Base_AxleRail_N", "Base_Frame_W"),
        ("Base_AxleRail_N", "Base_Frame_E"),
        ("Base_AxleRail_S", "Base_Frame_W"),
        ("Base_AxleRail_S", "Base_Frame_E"),
        ("Trigger_Frame", "Trigger_Bridge_N"),
        ("Trigger_Frame", "Trigger_Bridge_S"),
        ("Trigger_Bridge_N", "Base_AxleRail_N"),
        ("Trigger_Bridge_S", "Base_AxleRail_S"),
        ("Trigger_Plate", "Trigger_Frame"),
    ):
        add_attachment_failure(failures, first, second, 0.005)

    for side_name in ("Left", "Right"):
        add_attachment_failure(failures, f"Bearing_{side_name}_N", "Base_AxleRail_N", 0.005)
        add_attachment_failure(failures, f"Bearing_{side_name}_S", "Base_AxleRail_S", 0.005)
        jaw_prefix = LEFT_PIVOT_NAME if side_name == "Left" else RIGHT_PIVOT_NAME
        add_attachment_failure(failures, f"{jaw_prefix}_AxleRod", f"Bearing_{side_name}_N", 0.005)
        add_attachment_failure(failures, f"{jaw_prefix}_AxleRod", f"Bearing_{side_name}_S", 0.005)

    # Each jaw has one continuous semi-circle connected to its diameter and axle.
    for prefix in (LEFT_PIVOT_NAME, RIGHT_PIVOT_NAME):
        add_attachment_failure(failures, f"{prefix}_AxleRod", f"{prefix}_DiameterBar", 0.005)
        add_attachment_failure(failures, f"{prefix}_Arc_00", f"{prefix}_DiameterBar", 0.005)
        add_attachment_failure(failures, f"{prefix}_Arc_{ARC_SEGMENT_COUNT - 1:02d}", f"{prefix}_DiameterBar", 0.005)

        for index in range(ARC_SEGMENT_COUNT - 1):
            add_attachment_failure(
                failures,
                f"{prefix}_Arc_{index:02d}",
                f"{prefix}_Arc_{index + 1:02d}",
                0.005,
            )

        brace_arc_indices = (1, ARC_SEGMENT_COUNT // 2 - 1, ARC_SEGMENT_COUNT - 3)
        for brace_index, arc_index in enumerate(brace_arc_indices):
            add_attachment_failure(failures, f"{prefix}_Brace_{brace_index:02d}", f"{prefix}_DiameterBar", 0.005)
            add_attachment_failure(failures, f"{prefix}_Brace_{brace_index:02d}", f"{prefix}_Arc_{arc_index:02d}", 0.015)

        spike_arc_indices = (0, 2, 4, 6, 8, 10, 11)
        for spike_index, arc_index in enumerate(spike_arc_indices):
            add_attachment_failure(failures, f"{prefix}_Spike_{spike_index:02d}", f"{prefix}_Arc_{arc_index:02d}", 0.005)

    # Verify the two moving axle rods and diameter bars have genuine clearance.
    left_rod = get_object(f"{LEFT_PIVOT_NAME}_AxleRod")
    right_rod = get_object(f"{RIGHT_PIVOT_NAME}_AxleRod")
    rod_gap = aabb_distance(left_rod, right_rod)
    if rod_gap < AXLE_CLEARANCE_MIN:
        failures.append(
            f"Jaw axle clearance too small: {rod_gap:.4f} m < required {AXLE_CLEARANCE_MIN:.4f} m"
        )

    left_bar = get_object(f"{LEFT_PIVOT_NAME}_DiameterBar")
    right_bar = get_object(f"{RIGHT_PIVOT_NAME}_DiameterBar")
    bar_gap = aabb_distance(left_bar, right_bar)
    if bar_gap < 0.08:
        failures.append(f"Jaw diameter bars overlap or are too close: clearance {bar_gap:.4f} m")

    if failures:
        raise RuntimeError("FLOATING / CLIPPING AUDIT FAILED:\n- " + "\n- ".join(failures))

    print(
        "[VALID] Pre-merge attachment audit passed.\n"
        f"  Axle clearance: {rod_gap:.3f} m\n"
        f"  Diameter-bar clearance: {bar_gap:.3f} m"
    )


def validate_postmerge(root):
    if root.type != "EMPTY" or root.location.length > 0.0001:
        raise RuntimeError("Trap root must remain an Empty at world origin.")

    required_children = {BASE_STATIC_NAME, LEFT_PIVOT_NAME, RIGHT_PIVOT_NAME, "TrapBounds"}
    actual_children = {child.name for child in root.children}
    missing = sorted(required_children - actual_children)
    if missing:
        raise RuntimeError("Missing required export nodes: " + ", ".join(missing))

    forbidden = [obj.name for obj in bpy.context.scene.objects if obj.type in {"CAMERA", "LIGHT"}]
    if forbidden:
        raise RuntimeError("Cameras/lights must not remain in export scene: " + ", ".join(forbidden))

    collision_like = [
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and (obj.name.lower().startswith("ucx") or "collision" in obj.name.lower())
    ]
    if collision_like:
        raise RuntimeError("Collision-like meshes are not allowed: " + ", ".join(collision_like))

    left_meshes = get_meshes_under(get_object(LEFT_PIVOT_NAME))
    right_meshes = get_meshes_under(get_object(RIGHT_PIVOT_NAME))
    if len(left_meshes) != 1 or left_meshes[0].name != LEFT_MESH_NAME:
        raise RuntimeError("Expected one merged mesh under Jaw_Left.")
    if len(right_meshes) != 1 or right_meshes[0].name != RIGHT_MESH_NAME:
        raise RuntimeError("Expected one merged mesh under Jaw_Right.")

    meshes = get_meshes_under(root)
    low, high = world_bbox(meshes)
    dimensions = high - low
    if dimensions.x > 4.20 or dimensions.y > 4.20:
        raise RuntimeError(
            f"Trap footprint is too large: {dimensions.x:.3f} m x {dimensions.y:.3f} m"
        )

    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)

    print(
        f"[VALID] {ROOT_NAME}\n"
        f"  Bounds: {dimensions.x:.2f} m x {dimensions.y:.2f} m x {dimensions.z:.2f} m\n"
        f"  Mesh objects: {len(meshes)}\n"
        f"  Triangles: {triangles}\n"
        f"  Root children: {', '.join(sorted(required_children))}\n"
    )


# -----------------------------------------------------------------------------
# Root, build and export
# -----------------------------------------------------------------------------


def create_root(collection):
    root = create_empty(ROOT_NAME, (0.0, 0.0, 0.0), collection, display_type="PLAIN_AXES", size=0.30)
    root["asset_type"] = "Trap"
    root["trap_category"] = "LegClampTrap"
    root["visual_style"] = "ContinuousSemiCircularCenterAxleJaws"
    root["authoring_forward_axis"] = AUTHORING_FORWARD_AXIS
    root["intended_godot_forward_axis"] = INTENDED_GODOT_FORWARD_AXIS
    root["footprint_m"] = (4.0, 4.0)
    root["revision"] = SCRIPT_REVISION
    return root


def create_runtime_markers(root, collection):
    marker = create_empty(
        "TrapBounds",
        TRAP_BOUNDS_CENTER,
        collection,
        parent=root,
        display_type="CUBE",
        size=0.24,
    )
    marker["interaction_role"] = "LegClampAreaCenter"
    marker["recommended_box_extents_m"] = (2.0, 2.0, 0.55)
    return marker


def build_asset():
    if CLEAR_SCENE:
        clear_scene()
    configure_scene()

    collection = get_or_create_collection(COLLECTION_NAME)
    materials = build_materials()
    root = create_root(collection)

    base_parts = build_base(materials, collection, root)
    left_pivot, left_parts = build_jaw(LEFT_PIVOT_NAME, "L", materials, collection, root)
    right_pivot, right_parts = build_jaw(RIGHT_PIVOT_NAME, "R", materials, collection, root)
    create_runtime_markers(root, collection)

    # Mandatory pre-merge floating and clipping audit.
    validate_premerge()

    join_meshes(base_parts, BASE_STATIC_NAME, root)
    join_meshes(left_parts, LEFT_MESH_NAME, left_pivot)
    join_meshes(right_parts, RIGHT_MESH_NAME, right_pivot)

    validate_postmerge(root)
    return root


def select_hierarchy(root):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_asset(root):
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
    print("[EXPORT] GLB=" + OUTPUT_GLB)


def main():
    print(f"\n=== Generating Hinged Leg Clamp Trap [{SCRIPT_REVISION}] ===\n")
    root = build_asset()
    export_asset(root)
    print("\n=== Finished ===")
    print("Godot animation:")
    print(" - Open state: both jaw rotations are zero and lie flat on the ground.")
    print(" - Jaw_Left: rotate around Blender local Y by +72 degrees.")
    print(" - Jaw_Right: rotate around Blender local Y by -72 degrees.")
    print(" - After glTF import, Blender local Y is expected to correspond to Godot local Z.")


if __name__ == "__main__":
    main()
