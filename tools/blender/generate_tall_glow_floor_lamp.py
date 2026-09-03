import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "facilities", "interior")
OUTPUT_FILENAME = "TallGlowFloorLamp.glb"


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate a tall closed glowing floor lamp GLB.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default="")
    parser.add_argument("--filename", default=OUTPUT_FILENAME)
    parser.add_argument(
        "--sunset-glow",
        action="store_true",
        help="Use a deeper sunset-yellow emissive material.",
    )
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def make_material(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = (*color, 1.0)
    bsdf = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if emission_input:
            emission_input.default_value = (*emission, 1.0)
        emission_strength = bsdf.inputs.get("Emission Strength")
        if emission_strength:
            emission_strength.default_value = strength
    return result


def finish(obj, name, surface, root, bevel=0.0):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.data.materials.append(surface)
    obj.parent = root
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    return obj


def cylinder(name, location, radius, depth, surface, root, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radius, depth=depth, end_fill_type="NGON", location=location)
    return finish(bpy.context.object, name, surface, root, bevel)


def closed_frustum(name, location, bottom_radius, top_radius, depth, surface, root):
    # Capped ends keep the short glowing shade fully closed; there is no visible hollow.
    bpy.ops.mesh.primitive_cone_add(
        vertices=64,
        radius1=bottom_radius,
        radius2=top_radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    return finish(bpy.context.object, name, surface, root, bevel=0.016)


def calculate_bounds(objects):
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return min(point.z for point in points), max(point.z for point in points)


def build_lamp(sunset_glow=False):
    metal = make_material("MAT_TallLamp_BlackMetal", (0.008, 0.011, 0.016), metallic=0.82, roughness=0.20)
    if sunset_glow:
        glow = make_material(
            "MAT_TallLamp_SunsetGlow",
            (1.0, 0.26, 0.018),
            roughness=0.32,
            emission=(1.0, 0.075, 0.004),
            strength=4.8,
        )
    else:
        glow = make_material(
            "MAT_TallLamp_SoftWarmGlow",
            (1.0, 0.58, 0.17),
            roughness=0.30,
            emission=(1.0, 0.27, 0.035),
            strength=4.5,
        )
    root = bpy.data.objects.new("TallGlowFloorLamp", None)
    bpy.context.collection.objects.link(root)

    # 2m total height. The shade is intentionally short (0.46m) and top-small/bottom-wide;
    # the 1.38m visible stem gives it a distinct floor-lamp rather than table-lamp proportion.
    cylinder("Base", (0.0, 0.0, 0.040), 0.310, 0.080, metal, root, bevel=0.020)
    cylinder("BaseInset", (0.0, 0.0, 0.088), 0.118, 0.035, metal, root, bevel=0.008)
    cylinder("Stem", (0.0, 0.0, 0.770), 0.032, 1.335, metal, root, bevel=0.006)
    cylinder("TopJoint", (0.0, 0.0, 1.455), 0.070, 0.045, metal, root, bevel=0.008)
    closed_frustum("GlowHousing", (0.0, 0.0, 1.770), 0.410, 0.205, 0.460, glow, root)

    bpy.context.view_layer.update()
    meshes = [child for child in root.children if child.type == "MESH"]
    low, high = calculate_bounds(meshes)
    if low < -0.001 or high > 2.001 or high - low > 2.001:
        raise RuntimeError("Tall floor lamp exceeds its 2m height limit.")
    return root


def render_preview(path):
    bpy.ops.object.camera_add(location=(3.8, -4.8, 2.7))
    camera = bpy.context.object
    bpy.context.scene.camera = camera
    target = Vector((0.0, 0.0, 1.02))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 58

    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, -0.006))
    plane = bpy.context.object
    plane.data.materials.append(make_material("MAT_PreviewFloor", (0.012, 0.016, 0.024), roughness=0.72))
    bpy.ops.object.light_add(type="AREA", location=(2.7, -2.9, 3.8))
    light = bpy.context.object
    light.data.energy = 480.0
    light.data.shape = "DISK"
    light.data.size = 3.2
    light.rotation_euler = (0.48, 0.0, 0.72)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = path
    scene.world.color = (0.004, 0.006, 0.010)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    for obj in (plane, camera, light):
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    args = parse_args()
    clear_scene()
    root = build_lamp(args.sunset_glow)
    if args.preview:
        render_preview(os.path.abspath(args.preview))
    os.makedirs(args.output, exist_ok=True)
    output_path = os.path.abspath(os.path.join(args.output, args.filename))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
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


if __name__ == "__main__":
    main()
