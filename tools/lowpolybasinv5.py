# Blender 4.x / 5.x
# Procedural 400m x 400m low-poly basin terrain for Godot.
# V5: two side rivers + two asymmetric lakes, rounded 15m central plateau,
# and a gentler climbable slope around the plateau.
# WARNING: This deletes all objects in the currently opened Blender scene.

import bpy
import math
import os

# =============================================================================
# USER SETTINGS
# =============================================================================

# --- Map scale / density ------------------------------------------------------
MAP_SIZE = 400.0
GRID_STEP = 2.0
EDGE_HEIGHT = 26.0
EDGE_SLOPE_START = 150.0

# --- Central plateau ----------------------------------------------------------
# Rounded-square / squircle plateau footprint, about 100m x 100m on top.
CENTRAL_PLATEAU_HALF_EXTENT_X = 50.0
CENTRAL_PLATEAU_HALF_EXTENT_Z = 50.0
CENTRAL_PLATEAU_SHAPE_EXPONENT = 4.0
CENTRAL_PLATEAU_HEIGHT = 15.0           # Requested new height.
PLATEAU_SLOPE_WIDTH = 42.0              # Gentler, wider climbable ramp.

# --- River / lake / shallow settings -----------------------------------------
RIVER_WATER_LEVEL = -0.95
RIVER_CENTER_DEPTH = 2.55
RIVER_EDGE_DEPTH = 0.05
MIN_RIVER_WATER_WIDTH = 8.0

SHALLOW_BANK_WIDTH = 9.0
SHALLOW_BANK_HEIGHT_ABOVE_WATER = 0.20
SHALLOW_BANK_TRANSITION = 7.0
PADDY_EDGE_LIMIT = 170.0
PADDY_EDGE_FADE = 18.0

# --- Water mesh ---------------------------------------------------------------
WATER_SURFACE_OFFSET = 0.035
WATER_GRID_STEP = 2.0
WATER_UV_METERS_PER_TILE = 8.0

# --- Output -------------------------------------------------------------------
try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = bpy.path.abspath("//") if bpy.data.filepath else os.getcwd()

EXPORT_GLB = True
GLB_OUTPUT_PATH = os.path.join(SCRIPT_DIR, "lowpoly_basin_400m_v5_lakes_plateau15.glb")
SAVE_BLEND = True
BLEND_OUTPUT_PATH = os.path.join(SCRIPT_DIR, "lowpoly_basin_400m_v5_lakes_plateau15.blend")

# =============================================================================
# HELPERS
# =============================================================================

def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / max(edge1 - edge0, 0.00001), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def point_segment_distance(px, pz, ax, az, bx, bz):
    abx = bx - ax
    abz = bz - az
    apx = px - ax
    apz = pz - az
    denom = abx * abx + abz * abz

    if denom <= 1e-8:
        return math.hypot(px - ax, pz - az)

    t = clamp((apx * abx + apz * abz) / denom, 0.0, 1.0)
    qx = ax + abx * t
    qz = az + abz * t
    return math.hypot(px - qx, pz - qz)


def polyline_distance(x, z, points, closed=False):
    if len(points) < 2:
        return 999999.0

    result = 999999.0
    segment_count = len(points) if closed else len(points) - 1

    for i in range(segment_count):
        a = points[i]
        b = points[(i + 1) % len(points)]
        result = min(result, point_segment_distance(x, z, a[0], a[1], b[0], b[1]))

    return result


def superellipse_norm(x, z, a, b, exponent):
    nx = abs(x) / max(a, 0.00001)
    nz = abs(z) / max(b, 0.00001)
    return (nx ** exponent + nz ** exponent) ** (1.0 / exponent)


def ellipse_local_coords(x, z, cx, cz, rotation_degrees):
    angle = math.radians(rotation_degrees)
    dx = x - cx
    dz = z - cz
    c = math.cos(angle)
    s = math.sin(angle)
    # rotate point into ellipse local space
    lx =  dx * c + dz * s
    lz = -dx * s + dz * c
    return lx, lz


