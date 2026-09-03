import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "buildings", "RoadCheckpointWatchtower.glb")
DEFAULT_PREVIEW = os.path.join(PROJECT_ROOT, "assets", "buildings", "RoadCheckpointWatchtower_Preview.png")

BASE_WIDTH = 5.0
BASE_DEPTH = 5.0
TOTAL_HEIGHT = 9.65
BODY_BOTTOM_Z = 0.22
BODY_TOP_Z = 5.20
CABIN_BOTTOM_Z = 5.20
CABIN_TOP_Z = 8.62


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=DEFAULT_PREVIEW)
    parser.add_argument("--no-preview", action="store_true")
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(values)


def color(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index : index + 2], 16) / 255.0 for index in range(0, 8, 2))


def material(name, hex_color, roughness=0.75, metallic=0.0, emission=None, emission_strength=0.0):
    result = bpy.data.materials.new(name)
    rgba = color(hex_color)
    result.diffuse_color = rgba
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = rgba
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission is not None:
        shader.inputs["Emission Color"].default_value = color(emission)
        shader.inputs["Emission Strength"].default_value = emission_strength
    return result


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(datablocks):
            if item.users == 0:
                datablocks.remove(item)


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_cube(name, location, dimensions, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.dimensions = dimensions
    apply_scale(obj)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("StoneEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def add_cylinder(name, location, radius, depth, mat, vertices=12, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.data.materials.append(mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("BeaconEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return obj


def add_uv_sphere(name, location, dimensions, mat, segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.dimensions = dimensions
    apply_scale(obj)
    obj.data.materials.append(mat)
    return obj


def add_frustum(name, z0, z1, bottom_width, bottom_depth, top_width, top_depth, mat):
    bx = bottom_width * 0.5
    by = bottom_depth * 0.5
    tx = top_width * 0.5
    ty = top_depth * 0.5
    vertices = [
        (-bx, -by, z0), (bx, -by, z0), (bx, by, z0), (-bx, by, z0),
        (-tx, -ty, z1), (tx, -ty, z1), (tx, ty, z1), (-tx, ty, z1),
    ]
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (1, 2, 6, 5),
        (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def add_quad(name, vertices, mat):
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], [(0, 1, 2, 3)])
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def linear_width(z, z0, z1, lower, upper):
    ratio = (z - z0) / (z1 - z0)
    return lower + (upper - lower) * ratio


def add_window_side(parts, side, mats):
    glass = mats["glass"]
    # Keep the observation slit understated: one wide, shallow dark pane per face.
    # It follows the tapered wall profile and sits only 8 mm above the stone.
    z0 = 6.34
    z1 = 7.64
    lower_half = linear_width(z0, CABIN_BOTTOM_Z, CABIN_TOP_Z, 1.78, 2.24)
    upper_half = linear_width(z1, CABIN_BOTTOM_Z, CABIN_TOP_Z, 1.78, 2.24)
    offset = 0.008
    lower_width = 1.37
    upper_width = 1.56
    if side == "front":
        vertices = [(-lower_width, -lower_half - offset, z0), (lower_width, -lower_half - offset, z0), (upper_width, -upper_half - offset, z1), (-upper_width, -upper_half - offset, z1)]
    elif side == "back":
        vertices = [(lower_width, lower_half + offset, z0), (-lower_width, lower_half + offset, z0), (-upper_width, upper_half + offset, z1), (upper_width, upper_half + offset, z1)]
    elif side == "left":
        vertices = [(-lower_half - offset, lower_width, z0), (-lower_half - offset, -lower_width, z0), (-upper_half - offset, -upper_width, z1), (-upper_half - offset, upper_width, z1)]
    else:
        vertices = [(lower_half + offset, -lower_width, z0), (lower_half + offset, lower_width, z0), (upper_half + offset, upper_width, z1), (upper_half + offset, -upper_width, z1)]
    parts.append(add_quad("ObservationWindow_%s" % side.title(), vertices, glass))


def build_watchtower():
    mats = {
        "stone": material("MAT_Checkpoint_Stone", "#6A747B", roughness=0.92),
        "stone_light": material("MAT_Checkpoint_StoneLight", "#899198", roughness=0.89),
        "stone_dark": material("MAT_Checkpoint_StoneDark", "#434B52", roughness=0.94),
        "band": material("MAT_Checkpoint_BlueBand", "#273C49", roughness=0.68, metallic=0.10),
        "glass": material("MAT_Checkpoint_DarkBlueGlass", "#183B4D", roughness=0.30, metallic=0.18),
        "roof": material("MAT_Checkpoint_Roof", "#333A40", roughness=0.72, metallic=0.12),
        "beacon_base": material("MAT_Checkpoint_BeaconBase", "#242B30", roughness=0.42, metallic=0.48),
        "beacon": material("MAT_Checkpoint_BeaconGlow", "#FFAA3D", roughness=0.20, metallic=0.05, emission="#FF9E35", emission_strength=4.0),
    }
    parts = []

    # Square road-side plinth and a heavy battered stone lower body.
    parts.append(add_cube("FoundationSlab", (0.0, 0.0, 0.11), (5.20, 5.20, 0.22), mats["stone_dark"], 0.055))
    parts.append(add_frustum("BatteredStoneBase", BODY_BOTTOM_Z, BODY_TOP_Z, 4.94, 4.94, 3.54, 3.54, mats["stone"]))

    # Courses project just past the main taper and give the plain stone mass readable scale.
    parts.extend([
        add_frustum("LowerStoneCourse", 0.30, 0.78, 5.05, 5.05, 4.91, 4.91, mats["stone_dark"]),
        add_frustum("MidStoneCourse", 2.34, 2.68, 4.46, 4.46, 4.36, 4.36, mats["stone_light"]),
        add_frustum("UpperStoneCourse", 4.60, 4.90, 3.83, 3.83, 3.74, 3.74, mats["stone_dark"]),
        add_cube("TransitionCrown", (0.0, 0.0, 5.18), (3.82, 3.82, 0.24), mats["stone_light"], 0.035),
    ])

    # Four low corner blocks make the footprint feel engineered for a road checkpoint.
    for x in (-2.22, 2.22):
        for y in (-2.22, 2.22):
            parts.append(add_cube("CornerFooting_%s_%s" % ("L" if x < 0 else "R", "F" if y < 0 else "B"), (x, y, 0.52), (0.44, 0.44, 0.62), mats["stone_light"], 0.035))

    # Inverted four-sided frustum: narrow below, broad around the glazed observation room.
    parts.append(add_frustum("ObservationRoomStoneShell", CABIN_BOTTOM_Z, CABIN_TOP_Z, 3.56, 3.56, 4.48, 4.48, mats["stone"]))
    parts.extend([
        add_frustum("CheckpointBand", 5.38, 5.68, 3.66, 3.66, 3.74, 3.74, mats["band"]),
        add_frustum("ObservationLowerLedge", 5.72, 5.90, 3.78, 3.78, 3.83, 3.83, mats["stone_light"]),
        add_frustum("ObservationUpperLedge", 8.15, 8.34, 4.26, 4.26, 4.31, 4.31, mats["stone_dark"]),
    ])
    for side in ("front", "right", "back", "left"):
        add_window_side(parts, side, mats)

    # A small overhanging roof protects the sealed observation room, with an amber road beacon.
    parts.extend([
        add_cube("RoofSlab", (0.0, 0.0, 8.68), (4.82, 4.82, 0.24), mats["roof"], 0.045),
        add_frustum("RoofCap", 8.80, 9.15, 4.52, 4.52, 3.98, 3.98, mats["stone_dark"]),
        add_cube("RoofParapet", (0.0, 0.0, 9.25), (3.98, 3.98, 0.16), mats["roof"], 0.025),
        add_cylinder("CheckpointBeaconBase", (0.0, 0.0, 9.38), 0.31, 0.16, mats["beacon_base"], bevel=0.022),
    ])
    glow = add_uv_sphere("Glow", (0.0, 0.0, 9.62), (0.48, 0.48, 0.40), mats["beacon"])
    return parts, glow


def bounds(parts):
    points = [obj.matrix_world @ Vector(corner) for obj in parts for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def validate(parts):
    if not parts:
        raise RuntimeError("No watchtower parts created")
    minimum, maximum = bounds(parts)
    size = maximum - minimum
    if minimum.z < -0.01 or minimum.z > 0.02:
        raise RuntimeError("Watchtower must sit on ground, z_min=%f" % minimum.z)
    if not (4.8 <= size.x <= 5.4 and 4.8 <= size.y <= 5.4):
        raise RuntimeError("Unexpected footprint %s" % tuple(round(value, 3) for value in size))
    if not (9.3 <= size.z <= 10.0):
        raise RuntimeError("Unexpected height %f" % size.z)
    print("VALID RoadCheckpointWatchtower bounds=%s size=%s parts=%d" % (tuple(round(value, 3) for value in minimum), tuple(round(value, 3) for value in size), len(parts)))


def join_parts(parts, glow):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    # Keep the exported scene root and the visible tower mesh distinct.  This
    # preserves the child node named Glow alongside the main mesh in Godot.
    merged.name = "TowerMesh"
    merged.data.name = "MESH_RoadCheckpointWatchtower"
    merged.select_set(False)
    root = bpy.data.objects.new("RoadCheckpointWatchtower", None)
    bpy.context.collection.objects.link(root)
    merged.parent = root
    glow.parent = root
    return root, merged


def render_preview(merged, glow, path):
    scene = bpy.context.scene
    # The bundled Blender 5 build keeps the legacy enum spelling, while newer
    # desktop builds expose Eevee Next under a different identifier.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.render.film_transparent = False
    scene.world.color = (0.035, 0.050, 0.070)

    road_mat = material("MAT_Preview_Asphalt", "#30363B", roughness=0.96)
    line_mat = material("MAT_Preview_RoadLine", "#D2A447", roughness=0.75)
    road = add_cube("PreviewRoad", (0.0, 0.0, -0.10), (19.0, 19.0, 0.16), road_mat)
    for y in (-6.0, 6.0):
        add_cube("PreviewRoadLine_%s" % y, (0.0, y, -0.006), (15.5, 0.16, 0.015), line_mat)

    bpy.ops.object.camera_add(location=(13.6, -16.6, 11.2))
    camera = bpy.context.object
    camera.data.lens = 52
    camera.rotation_euler = (Vector((0.0, 0.0, 4.85)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    def area(name, location, energy, size, target):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()
        return light

    area("KeyLight", (4.0, -8.0, 15.0), 1600, 7.0, (0.0, 0.0, 4.8))
    area("FillLight", (-10.0, -2.0, 9.0), 950, 6.0, (0.0, 0.0, 5.0))
    area("RimLight", (3.0, 8.0, 12.0), 1300, 5.0, (0.0, 0.0, 6.0))
    bpy.ops.object.light_add(type="POINT", location=glow.location)
    beacon_light = bpy.context.object
    beacon_light.name = "PreviewBeaconLight"
    beacon_light.data.energy = 95.0
    beacon_light.data.color = (1.0, 0.48, 0.10)
    beacon_light.data.shadow_soft_size = 1.2

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    for obj in [road] + [item for item in bpy.context.scene.objects if item.name.startswith("PreviewRoadLine_")]:
        bpy.data.objects.remove(obj, do_unlink=True)


def export_glb(root, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=os.path.abspath(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    root.select_set(False)
    for child in root.children:
        child.select_set(False)


def main():
    args = parse_args()
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    parts, glow = build_watchtower()
    validate(parts + [glow])
    root, merged = join_parts(parts, glow)
    if not args.no_preview:
        render_preview(merged, glow, os.path.abspath(args.preview))
    export_glb(root, args.output)
    merged.data.calc_loop_triangles()
    print("EXPORTED %s triangles=%d materials=%d preview=%s" % (os.path.abspath(args.output), len(merged.data.loop_triangles), len(merged.data.materials), os.path.abspath(args.preview)))


if __name__ == "__main__":
    main()
