"""Compose existing PNGs as 2D texture layers into a 1024x1024 image."""

import argparse
import sys
from pathlib import Path

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Compose a 2D cargo car with crates.")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--output",
        default="assets/icons/app_icon_sources/red_cargo_car_with_crates_2d.png",
    )
    parser.add_argument("--size", type=int, default=1024)
    return parser.parse_args(argv)


def make_emission_material(name, image=None, color=(1.0, 1.0, 1.0, 1.0)):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 1.0
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")

    if image is None:
        emission.inputs["Color"].default_value = color
        links.new(emission.outputs[0], output.inputs[0])
    else:
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.interpolation = "Linear"
        links.new(texture.outputs["Color"], emission.inputs["Color"])
        links.new(texture.outputs["Alpha"], mix.inputs[0])
        links.new(transparent.outputs[0], mix.inputs[1])
        links.new(emission.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], output.inputs[0])
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "DITHERED"
    return material


def make_layer(name, material, center_x, center_y, scale, size):
    # World coordinates map directly to the 1024x1024 canvas:
    # x = (pixel_x - 512) / 512, y = (512 - pixel_y) / 512.
    bpy.ops.mesh.primitive_plane_add(
        size=2.0 * scale,
        location=(
            (center_x - size * 0.5) / (size * 0.5),
            (size * 0.5 - center_y) / (size * 0.5),
            0.0,
        ),
    )
    layer = bpy.context.object
    layer.name = name
    layer.data.materials.append(material)
    return layer


def load_image(path):
    return bpy.data.images.load(str(path), check_existing=False)


def main():
    args = parse_args()
    project = Path(args.project).resolve()
    output_path = (project / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = args.size
    scene.render.resolution_y = args.size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = str(output_path)
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0

    camera_data = bpy.data.cameras.new("CargoCar2DCamera")
    camera = bpy.data.objects.new("CargoCar2DCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.0
    camera.location = (0.0, 0.0, 10.0)
    scene.camera = camera

    white_material = make_emission_material("White background")
    make_layer("White background", white_material, 512.0, 512.0, 1.0, args.size)

    crate_image = load_image(
        project / "assets/icons/app_icon_sources/cargo_crate_medium_front.png"
    )
    crate_material = make_emission_material("Cargo crate 2D", crate_image)

    # Three crates on the lower layer, one crate on the upper layer.
    for index, (center_x, center_y) in enumerate(
        ((590.0, 472.0), (705.0, 472.0), (820.0, 472.0), (705.0, 348.0)),
        1,
    ):
        make_layer(
            f"Cargo crate layer {index}",
            crate_material,
            center_x,
            center_y,
            0.18,
            args.size,
        ).location.z = 0.1 + index * 0.001

    truck_image = load_image(
        project / "assets/icons/app_icon_sources/red_cargo_car_side.png"
    )
    truck_material = make_emission_material("Red CargoCar 2D", truck_image)
    make_layer("Red CargoCar foreground", truck_material, 512.0, 512.0, 1.0, args.size).location.z = 1.0

    bpy.ops.render.render(write_still=True)
    print(f"[CargoCar2D] Saved: {output_path}")


if __name__ == "__main__":
    main()