def ellipse_norm(x, z, cx, cz, radius_x, radius_z, rotation_degrees=0.0):
    lx, lz = ellipse_local_coords(x, z, cx, cz, rotation_degrees)
    return math.sqrt((lx / max(radius_x, 0.00001)) ** 2 + (lz / max(radius_z, 0.00001)) ** 2)


# =============================================================================
# WATER LAYOUT (XZ coordinates)
# =============================================================================
# V5 goals:
# - keep the map open and readable;
# - retain the left/right main river corridors;
# - replace the two horizontal tributaries with two lakes;
# - lakes should not be perfectly top/bottom symmetric.

LEFT_RIVER = [
    (-188.0, 188.0),
    (-176.0, 160.0),
    (-164.0, 130.0),
    (-154.0, 98.0),
    (-148.0, 64.0),
    (-146.0, 28.0),
    (-148.0, 0.0),
    (-146.0, -28.0),
    (-148.0, -64.0),
    (-154.0, -98.0),
    (-164.0, -130.0),
    (-176.0, -160.0),
    (-188.0, -188.0),
]

RIGHT_RIVER = [(-x, z) for (x, z) in LEFT_RIVER]

# Lakes are defined as rotated ellipses.
# Upper lake: slightly left of center and broader.
# Lower lake: slightly right of center, smaller and rotated differently.
LAKES = [
    {
        "name": "UpperLake",
        "center": (-42.0, 112.0),
        "radius_x": 28.0,
        "radius_z": 20.0,
        "rotation_degrees": -18.0,
    },
    {
        "name": "LowerLake",
        "center": (54.0, -122.0),
        "radius_x": 22.0,
        "radius_z": 16.0,
        "rotation_degrees": 26.0,
    },
]

RIVER_PATHS = [
    ("LeftRiver", LEFT_RIVER, 14.0, False),
    ("RightRiver", RIGHT_RIVER, 14.0, False),
]


# =============================================================================
# WATER MASKS / TERRAIN CARVING
# =============================================================================

def water_half_width(water_width):
    return max(water_width, MIN_RIVER_WATER_WIDTH) * 0.5


def river_coverage(x, z):
    coverage = 0.0
    for _, points, water_width, closed in RIVER_PATHS:
        half_width = water_half_width(water_width)
        distance = polyline_distance(x, z, points, closed)
        coverage = max(coverage, 1.0 - distance / max(half_width, 0.001))
    return clamp(coverage, 0.0, 1.0)


def lake_coverage(x, z):
    coverage = 0.0
    for lake in LAKES:
        norm = ellipse_norm(
            x,
            z,
            lake["center"][0],
            lake["center"][1],
            lake["radius_x"],
            lake["radius_z"],
            lake["rotation_degrees"],
        )
        coverage = max(coverage, 1.0 - norm)
    return clamp(coverage, 0.0, 1.0)


def water_coverage(x, z):
    return max(river_coverage(x, z), lake_coverage(x, z))


def river_channel_mask(x, z):
    return smoothstep(0.0, 0.12, water_coverage(x, z))


def paddy_shallow_mask(x, z):
    max_axis = max(abs(x), abs(z))
    interior_allow = 1.0 - smoothstep(
        PADDY_EDGE_LIMIT,
        PADDY_EDGE_LIMIT + PADDY_EDGE_FADE,
        max_axis,
    )

    value = 0.0

    # River shelves
    for _, points, water_width, closed in RIVER_PATHS:
        half_width = water_half_width(water_width)
        distance = polyline_distance(x, z, points, closed)
        shelf_inner = half_width
        shelf_outer = half_width + SHALLOW_BANK_WIDTH

        enters_shelf = smoothstep(shelf_inner - 0.25, shelf_inner + 1.0, distance)
        exits_shelf = 1.0 - smoothstep(shelf_outer - 1.0, shelf_outer + 1.0, distance)
        value = max(value, enters_shelf * exits_shelf * interior_allow)

    # Lake shelves
    for lake in LAKES:
        inner_norm = ellipse_norm(
            x, z,
            lake["center"][0], lake["center"][1],
            lake["radius_x"], lake["radius_z"], lake["rotation_degrees"]
        )
        outer_norm = ellipse_norm(
            x, z,
            lake["center"][0], lake["center"][1],
            lake["radius_x"] + SHALLOW_BANK_WIDTH,
            lake["radius_z"] + SHALLOW_BANK_WIDTH,
            lake["rotation_degrees"]
        )
        # 1.0 is the exact shoreline ellipse.
        enters = smoothstep(0.96, 1.03, inner_norm)
        exits = 1.0 - smoothstep(0.96, 1.03, outer_norm)
        value = max(value, enters * exits * interior_allow)

    return value


