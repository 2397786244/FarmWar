import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "buildings")
DEFAULT_PREVIEW = os.path.join(DEFAULT_OUTPUT, "RoadBarrier_Preview.png")

# FarmBaseVehicle is 3.4m wide. The 3.9m arm leaves useful clearance while
# still reaching across a single road lane.
ARM_LENGTH = 3.90
# The boom passes through the pivot support and overlaps the cabinet cap by
# roughly 10cm, making the mechanical connection read clearly from any angle.
ARM_HEIGHT = 0.92


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate mirrored roadside barrier GLBs.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default=DEFAULT_PREVIEW)
    parser.add_argument("--detail-preview", default="")
    parser.add_argument("--no-preview", action="store_true")
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(datablocks):
            if item.users == 0:
                datablocks.remove(item)


def material(name, color, roughness=0.5, metallic=0.0, emission=None, emission_strength=0.0):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = (*color, 1.0)
    shader = next(
        (node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED"),
        None,
    )
    if shader is None:
        raise RuntimeError("Could not create a Principled material shader")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission is not None:
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = emission_strength
    return result


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def finish(obj, name, surface, parent=None):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.data.materials.append(surface)
    if parent is not None:
        obj.parent = parent
    return obj


def add_box(name, location, dimensions, surface, parent=None, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return finish(obj, name, surface, parent)


def add_cylinder(name, location, radius, depth, surface, parent=None, vertices=32, bevel=0.0, rotation=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    if rotation is not None:
        obj.rotation_euler = rotation
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    return finish(obj, name, surface, parent)


def add_uv_sphere(name, location, radius, surface, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=radius, location=location)
    return finish(bpy.context.object, name, surface, parent)


def create_arm_mesh(name, length, direction, surface, parent):
    # Its local origin is the pivot (x=0), so this mesh and its children can be
    # rotated directly in Godot to raise/lower the gate without an extra offset.
    half_y = 0.060
    half_z = 0.055
    vertices = [
        (0.0, -half_y, -half_z), (length * direction, -half_y, -half_z),
        (length * direction, half_y, -half_z), (0.0, half_y, -half_z),
        (0.0, -half_y, half_z), (length * direction, -half_y, half_z),
        (length * direction, half_y, half_z), (0.0, half_y, half_z),
    ]
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (1, 2, 6, 5),
        (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new("MESH_" + name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(surface)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = (0.0, 0.0, ARM_HEIGHT)
    obj.parent = parent
    bevel = obj.modifiers.new("ArmEdge", "BEVEL")
    bevel.width = 0.014
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)
    return obj


def build_barrier(root_name, control_on_left, mats):
    root = bpy.data.objects.new(root_name, None)
    bpy.context.collection.objects.link(root)

    direction = 1.0 if control_on_left else -1.0
    control_x = -2.10 if control_on_left else 2.10
    pivot_x = control_x + direction * 0.265

    # A compact orange steel cabinet: weighted base, beveled plinth, dark
    # service door and an understated status indicator make it readable at road scale.
    add_box("FoundationPlate", (control_x, 0.0, 0.035), (0.78, 0.62, 0.07), mats["black"], root, 0.025)
    add_box("ControlBase", (control_x, 0.0, 0.155), (0.57, 0.45, 0.22), mats["orange_dark"], root, 0.045)
    add_box("ControlHousing", (control_x, 0.0, 0.575), (0.48, 0.38, 0.65), mats["orange"], root, 0.050)
    # The wider cap intentionally reaches under the pivot instead of stopping
    # exactly at the boom's near edge.
    add_box("ControlCap", (control_x, 0.0, 0.925), (0.66, 0.43, 0.075), mats["orange_light"], root, 0.028)
    add_box("ServiceDoor", (control_x, -0.196, 0.555), (0.31, 0.012, 0.38), mats["charcoal"], root, 0.008)
    add_box("DoorHandle", (control_x + direction * 0.08, -0.208, 0.535), (0.04, 0.018, 0.10), mats["steel"], root, 0.006)
    # Keep the indicator clearly above the service door rather than resting on
    # its top edge; both the bezel and glow move together as one assembly.
    add_cylinder("StatusBezel", (control_x - direction * 0.09, -0.211, 0.82), 0.037, 0.016, mats["black"], root, rotation=(1.5708, 0.0, 0.0))
    add_uv_sphere("StatusGlow", (control_x - direction * 0.09, -0.224, 0.82), 0.022, mats["green"], root)
    for sx in (-0.27, 0.27):
        for sy in (-0.20, 0.20):
            add_cylinder("AnchorBolt", (control_x + sx, sy, 0.083), 0.025, 0.024, mats["steel"], root, vertices=12)

    # A solid orange pivot column visibly bridges the cap and hinge. It is
    # deliberately behind the front hinge discs, so the rotating joint remains
    # legible while the housing no longer appears to float below it.
    add_box("PivotSupport", (pivot_x, 0.0, 0.875), (0.24, 0.34, 0.30), mats["orange_dark"], root, 0.035)
    add_box("PivotSupportTop", (pivot_x, 0.0, 1.015), (0.30, 0.38, 0.075), mats["orange_light"], root, 0.022)

    # The arm's origin stays at the mechanical pivot. It is deliberately one
    # standalone mesh, so gameplay can rotate this white boom directly.
    arm = create_arm_mesh("BarrierArm", ARM_LENGTH, direction, mats["white"], root)
    arm.location.x = pivot_x
    arm.rotation_euler = (0.0, 0.0, 0.0)
    # The disc is a real cross-arm hinge: its Y depth passes through the boom
    # and its front face remains visible beyond the pivot support. The smaller
    # hub overlaps the disc and reaches the front face of the white arm.
    add_cylinder("HingeDisc", (pivot_x, -0.12, ARM_HEIGHT), 0.135, 0.26, mats["black"], root, rotation=(1.5708, 0.0, 0.0), bevel=0.008)
    add_cylinder("HingeHub", (pivot_x, -0.22, ARM_HEIGHT), 0.075, 0.14, mats["orange_light"], root, rotation=(1.5708, 0.0, 0.0), bevel=0.006)
    return root


def bounds(root):
    meshes = [child for child in root.children_recursive if child.type == "MESH"]
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[index] for point in points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in points) for index in range(3)))
    return minimum, maximum


def validate(root):
    arm = next((child for child in root.children if child.name.startswith("BarrierArm")), None)
    if arm is None or arm.type != "MESH":
        raise RuntimeError("BarrierArm must be an independent mesh node")
    if abs(arm.location.z - ARM_HEIGHT) > 0.001:
        raise RuntimeError("BarrierArm pivot has an unexpected elevation")
    minimum, maximum = bounds(root)
    size = maximum - minimum
    if not (3.85 <= ARM_LENGTH <= 4.15):
        raise RuntimeError("Barrier arm must clear FarmBaseVehicle width")
    if minimum.z < -0.01 or maximum.z > 1.20:
        raise RuntimeError("Road barrier height is out of range: min=%.3f max=%.3f" % (minimum.z, maximum.z))
    print("VALID %s bounds=%s size=%s arm=%.2fm" % (
        root.name,
        tuple(round(value, 3) for value in minimum),
        tuple(round(value, 3) for value in size),
        ARM_LENGTH,
    ))


def export_root(root, output_path):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print("Exported: " + output_path)


def render_preview(left_root, right_root, path, mats):
    # Place the two variants as a checkpoint pair, keeping the GLB roots intact.
    left_root.location.y = -1.65
    right_root.location.y = 1.65

    road = add_box("PreviewAsphalt", (0.0, 0.0, -0.08), (11.0, 7.2, 0.12), mats["asphalt"], bevel=0.02)
    for y in (-1.65, 1.65):
        add_box("LaneMark_%s" % y, (0.0, y - 0.55, -0.008), (7.6, 0.10, 0.016), mats["road_line"])

    bpy.ops.object.camera_add(location=(7.6, -10.2, 6.6))
    camera = bpy.context.object
    camera.data.lens = 54
    camera.rotation_euler = (Vector((0.0, 0.0, 0.62)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    for location, energy, size in [
        ((3.2, -4.8, 6.5), 980.0, 4.5),
        ((-4.0, -1.5, 3.2), 520.0, 3.0),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (Vector((0.0, 0.0, 0.55)) - light.location).to_track_quat("-Z", "Y").to_euler()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 760
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.035, 0.052)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def render_connection_preview(left_root, path, mats):
    target = Vector((-1.55, -1.65, 0.78))
    bpy.ops.object.camera_add(location=(-3.25, -4.85, 2.15))
    camera = bpy.context.object
    camera.data.lens = 70
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-2.8, -3.6, 3.1))
    key = bpy.context.object
    key.data.energy = 460.0
    key.data.shape = "DISK"
    key.data.size = 2.0
    key.rotation_euler = (target - key.location).to_track_quat("-Z", "Y").to_euler()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.render.film_transparent = False
    scene.world.color = (0.025, 0.035, 0.052)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    clear_scene()
    mats = {
        "orange": material("MAT_Barrier_Orange", (0.92, 0.255, 0.025), roughness=0.34, metallic=0.52),
        "orange_dark": material("MAT_Barrier_OrangeDark", (0.47, 0.060, 0.008), roughness=0.42, metallic=0.48),
        "orange_light": material("MAT_Barrier_OrangeLight", (1.0, 0.49, 0.045), roughness=0.31, metallic=0.38),
        "white": material("MAT_Barrier_White", (0.93, 0.945, 0.95), roughness=0.28, metallic=0.12),
        "reflective_orange": material("MAT_Barrier_ReflectiveOrange", (1.0, 0.24, 0.015), roughness=0.20, metallic=0.05, emission=(1.0, 0.055, 0.002), emission_strength=0.22),
        "black": material("MAT_Barrier_Black", (0.012, 0.017, 0.023), roughness=0.28, metallic=0.78),
        "charcoal": material("MAT_Barrier_Charcoal", (0.065, 0.080, 0.095), roughness=0.38, metallic=0.56),
        "steel": material("MAT_Barrier_Steel", (0.30, 0.34, 0.38), roughness=0.30, metallic=0.88),
        "green": material("MAT_Barrier_Indicator", (0.06, 0.85, 0.27), roughness=0.24, metallic=0.05, emission=(0.015, 1.0, 0.13), emission_strength=2.2),
        "asphalt": material("MAT_Preview_Asphalt", (0.065, 0.080, 0.092), roughness=0.93),
        "road_line": material("MAT_Preview_Line", (0.90, 0.64, 0.16), roughness=0.52),
    }
    left_root = build_barrier("RoadBarrierLeft", True, mats)
    right_root = build_barrier("RoadBarrierRight", False, mats)
    validate(left_root)
    validate(right_root)

    os.makedirs(args.output, exist_ok=True)
    export_root(left_root, os.path.join(args.output, "RoadBarrierLeft.glb"))
    # Blender object names must be unique inside this generation scene. Rename
    # the already-exported left arm so the right GLB can expose the same stable
    # BarrierArm node name expected by the game.
    left_arm = next(child for child in left_root.children if child.name.startswith("BarrierArm"))
    right_arm = next(child for child in right_root.children if child.name.startswith("BarrierArm"))
    left_arm.name = "BarrierArm_LeftPreview"
    right_arm.name = "BarrierArm"
    export_root(right_root, os.path.join(args.output, "RoadBarrierRight.glb"))
    if not args.no_preview:
        render_preview(left_root, right_root, os.path.abspath(args.preview), mats)
        print("Rendered: " + os.path.abspath(args.preview))
        if args.detail_preview:
            render_connection_preview(left_root, os.path.abspath(args.detail_preview), mats)
            print("Rendered: " + os.path.abspath(args.detail_preview))


if __name__ == "__main__":
    main()
