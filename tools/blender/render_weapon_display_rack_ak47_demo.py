import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
DEFAULT_OUTPUT = os.path.join(
    PROJECT_ROOT,
    "assets",
    "facilities",
    "interior",
    "WeaponDisplayRack_AK47_Demo.png",
)
RACK_PATH = os.path.join(
    PROJECT_ROOT,
    "assets",
    "facilities",
    "interior",
    "WeaponDisplayRack.glb",
)
AK47_VARIANTS = (
    (
        "Golden",
        os.path.join(PROJECT_ROOT, "assets", "tools", "other_styles", "Golden", "AK47_Golden.glb"),
        3.69,
    ),
    (
        "HardenedSteel",
        os.path.join(
            PROJECT_ROOT,
            "assets",
            "tools",
            "other_styles",
            "HardenedSteel",
            "AK47_HardenedSteel.glb",
        ),
        2.58,
    ),
    (
        "Rusted",
        os.path.join(PROJECT_ROOT, "assets", "tools", "other_styles", "Rusted", "AK47_Rusted.glb"),
        1.47,
    ),
)
WEAPON_SCALE = 1.35


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(values)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def srgb_channel_to_linear(channel):
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def color(value):
    value = value.lstrip("#")
    channels = [int(value[index:index + 2], 16) / 255.0 for index in range(0, 6, 2)]
    return tuple(srgb_channel_to_linear(channel) for channel in channels) + (1.0,)


def make_material(name, hex_color, metallic=0.0, roughness=0.7):
    material = bpy.data.materials.new(name)
    rgba = color(hex_color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def descendants(root):
    yield root
    for child in root.children:
        yield from descendants(child)


def mesh_bounds(objects):
    meshes = [obj for obj in objects if obj.type == "MESH"]
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def import_glb(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def add_ak47_variant(name, path, support_height):
    imported = import_glb(path)
    imported_set = set(imported)
    roots = [obj for obj in imported if obj.parent not in imported_set]

    wrapper = bpy.data.objects.new(f"AK47_{name}_Display", None)
    bpy.context.collection.objects.link(wrapper)
    for root in roots:
        root.parent = wrapper

    # Source AK47 models are longitudinal on Y. Rotate them horizontally across the rack.
    wrapper.rotation_euler.z = math.radians(90.0)
    wrapper.scale = (WEAPON_SCALE, WEAPON_SCALE, WEAPON_SCALE)
    bpy.context.view_layer.update()

    minimum, maximum = mesh_bounds(list(descendants(wrapper)))
    center = (minimum + maximum) * 0.5
    target_bottom = support_height + 0.035
    wrapper.location += Vector((
        -center.x,
        -0.25 - center.y,
        target_bottom - minimum.z,
    ))
    bpy.context.view_layer.update()

    minimum, maximum = mesh_bounds(list(descendants(wrapper)))
    print(
        f"PLACED {name} "
        f"bounds={tuple(round(value, 3) for value in minimum)}.."
        f"{tuple(round(value, 3) for value in maximum)}"
    )
    return wrapper


def add_environment():
    floor_material = make_material("MAT_DemoFloor", "#50565D", roughness=0.86)
    wall_material = make_material("MAT_DemoWall", "#252A31", roughness=0.91)

    bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, 0.0, -0.012))
    bpy.context.object.name = "DemoFloor"
    bpy.context.object.data.materials.append(floor_material)

    bpy.ops.mesh.primitive_plane_add(
        size=18.0,
        location=(0.0, 0.22, 5.0),
        rotation=(math.radians(90.0), 0.0, 0.0),
    )
    bpy.context.object.name = "DemoWall"
    bpy.context.object.data.materials.append(wall_material)


def add_area_light(name, location, energy, size, target, color_value):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.data.color = color_value
    light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()
    return light


def configure_render(output_path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 1250
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = output_path
    scene.render.film_transparent = False

    world = scene.world or bpy.data.worlds.new("DemoWorld")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = color("#10151C")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.24

    bpy.ops.object.camera_add(location=(6.25, -10.6, 4.45))
    camera = bpy.context.object
    camera.name = "DemoCamera"
    camera.data.lens = 60
    target = Vector((0.0, -0.10, 2.34))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera

    add_area_light(
        "KeyLight",
        (-3.5, -4.0, 6.5),
        1250,
        4.5,
        (0.0, -0.15, 2.5),
        (1.0, 0.86, 0.70),
    )
    add_area_light(
        "FillLight",
        (4.4, -3.0, 4.6),
        900,
        4.0,
        (0.0, -0.12, 2.4),
        (0.65, 0.78, 1.0),
    )
    add_area_light(
        "TopRimLight",
        (0.0, 1.8, 6.1),
        1350,
        3.8,
        (0.0, 0.0, 2.8),
        (0.72, 0.82, 1.0),
    )


def main():
    args = parse_args()
    output_path = os.path.abspath(args.output)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    clear_scene()

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    import_glb(RACK_PATH)
    for name, path, support_height in AK47_VARIANTS:
        add_ak47_variant(name, path, support_height)

    add_environment()
    configure_render(output_path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {output_path}")


if __name__ == "__main__":
    main()