def apply_river_and_shallow_banks(land_height, x, z):
    result = land_height

    # Rivers
    for _, points, water_width, closed in RIVER_PATHS:
        distance = polyline_distance(x, z, points, closed)
        half_width = water_half_width(water_width)
        shelf_end = half_width + SHALLOW_BANK_WIDTH
        transition_end = shelf_end + SHALLOW_BANK_TRANSITION

        if distance <= half_width:
            t = smoothstep(0.0, half_width, distance)
            target = lerp(
                RIVER_WATER_LEVEL - RIVER_CENTER_DEPTH,
                RIVER_WATER_LEVEL - RIVER_EDGE_DEPTH,
                t,
            )
            result = min(result, target)

        elif distance <= shelf_end:
            t = smoothstep(half_width, shelf_end, distance)
            target = lerp(
                RIVER_WATER_LEVEL - RIVER_EDGE_DEPTH,
                RIVER_WATER_LEVEL + SHALLOW_BANK_HEIGHT_ABOVE_WATER,
                t,
            )
            result = min(result, target)

        elif distance <= transition_end:
            t = smoothstep(shelf_end, transition_end, distance)
            target = lerp(
                RIVER_WATER_LEVEL + SHALLOW_BANK_HEIGHT_ABOVE_WATER,
                land_height,
                t,
            )
            result = min(result, target)

    # Lakes
    for lake in LAKES:
        inner_norm = ellipse_norm(
            x, z,
            lake["center"][0], lake["center"][1],
            lake["radius_x"], lake["radius_z"], lake["rotation_degrees"]
        )
        shelf_norm = ellipse_norm(
            x, z,
            lake["center"][0], lake["center"][1],
            lake["radius_x"] + SHALLOW_BANK_WIDTH,
            lake["radius_z"] + SHALLOW_BANK_WIDTH,
            lake["rotation_degrees"]
        )
        transition_norm = ellipse_norm(
            x, z,
            lake["center"][0], lake["center"][1],
            lake["radius_x"] + SHALLOW_BANK_WIDTH + SHALLOW_BANK_TRANSITION,
            lake["radius_z"] + SHALLOW_BANK_WIDTH + SHALLOW_BANK_TRANSITION,
            lake["rotation_degrees"]
        )

        if inner_norm <= 1.0:
            t = clamp(inner_norm, 0.0, 1.0)
            target = lerp(
                RIVER_WATER_LEVEL - (RIVER_CENTER_DEPTH - 0.20),
                RIVER_WATER_LEVEL - RIVER_EDGE_DEPTH,
                t,
            )
            result = min(result, target)
        elif shelf_norm <= 1.0:
            t = clamp((inner_norm - 1.0) / max(shelf_norm - 1.0, 0.00001), 0.0, 1.0)
            target = lerp(
                RIVER_WATER_LEVEL - RIVER_EDGE_DEPTH,
                RIVER_WATER_LEVEL + SHALLOW_BANK_HEIGHT_ABOVE_WATER,
                t,
            )
            result = min(result, target)
        elif transition_norm <= 1.0:
            t = clamp((shelf_norm - 1.0) / max(transition_norm - 1.0, 0.00001), 0.0, 1.0)
            target = lerp(
                RIVER_WATER_LEVEL + SHALLOW_BANK_HEIGHT_ABOVE_WATER,
                land_height,
                t,
            )
            result = min(result, target)

    return result


# =============================================================================
# HEIGHT FUNCTION
# =============================================================================

