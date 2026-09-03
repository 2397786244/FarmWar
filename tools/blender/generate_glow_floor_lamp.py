import argparse
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(PROJECT_ROOT, "assets", "facilities", "interior")
OUTPUT_FILENAME = "GlowFloorLamp.glb"


def parse_args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Generate a closed glowing floor lamp GLB.")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument("--preview", default="")
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def material(name, color, metallic=0.0, roughness=0.5, emission=None, emission_strength=0.0):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = (*color, 1.0)
    bsdf = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if emission_input is not None:
            emission_input.default_value = (*emission, 1.0)
        strength_input = bsdf.inputs.get("Emission Strength")
        if strength_input is not None:
            strength_input.default_value = emission_strength
    return result


def finish(obj, name, surface, parent):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.data.materials.append(surface)
    obj.parent = parent
    return obj


def add_cylinder(name, location, radius, depth, surface, parent, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=48,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    obj = bpy.context.object
    if bevel > 0.0:
        modifier = obj.modifiers.new("SoftEdges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 3
    return finish(obj, name, surface, parent)


def add_closed_frustum(name, location, bottom_radius, top_radius, depth, surface, parent):
    # The NGON end fill deliberately makes the luminous housing a fully closed body,
    # rather than an open lampshade with a visible hollow interior.
    bpy.ops.mesh.primitive_cone_add(
        vertices=64,
        radius1=bottom_radius,
        radius2=top_radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    obj = bpy.context.object
    bevel = obj.modifiers.new("SoftHousingEdges", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 3
    return finish(obj, name, surface, parent)


def bounds(meshes):
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    return (
        Vector(tuple(min(point[index] for point in points) for index in range(3))),
        Vector(tuple(max(point[index] for point in points) for index in range(3))),
    )


def build_lamp():
    black_metal = material("MAT_FloorLamp_BlackMetal", (0.012, 0.015, 0.020), metallic=0.78, roughness=0.24)
    warm_glow = material(
        "MAT_FloorLamp_WarmGlow",
        (1.0, 0.36, 0.045),
        metallic=0.0,
        roughness=0.34,
        emission=(1.0, 0.20, 0.018),
        emission_strength=4.2,
    )

    root = bpy.data.objects.new("GlowFloorLamp", None)
    bpy.context.collection.objects.link(root)

    # Overall height is 1.78m: suitable for interior placement while safely below the 2m limit.
    add_cylinder("Base", (0.0, 0.0, 0.045), 0.275, 0.09, black_metal, root, bevel=0.020)
    add_cylinder("BaseCollar", (0.0, 0.0, 0.105), 0.082, 0.040, black_metal, root, bevel=0.009)
    add_cylinder("Stem", (0.0, 0.0, 0.540), 0.037, 0.850, black_metal, root, bevel=0.007)
    add_cylinder("HousingConnector", (0.0, 0.0, 0.970), 0.075, 0.055, black_metal, root, bevel=0.010)
    add_closed_frustum("GlowHousing", (0.0, 0.0, 1.365), 0.220, 0.385, 0.830, warm_glow, root)

    bpy.context.view_layer.update()
    meshes = [child for child in root.children if child.type == "MESH"]
    minimum, maximum = bounds(meshes)
    height = maximum.z - minimum.z
    if minimum.z < -0.001 or maximum.z > 2.0 or height > 2.0:
        raise RuntimeError("Floor lamp bounds violate the requested maximum height.")
    return root


def render_preview(path):
    bpy.ops.object.camera_add(location=(3.4, -4.2, 2.45))
    camera = bpy.context.object
    bpy.context.scene.camera = camera
    target = Vector((0.0, 0.0, 0.92))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 55

    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, -0.006))
    ground = bpy.context.object
    ground.data.materials.append(material("MAT_PreviewFloor", (0.018, 0.022, 0.030), roughness=0.72))

    bpy.ops.object.light_add(type="AREA", location=(2.4, -2.7, 3.4))
    key = bpy.context.object
    key.data.energy = 450.0
    key.data.shape = "DISK"
    key.data.size = 3.0
    key.rotation_euler = (0.44, 0.0, 0.70)

    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.render.resolution_x = 720
    bpy.context.scene.render.resolution_y = 720
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.render.filepath = path
    bpy.context.scene.world.color = (0.006, 0.008, 0.014)
    bpy.context.scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.context.scene.render.film_transparent = False
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(ground, do_unlink=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.objects.remove(key, do_unlink=True)


def main():
    args = parse_args()
    clear_scene()
    root = build_lamp()
    bpy.context.view_layer.objects.active = root
    if args.preview:
        render_preview(os.path.abspath(args.preview))
    os.makedirs(args.output, exist_ok=True)
    output = os.path.abspath(os.path.join(args.output, OUTPUT_FILENAME))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    print("Exported: " + output)


if __name__ == "__main__":
    main()