def terrain_height(x, z):
    half_map = MAP_SIZE * 0.5
    ax = abs(x)
    az = abs(z)
    max_axis = max(ax, az)

    floor_noise = (
        math.sin(x * 0.050) * 0.16
        + math.cos(z * 0.045) * 0.14
        + math.sin((x + z) * 0.023) * 0.10
    )

    edge_t = smoothstep(EDGE_SLOPE_START, half_map, max_axis)
    edge_height = EDGE_HEIGHT * (edge_t ** 1.36)
    corner_factor = (ax / half_map) * (az / half_map)
    corner_lift = 6.5 * (corner_factor ** 1.9) * edge_t
    base_land = floor_noise + edge_height + corner_lift

    plateau_norm = superellipse_norm(
        x,
        z,
        CENTRAL_PLATEAU_HALF_EXTENT_X,
        CENTRAL_PLATEAU_HALF_EXTENT_Z,
        CENTRAL_PLATEAU_SHAPE_EXPONENT,
    )

    slope_outer_norm = superellipse_norm(
        CENTRAL_PLATEAU_HALF_EXTENT_X + PLATEAU_SLOPE_WIDTH,
        0.0,
        CENTRAL_PLATEAU_HALF_EXTENT_X,
        CENTRAL_PLATEAU_HALF_EXTENT_Z,
        CENTRAL_PLATEAU_SHAPE_EXPONENT,
    )

    slope_t = smoothstep(1.0, slope_outer_norm, plateau_norm)
    plateau_influence = 1.0 - slope_t

    base_land *= 1.0 - plateau_influence * 0.86
    land_height = lerp(base_land, CENTRAL_PLATEAU_HEIGHT, plateau_influence)

    if plateau_norm <= 1.0:
        land_height = CENTRAL_PLATEAU_HEIGHT
        return land_height

    return apply_river_and_shallow_banks(land_height, x, z)


# =============================================================================
# MATERIALS
# =============================================================================

def make_principled_material(name, base_color, roughness=0.8, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = base_color

    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic

    return material


M_GRASS = None
M_RIVERBED = None
M_ROCK = None
M_PADDY_SHALLOW = None
M_WATER_GUIDE = None


def create_materials():
    global M_GRASS, M_RIVERBED, M_ROCK, M_PADDY_SHALLOW, M_WATER_GUIDE

    M_GRASS = make_principled_material(
        "M_Grass", (0.19, 0.42, 0.105, 1.0), roughness=0.92
    )
    M_RIVERBED = make_principled_material(
        "M_Riverbed_Soil", (0.16, 0.105, 0.055, 1.0), roughness=1.0
    )
    M_ROCK = make_principled_material(
        "M_Boundary_Rock", (0.22, 0.21, 0.18, 1.0), roughness=0.95
    )
    M_PADDY_SHALLOW = make_principled_material(
        "M_Paddy_Shallow", (0.31, 0.235, 0.090, 1.0), roughness=0.96
    )
    M_WATER_GUIDE = make_principled_material(
        "M_WaterGuide", (0.025, 0.29, 0.54, 1.0), roughness=0.18
    )

    bsdf = M_WATER_GUIDE.node_tree.nodes.get("Principled BSDF")
    if bsdf and "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.62


# =============================================================================
# MESH CREATION
# =============================================================================

def build_terrain_mesh(collection):
    half_map = MAP_SIZE * 0.5
    segment_count = int(round(MAP_SIZE / GRID_STEP))

    vertices = []
    channel_values = []
    paddy_values = []
    heights = []

    for iz in range(segment_count + 1):
        z = -half_map + iz * GRID_STEP
        for ix in range(segment_count + 1):
            x = -half_map + ix * GRID_STEP
            height = terrain_height(x, z)
            vertices.append((x, height, z))
            heights.append(height)
            channel_values.append(river_channel_mask(x, z))
            paddy_values.append(paddy_shallow_mask(x, z))

    faces = []
    face_materials = []

    for iz in range(segment_count):
        for ix in range(segment_count):
            a = iz * (segment_count + 1) + ix
            b = a + 1
            c = a + (segment_count + 1)
            d = c + 1

            if (ix + iz) % 2 == 0:
                triangles = [(a, c, b), (b, c, d)]
            else:
                triangles = [(a, c, d), (a, d, b)]

            average_channel = (
                channel_values[a] + channel_values[b] + channel_values[c] + channel_values[d]
            ) * 0.25
            average_paddy = (
                paddy_values[a] + paddy_values[b] + paddy_values[c] + paddy_values[d]
            ) * 0.25
            average_height = (heights[a] + heights[b] + heights[c] + heights[d]) * 0.25

            if average_channel > 0.45:
                material_index = 1
            elif average_paddy > 0.30:
                material_index = 3
            elif average_height > EDGE_HEIGHT * 0.52:
                material_index = 2
            else:
                material_index = 0

            for triangle in triangles:
                faces.append(triangle)
                face_materials.append(material_index)

    mesh = bpy.data.meshes.new("Terrain_Basin_400m_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)

    mesh.materials.append(M_GRASS)
    mesh.materials.append(M_RIVERBED)
    mesh.materials.append(M_ROCK)
    mesh.materials.append(M_PADDY_SHALLOW)

    for polygon, material_index in zip(mesh.polygons, face_materials):
        polygon.use_smooth = False
        polygon.material_index = material_index

    terrain_object = bpy.data.objects.new("Terrain_Basin_400m", mesh)
    collection.objects.link(terrain_object)
    return terrain_object, segment_count


def build_boundary_skirt(collection, segment_count):
    half_map = MAP_SIZE * 0.5
    bottom_y = -20.0
    top_ring = []

    for ix in range(segment_count):
        top_ring.append((-half_map + ix * GRID_STEP, -half_map))
    for iz in range(segment_count):
        top_ring.append((half_map, -half_map + iz * GRID_STEP))
    for ix in range(segment_count, 0, -1):
        top_ring.append((-half_map + ix * GRID_STEP, half_map))
    for iz in range(segment_count, 0, -1):
        top_ring.append((-half_map, -half_map + iz * GRID_STEP))

    vertices = [(x, terrain_height(x, z), z) for x, z in top_ring]
    vertices.extend((x, bottom_y, z) for x, z in top_ring)

    count = len(top_ring)
    faces = []
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))

    mesh = bpy.data.meshes.new("Terrain_Boundary_Skirt_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    mesh.materials.append(M_ROCK)

    for polygon in mesh.polygons:
        polygon.use_smooth = False
        polygon.material_index = 0

    boundary_object = bpy.data.objects.new("Terrain_Boundary_Skirt", mesh)
    collection.objects.link(boundary_object)
    return boundary_object


def apply_uvs_from_vertex_uvs(mesh, vertex_uvs):
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            uv_layer.data[loop_index].uv = vertex_uvs[vertex_index]


def build_unified_water_surface(collection):
    half_map = MAP_SIZE * 0.5
    segment_count = int(round(MAP_SIZE / WATER_GRID_STEP))
    water_y = RIVER_WATER_LEVEL + WATER_SURFACE_OFFSET

    vertices = []
    vertex_uvs = []
    faces = []
    vertex_lookup = {}

    def get_vertex(ix, iz):
        key = (ix, iz)
        existing = vertex_lookup.get(key)
        if existing is not None:
            return existing

        x = -half_map + ix * WATER_GRID_STEP
        z = -half_map + iz * WATER_GRID_STEP
        index = len(vertices)
        vertex_lookup[key] = index
        vertices.append((x, water_y, z))

        u = (x + half_map) / WATER_UV_METERS_PER_TILE
        v = water_coverage(x, z) * 0.5
        vertex_uvs.append((u, v))
        return index

    for iz in range(segment_count):
        z_center = -half_map + (iz + 0.5) * WATER_GRID_STEP
        for ix in range(segment_count):
            x_center = -half_map + (ix + 0.5) * WATER_GRID_STEP

            if water_coverage(x_center, z_center) <= 0.0:
                continue

            a = get_vertex(ix, iz)
            b = get_vertex(ix + 1, iz)
            c = get_vertex(ix, iz + 1)
            d = get_vertex(ix + 1, iz + 1)

            faces.append((a, c, b))
            faces.append((b, c, d))

    if not faces:
        raise RuntimeError("Unified water mesh has no faces. Check river/lake layout.")

    mesh = bpy.data.meshes.new("WaterGuide_AllRivers_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.validate(verbose=False)
    apply_uvs_from_vertex_uvs(mesh, vertex_uvs)
    mesh.materials.append(M_WATER_GUIDE)

    for polygon in mesh.polygons:
        polygon.use_smooth = False
        polygon.material_index = 0

    water_object = bpy.data.objects.new("WaterGuide_AllRivers", mesh)
    water_object["godot_role"] = "river_water"
    water_object["water_level"] = RIVER_WATER_LEVEL
    water_object["water_mesh_type"] = "single_union_mesh_no_z_fighting"
    collection.objects.link(water_object)
    return water_object


def add_map_metadata(collection):
    north_spawn = (0.0, 162.0)
    south_spawn = (0.0, -162.0)
    markers = [
        ("Marker_CentralPlateau", (0.0, CENTRAL_PLATEAU_HEIGHT, 0.0)),
        ("Marker_MapCenter", (0.0, terrain_height(0.0, 0.0), 0.0)),
        ("Marker_NorthSpawn", (north_spawn[0], terrain_height(*north_spawn) + 0.15, north_spawn[1])),
        ("Marker_SouthSpawn", (south_spawn[0], terrain_height(*south_spawn) + 0.15, south_spawn[1])),
        ("Marker_RiverWaterLevel", (0.0, RIVER_WATER_LEVEL, 0.0)),
    ]

    for name, location in markers:
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = 'ARROWS'
        empty.empty_display_size = 4.0
        empty.location = location
        collection.objects.link(empty)


# =============================================================================
# SCENE SETUP / EXPORT
# =============================================================================

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)


def prepare_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.length_unit = 'METERS'
    scene.unit_settings.scale_length = 1.0

    if scene.world:
        scene.world.color = (0.05, 0.05, 0.05)


def export_selected_glb(collection, active_object):
    bpy.ops.object.select_all(action='DESELECT')
    for object_3d in collection.all_objects:
        object_3d.select_set(True)

    bpy.context.view_layer.objects.active = active_object
    filepath = bpy.path.abspath(GLB_OUTPUT_PATH)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"GLB exported: {filepath}")


def main():
    if abs((MAP_SIZE / GRID_STEP) - round(MAP_SIZE / GRID_STEP)) > 1e-6:
        raise ValueError("MAP_SIZE must be divisible by GRID_STEP.")
    if abs((MAP_SIZE / WATER_GRID_STEP) - round(MAP_SIZE / WATER_GRID_STEP)) > 1e-6:
        raise ValueError("MAP_SIZE must be divisible by WATER_GRID_STEP.")

    clear_scene()
    prepare_scene()
    create_materials()

    old_collection = bpy.data.collections.get("LowPolyFarmBasin")
    if old_collection:
        bpy.data.collections.remove(old_collection, do_unlink=True)

    collection = bpy.data.collections.new("LowPolyFarmBasin")
    bpy.context.scene.collection.children.link(collection)

    terrain_object, segment_count = build_terrain_mesh(collection)
    build_boundary_skirt(collection, segment_count)
    build_unified_water_surface(collection)
    add_map_metadata(collection)

    bpy.ops.object.select_all(action='DESELECT')
    terrain_object.select_set(True)
    bpy.context.view_layer.objects.active = terrain_object

    if SAVE_BLEND:
        blend_path = bpy.path.abspath(BLEND_OUTPUT_PATH)
        os.makedirs(os.path.dirname(blend_path), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
        print(f"Blend saved: {blend_path}")

    if EXPORT_GLB:
        export_selected_glb(collection, terrain_object)

    print("Done: created 400m basin terrain with two side rivers, two asymmetric lakes, a rounded 15m plateau, and a gentler climbable slope.")


main()
