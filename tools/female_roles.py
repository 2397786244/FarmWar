# Blender 4.x / 5.x
# Self-contained FarmWar character generator.
# Builds Mage, Apothecary and Assistant female adult stylized low-poly roles,
# each in Red and Blue variants. Includes rigid humanoid rig, the same ten
# animation clip names/poses as the existing FarmWar pipeline, GLB export,
# re-import validation, and rendered pose checks.
#
# Run (macOS example):
# "/Applications/Blender.app/Contents/MacOS/Blender" --background --factory-startup \
#   --python generate_farmwar_female_roles_rigged.py -- --output /path/to/output
#
# WARNING: Script runs in factory startup scenes and clears its own scene.

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


def r(x=0.0, y=0.0, z=0.0):
    return (math.radians(x), math.radians(y), math.radians(z))


ANIMATIONS = {
    "Idle": {
        "end": 60,
        "loop": True,
        "keys": [
            (1,  {"Hips": {"loc": (0, 0, 0)}, "Chest": {"rot": r(0, 0, 0)}, "Head": {"rot": r(0, 0, 0)}}),
            (30, {"Hips": {"loc": (0, 0, 0.018)}, "Chest": {"rot": r(1.2, 0, 0.8)}, "Head": {"rot": r(-0.8, 0, -1.0)}}),
            (60, {"Hips": {"loc": (0, 0, 0)}, "Chest": {"rot": r(0, 0, 0)}, "Head": {"rot": r(0, 0, 0)}}),
        ],
    },
    "IdleTool": {
        "end": 60,
        "loop": True,
        "keys": [
            (1, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)}, "Chest": {"rot": r(0, 0, 0)},
            }),
            (30, {
                "__right_arm_ik": {"target": (-0.47, -0.21, 1.09), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 2)}, "Chest": {"rot": r(0.8, 0, 0.5)},
                "Hips": {"loc": (0, 0, 0.012)},
            }),
            (60, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)}, "Chest": {"rot": r(0, 0, 0)},
            }),
        ],
    },
    "IdleAim": {
        "end": 30,
        "loop": True,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(0, 0, 4)},
            }),
            (15, {
                "Chest": {"rot": r(0.5, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.495, 1.425), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(-0.4, 0, 4)},
            }),
            (30, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
                "Head": {"rot": r(0, 0, 4)},
            }),
        ],
    },
    "Walk": {
        "end": 24,
        "loop": True,
        "keys": [
            (1, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, 2)},
                "Thigh.L": {"rot": r(-24, 0, 0)}, "Thigh.R": {"rot": r(24, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(-18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
            (7, {
                "Hips": {"loc": (0, 0, 0.0), "rot": r(0, 0, 0)},
                "Thigh.L": {"rot": r(0, 0, 0)}, "Thigh.R": {"rot": r(0, 0, 0)},
                "UpperArm.L": {"rot": r(0, 0, 0)}, "UpperArm.R": {"rot": r(0, 0, 0)},
            }),
            (13, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, -2)},
                "Thigh.L": {"rot": r(24, 0, 0)}, "Thigh.R": {"rot": r(-24, 0, 0)},
                "UpperArm.L": {"rot": r(-18, 0, 0)}, "UpperArm.R": {"rot": r(18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
            (19, {
                "Hips": {"loc": (0, 0, 0.0), "rot": r(0, 0, 0)},
                "Thigh.L": {"rot": r(0, 0, 0)}, "Thigh.R": {"rot": r(0, 0, 0)},
                "UpperArm.L": {"rot": r(0, 0, 0)}, "UpperArm.R": {"rot": r(0, 0, 0)},
            }),
            (24, {
                "Hips": {"loc": (0, 0, 0.025), "rot": r(0, 0, 2)},
                "Thigh.L": {"rot": r(-24, 0, 0)}, "Thigh.R": {"rot": r(24, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(-18, 0, 0)},
                "Forearm.L": {"rot": r(-8, 0, 0)}, "Forearm.R": {"rot": r(-8, 0, 0)},
            }),
        ],
    },
    "JumpStart": {
        "end": 10,
        "loop": False,
        "keys": [
            (1, {}),
            (6, {
                "Hips": {"loc": (0, 0, -0.10)}, "Chest": {"rot": r(8, 0, 0)},
                "Thigh.L": {"rot": r(15, 0, 0)}, "Thigh.R": {"rot": r(15, 0, 0)},
                "UpperArm.L": {"rot": r(-12, 0, 0)}, "UpperArm.R": {"rot": r(-12, 0, 0)},
            }),
            (10, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-4, 0, 0)},
                "Thigh.L": {"rot": r(-8, 0, 0)}, "Thigh.R": {"rot": r(-8, 0, 0)},
                "UpperArm.L": {"rot": r(18, 0, 0)}, "UpperArm.R": {"rot": r(18, 0, 0)},
            }),
        ],
    },
    "JumpLoop": {
        "end": 20,
        "loop": True,
        "keys": [
            (1, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-3, 0, 0)},
                "Thigh.L": {"rot": r(-10, 0, 0)}, "Thigh.R": {"rot": r(8, 0, 0)},
                "UpperArm.L": {"rot": r(20, 0, 0)}, "UpperArm.R": {"rot": r(20, 0, 0)},
            }),
            (10, {
                "Hips": {"loc": (0, 0, 0.055)}, "Chest": {"rot": r(-2, 0, 0)},
                "Thigh.L": {"rot": r(-8, 0, 0)}, "Thigh.R": {"rot": r(6, 0, 0)},
                "UpperArm.L": {"rot": r(22, 0, 0)}, "UpperArm.R": {"rot": r(22, 0, 0)},
            }),
            (20, {
                "Hips": {"loc": (0, 0, 0.04)}, "Chest": {"rot": r(-3, 0, 0)},
                "Thigh.L": {"rot": r(-10, 0, 0)}, "Thigh.R": {"rot": r(8, 0, 0)},
                "UpperArm.L": {"rot": r(20, 0, 0)}, "UpperArm.R": {"rot": r(20, 0, 0)},
            }),
        ],
    },
    "JumpLand": {
        "end": 12,
        "loop": False,
        "keys": [
            (1, {"Hips": {"loc": (0, 0, 0.03)}, "Chest": {"rot": r(-3, 0, 0)}}),
            (6, {
                "Hips": {"loc": (0, 0, -0.12)}, "Chest": {"rot": r(9, 0, 0)},
                "Thigh.L": {"rot": r(16, 0, 0)}, "Thigh.R": {"rot": r(16, 0, 0)},
                "UpperArm.L": {"rot": r(-8, 0, 0)}, "UpperArm.R": {"rot": r(-8, 0, 0)},
            }),
            (12, {}),
        ],
    },
    "ShootOneHand": {
        "end": 10,
        "loop": False,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
            (3, {
                "Chest": {"rot": r(-2, 0, -4)},
                "__right_arm_ik": {"target": (-0.35, -0.40, 1.44), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(-7, -4, 2)},
            }),
            (6, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
            (10, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.34, -0.49, 1.42), "bend": (-1.0, 0.0, -0.25)},
                "Hand.R": {"rot": r(0, -4, 2)},
            }),
        ],
    },
    "PunchRight": {
        "end": 16,
        "loop": False,
        "keys": [
            (1, {
                "Chest": {"rot": r(0, 0, -4)},
                "__right_arm_ik": {"target": (-0.43, -0.22, 1.32), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 8)},
            }),
            (5, {
                "Chest": {"rot": r(1, 0, 9)},
                "__right_arm_ik": {"target": (-0.48, -0.10, 1.24), "bend": (-1.0, 0.0, -0.15)},
                "Hand.R": {"rot": r(0, 0, 10)},
            }),
            (8, {
                "Chest": {"rot": r(-2, 0, -10)},
                "__right_arm_ik": {"target": (-0.30, -0.50, 1.40), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 0)},
            }),
            (11, {
                "Chest": {"rot": r(0, 0, -5)},
                "__right_arm_ik": {"target": (-0.42, -0.24, 1.32), "bend": (-1.0, 0.0, -0.20)},
                "Hand.R": {"rot": r(0, 0, 8)},
            }),
            (16, {}),
        ],
    },
    "ToolUseRight": {
        "end": 20,
        "loop": False,
        "keys": [
            (1, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)},
            }),
            (7, {
                "Chest": {"rot": r(-2, 0, -4)},
                "__right_arm_ik": {"target": (-0.39, -0.40, 1.15), "bend": (-1.0, 0.0, -0.30)},
                "Hand.R": {"rot": r(0, -3, 2)},
            }),
            (12, {
                "Chest": {"rot": r(-3, 0, -6)},
                "__right_arm_ik": {"target": (-0.35, -0.50, 1.19), "bend": (-1.0, 0.0, -0.28)},
                "Hand.R": {"rot": r(0, -4, 1)},
            }),
            (20, {
                "__right_arm_ik": {"target": (-0.47, -0.20, 1.08), "bend": (-1.0, 0.0, -0.35)},
                "Hand.R": {"rot": r(0, 0, 3)},
            }),
        ],
    },
}


# =============================================================================
# PROJECT / OUTPUT
# =============================================================================

try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = os.getcwd()

DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "generated_farmwar_characters")
FPS = 30
RENDER_POSE_CHECKS = True
POSE_CHECKS = {
    "Walk": 1,
    "IdleAim": 15,
    "ShootOneHand": 3,
    "ToolUseRight": 12,
}

TEAM_COLORS = {
    "Red": "#F23838",
    "Blue": "#1687F8",
}

EXPRESSIONS = ("Calm", "Fierce", "Funny", "Happy", "Worried")

# =============================================================================
# GENERAL HELPERS
# =============================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate rigged FarmWar female character role variants."
    )
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--skip-pose-renders",
        action="store_true",
        help="Export and validate GLBs but do not render pose-check PNGs.",
    )
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def hex_rgba(value):
    value = value.lstrip("#")
    if len(value) == 6:
        value += "FF"
    return tuple(int(value[index:index + 2], 16) / 255.0 for index in range(0, 8, 2))


def clear_scene(remove_actions=False):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.armatures):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)

    if remove_actions:
        for action in list(bpy.data.actions):
            if action.users == 0:
                bpy.data.actions.remove(action)


def ensure_metric_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS


def make_material(name, color, metallic=0.0, roughness=0.72):
    material = bpy.data.materials.new(name)
    rgba = hex_rgba(color)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return material


def create_role_materials(role_name, team_name):
    """Exactly six visible material families per role/team variant."""
    team = TEAM_COLORS[team_name]
    common = {
        "skin": ("#E5A076", 0.0, 0.76),
        "dark": ("#303B43", 0.0, 0.72),
        "team": (team, 0.0, 0.58),
    }
    role_palettes = {
        "Mage": {
            "hair": ("#E7B73C", 0.0, 0.58),
            "primary": ("#5A4A9C", 0.0, 0.70),
            "accent": ("#E9DFC9", 0.0, 0.68),
        },
        "Apothecary": {
            "hair": ("#E978AE", 0.0, 0.58),
            "primary": ("#F3D7D8", 0.0, 0.72),
            "accent": ("#57B7A7", 0.0, 0.65),
        },
        "Assistant": {
            "hair": ("#25242C", 0.0, 0.66),
            "primary": ("#F2EEE3", 0.0, 0.74),
            "accent": ("#3188C6", 0.0, 0.72),
        },
    }
    colors = dict(common)
    colors.update(role_palettes[role_name])
    return {
        key: make_material(
            f"MAT_{role_name}_{team_name}_{key.title()}",
            color,
            metallic=metallic,
            roughness=roughness,
        )
        for key, (color, metallic, roughness) in colors.items()
    }


def create_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root["asset_type"] = "rigged_low_poly_character"
    root["front_axis"] = "-Y"
    return root


def apply_scale(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_bevel(obj, width):
    if width <= 0.0:
        return
    modifier = obj.modifiers.new("SingleSegmentBevel", "BEVEL")
    modifier.width = width
    modifier.segments = 1


def finish_object(obj, name, material, root, bind_bone):
    obj.name = name
    obj.data.name = "MESH_" + name
    obj.parent = root
    obj["bind_bone"] = bind_bone
    if material is not None:
        obj.data.materials.append(material)
    return obj


def add_cube(name, location, dimensions, material, root, bind_bone, bevel=0.02, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_cylinder(name, location, radius, depth, material, root, bind_bone, vertices=8, rotation=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_cone(name, location, radius_bottom, radius_top, depth, material, root, bind_bone, vertices=8, bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        end_fill_type="NGON",
        location=location,
    )
    obj = bpy.context.object
    apply_scale(obj)
    add_bevel(obj, bevel)
    return finish_object(obj, name, material, root, bind_bone)


def add_ico(name, location, dimensions, material, root, bind_bone, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=0.5, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    apply_scale(obj)
    return finish_object(obj, name, material, root, bind_bone)


def add_cylinder_between(name, start, end, radius, material, root, bind_bone, vertices=8, bevel=0.0):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    midpoint = (start + end) * 0.5
    obj = add_cylinder(
        name,
        midpoint,
        radius,
        direction.length,
        material,
        root,
        bind_bone,
        vertices=vertices,
        bevel=bevel,
    )
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return obj


# =============================================================================
# FACIAL BLEND SHAPES
# =============================================================================

def add_expression_shape_keys(obj, transforms):
    basis = obj.shape_key_add(name="Basis")
    original_positions = [point.co.copy() for point in basis.data]

    for expression in EXPRESSIONS:
        settings = transforms.get(expression, {})
        scale = Vector(settings.get("scale", (1.0, 1.0, 1.0)))
        offset = Vector(settings.get("offset", (0.0, 0.0, 0.0)))
        rotation_y = math.radians(float(settings.get("rotation_y", 0.0)))
        rotation = Matrix.Rotation(rotation_y, 4, "Y")
        shape = obj.shape_key_add(name=expression)
        for index, position in enumerate(original_positions):
            scaled = Vector((position.x * scale.x, position.y * scale.y, position.z * scale.z))
            shape.data[index].co = rotation @ scaled + offset


def add_eye_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_scale = (1.30, 1.0, 1.30) if side == "Left" else (0.95, 1.0, 0.38)
    funny_offset = (0.0, 0.0, 0.018) if side == "Left" else (0.0, 0.0, -0.012)
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"scale": (1.10, 1.0, 0.55), "rotation_y": 14.0 * sign, "offset": (0.0, 0.0, -0.010)},
        "Funny": {"scale": funny_scale, "rotation_y": -10.0 * sign, "offset": funny_offset},
        "Happy": {"scale": (1.18, 1.0, 0.35), "rotation_y": -5.0 * sign, "offset": (0.0, 0.0, -0.015)},
        "Worried": {"scale": (0.92, 1.0, 1.15), "rotation_y": -8.0 * sign, "offset": (0.0, 0.0, 0.005)},
    })


def add_brow_expression_shapes(obj, side):
    sign = -1.0 if side == "Left" else 1.0
    funny_height = 0.045 if side == "Left" else -0.025
    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"rotation_y": -22.0 * sign, "offset": (0.0, 0.0, -0.025)},
        "Funny": {"rotation_y": 18.0 * sign, "offset": (0.0, 0.0, funny_height)},
        "Happy": {"rotation_y": 7.0 * sign, "offset": (0.0, 0.0, 0.020)},
        "Worried": {"rotation_y": 22.0 * sign, "offset": (0.0, 0.0, 0.030)},
    })


def add_mouth_expression_shapes(obj, segment):
    if segment == "Left":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, 0.025)
        happy_rotation = -18.0
        worried_rotation = 20.0
    elif segment == "Right":
        happy_offset = (0.0, 0.0, 0.025)
        worried_offset = (0.0, 0.0, -0.030)
        funny_offset = (0.0, 0.0, -0.025)
        happy_rotation = 18.0
        worried_rotation = -20.0
    else:
        happy_offset = (0.0, 0.0, -0.012)
        worried_offset = (0.0, 0.0, 0.018)
        funny_offset = (0.0, 0.0, 0.0)
        happy_rotation = 0.0
        worried_rotation = 0.0

    add_expression_shape_keys(obj, {
        "Calm": {},
        "Fierce": {"scale": (1.05, 1.0, 0.72), "offset": worried_offset, "rotation_y": worried_rotation},
        "Funny": {"scale": (1.0, 1.0, 1.25 if segment == "Center" else 0.85), "offset": funny_offset, "rotation_y": 12.0 if segment != "Center" else 0.0},
        "Happy": {"offset": happy_offset, "rotation_y": happy_rotation},
        "Worried": {"scale": (0.92, 1.0, 0.9), "offset": worried_offset, "rotation_y": worried_rotation},
    })


def add_face(root, mats, cute=False):
    add_cube("Head", (0.0, 0.0, 1.72), (0.45, 0.38, 0.43), mats["skin"], root, "Head", bevel=0.028)

    eye_scale = (0.068, 0.035, 0.086) if cute else (0.058, 0.035, 0.073)
    left_eye = add_ico("LeftEye", (-0.092, -0.202, 1.755), eye_scale, mats["dark"], root, "Head")
    right_eye = add_ico("RightEye", (0.092, -0.202, 1.755), eye_scale, mats["dark"], root, "Head")
    add_eye_expression_shapes(left_eye, "Left")
    add_eye_expression_shapes(right_eye, "Right")

    left_brow = add_cube("LeftBrow", (-0.102, -0.214, 1.852), (0.142, 0.024, 0.030), mats["hair"], root, "Head", bevel=0.006)
    right_brow = add_cube("RightBrow", (0.102, -0.214, 1.852), (0.142, 0.024, 0.030), mats["hair"], root, "Head", bevel=0.006)
    add_brow_expression_shapes(left_brow, "Left")
    add_brow_expression_shapes(right_brow, "Right")

    add_cube("Nose", (0.0, -0.219, 1.676), (0.065, 0.045, 0.064), mats["skin"], root, "Head", bevel=0.012)

    # The Assistant gets an upward mouth line at rest for a cute, friendly pose.
    base_z = {"Left": 1.592, "Center": 1.580, "Right": 1.592} if cute else {"Left": 1.585, "Center": 1.585, "Right": 1.585}
    for segment, x in (("Left", -0.060), ("Center", 0.0), ("Right", 0.060)):
        mouth = add_cube("Mouth" + segment, (x, -0.213, base_z[segment]), (0.068, 0.020, 0.026), mats["dark"], root, "Head", bevel=0.004)
        add_mouth_expression_shapes(mouth, segment)

    tongue = add_cube("FunnyTongue", (0.0, -0.010, 1.550), (0.095, 0.022, 0.070), mats["team"], root, "Head", bevel=0.006)
    add_expression_shape_keys(tongue, {
        "Calm": {}, "Fierce": {}, "Funny": {"offset": (0.0, -0.218, -0.014)}, "Happy": {}, "Worried": {},
    })

    if cute:
        add_ico("LeftCheek", (-0.158, -0.207, 1.652), (0.090, 0.010, 0.045), mats["team"], root, "Head")
        add_ico("RightCheek", (0.158, -0.207, 1.652), (0.090, 0.010, 0.045), mats["team"], root, "Head")


# =============================================================================
# FEMALE LOW-POLY BODY
# =============================================================================

def add_female_body(root, mats, top_material, pants_material, boot_material, sleeve_material=None, cute=False):
    sleeve_material = sleeve_material or top_material

    add_cube("Torso", (0.0, 0.0, 1.19), (0.54, 0.32, 0.62), top_material, root, "Chest", bevel=0.055)
    add_cube("Waist", (0.0, 0.0, 0.91), (0.45, 0.30, 0.16), top_material, root, "Hips", bevel=0.040)

    for side, sign, bone_side in (("Left", -1.0, "R"), ("Right", 1.0, "L")):
        leg_x = 0.145 * sign
        add_cube(side + "Leg", (leg_x, 0.015, 0.57), (0.20, 0.25, 0.56), pants_material, root, "Thigh." + bone_side, bevel=0.033)
        add_cube(side + "Boot", (leg_x, -0.070, 0.165), (0.22, 0.34, 0.23), boot_material, root, "Foot." + bone_side, bevel=0.038)

        shoulder = (0.300 * sign, 0.0, 1.41)
        elbow = (0.465 * sign, 0.0, 1.16)
        wrist = (0.565 * sign, -0.018, 0.97)
        add_cylinder_between(side + "UpperArm", shoulder, elbow, 0.094, sleeve_material, root, "UpperArm." + bone_side, vertices=8)
        add_cylinder_between(side + "Forearm", elbow, wrist, 0.078, mats["skin"], root, "Forearm." + bone_side, vertices=8)
        add_ico(side + "Hand", wrist, (0.150, 0.128, 0.170), mats["skin"], root, "Hand." + bone_side)

    add_face(root, mats, cute=cute)


def add_team_badge(root, mats, y=-0.196, z=1.28):
    # Deliberately offset forward to avoid coplanar overlap with clothes.
    add_cube("TeamBadgeFrame", (0.0, y, z), (0.245, 0.033, 0.18), mats["dark"], root, "Chest", bevel=0.020)
    add_cube("TeamBadge", (0.0, y - 0.027, z), (0.185, 0.020, 0.115), mats["team"], root, "Chest", bevel=0.014)


def add_hair_cap(root, mats, style="long"):
    # cap slightly above / behind the head so it never shares the head surface.
    add_ico("HairCap", (0.0, 0.035, 1.895), (0.49, 0.41, 0.28), mats["hair"], root, "Head")
    if style == "long":
        add_cube("HairBack", (0.0, 0.175, 1.64), (0.39, 0.10, 0.52), mats["hair"], root, "Head", bevel=0.050)
        add_cylinder_between("HairLockLeft", (-0.195, -0.145, 1.86), (-0.225, -0.155, 1.50), 0.050, mats["hair"], root, "Head", vertices=6)
        add_cylinder_between("HairLockRight", (0.195, -0.145, 1.86), (0.225, -0.155, 1.50), 0.050, mats["hair"], root, "Head", vertices=6)
    elif style == "bob":
        add_cube("HairBobBack", (0.0, 0.135, 1.68), (0.42, 0.14, 0.40), mats["hair"], root, "Head", bevel=0.060)
        add_ico("HairBobLeft", (-0.205, -0.08, 1.66), (0.12, 0.14, 0.27), mats["hair"], root, "Head")
        add_ico("HairBobRight", (0.205, -0.08, 1.66), (0.12, 0.14, 0.27), mats["hair"], root, "Head")
    elif style == "ponytail":
        add_ico("Ponytail", (0.0, 0.285, 1.77), (0.28, 0.18, 0.38), mats["hair"], root, "Head")
        add_cylinder("PonytailTie", (0.0, 0.198, 1.80), 0.052, 0.12, mats["team"], root, "Head", vertices=8, rotation=(math.radians(90), 0, 0))
        add_cylinder_between("FrontBangLeft", (-0.10, -0.184, 1.92), (-0.15, -0.205, 1.76), 0.035, mats["hair"], root, "Head", vertices=6)
        add_cylinder_between("FrontBangRight", (0.10, -0.184, 1.92), (0.15, -0.205, 1.76), 0.035, mats["hair"], root, "Head", vertices=6)


# =============================================================================
# ROLE BUILDERS
# =============================================================================

def build_mage(team_name):
    root = create_root("FTF_Character_Mage_" + team_name)
    mats = create_role_materials("Mage", team_name)
    add_female_body(root, mats, mats["primary"], mats["primary"], mats["dark"], sleeve_material=mats["primary"], cute=False)

    # Long robe and belt. The lower robe is attached to Hips so it follows the body.
    add_cone("RobeLower", (0.0, 0.015, 0.58), 0.43, 0.285, 0.86, mats["primary"], root, "Hips", vertices=8, bevel=0.020)
    add_cube("RobeBelt", (0.0, -0.006, 0.94), (0.50, 0.35, 0.105), mats["team"], root, "Hips", bevel=0.020)
    add_cube("RobeFrontPanel", (0.0, -0.183, 0.72), (0.25, 0.030, 0.48), mats["accent"], root, "Hips", bevel=0.017)
    add_cube("RobeCollar", (0.0, -0.175, 1.47), (0.31, 0.040, 0.11), mats["accent"], root, "Chest", bevel=0.018)

    # Wide cuffs give an iconic wizard silhouette without excess detail.
    add_cylinder_between("LeftRobeSleeve", (-0.30, 0.0, 1.40), (-0.465, 0.0, 1.15), 0.118, mats["primary"], root, "UpperArm.R", vertices=8)
    add_cylinder_between("RightRobeSleeve", (0.30, 0.0, 1.40), (0.465, 0.0, 1.15), 0.118, mats["primary"], root, "UpperArm.L", vertices=8)
    add_cylinder("LeftCuff", (-0.505, -0.010, 1.08), 0.112, 0.12, mats["accent"], root, "Forearm.R", vertices=8, rotation=(math.radians(38), 0, math.radians(-28)))
    add_cylinder("RightCuff", (0.505, -0.010, 1.08), 0.112, 0.12, mats["accent"], root, "Forearm.L", vertices=8, rotation=(math.radians(38), 0, math.radians(28)))

    add_hair_cap(root, mats, style="long")
    # Pointed cloth hat: intentionally chunky and short enough for gameplay cameras.
    add_cone("WizardHatCone", (0.0, 0.025, 2.21), 0.24, 0.055, 0.55, mats["primary"], root, "Head", vertices=8, bevel=0.010)
    add_cylinder("WizardHatBrim", (0.0, 0.0, 1.965), 0.34, 0.050, mats["accent"], root, "Head", vertices=10)
    add_cube("HatTeamBand", (0.0, -0.245, 2.085), (0.30, 0.030, 0.075), mats["team"], root, "Head", bevel=0.010)
    add_ico("MagicCharm", (0.0, -0.215, 1.31), (0.11, 0.028, 0.11), mats["team"], root, "Chest")

    add_team_badge(root, mats, y=-0.215, z=1.22)
    return root


def build_apothecary(team_name):
    root = create_root("FTF_Character_Apothecary_" + team_name)
    mats = create_role_materials("Apothecary", team_name)
    add_female_body(root, mats, mats["primary"], mats["skin"], mats["dark"], sleeve_material=mats["primary"], cute=True)

    # Cute short skirt; it ends well above the knee. This is an adult stylized role outfit.
    add_cone("ShortSkirt", (0.0, 0.012, 0.80), 0.36, 0.24, 0.34, mats["primary"], root, "Hips", vertices=8, bevel=0.018)
    add_cube("SkirtTeamHem", (0.0, -0.005, 0.65), (0.58, 0.33, 0.075), mats["team"], root, "Hips", bevel=0.018)
    add_cube("ApronBib", (0.0, -0.185, 1.16), (0.35, 0.040, 0.37), mats["accent"], root, "Chest", bevel=0.030)
    add_cube("ApronPocket", (0.0, -0.214, 1.05), (0.20, 0.018, 0.105), mats["team"], root, "Chest", bevel=0.012)
    add_cube("LeftApronStrap", (-0.145, -0.180, 1.40), (0.055, 0.035, 0.26), mats["accent"], root, "Chest", bevel=0.012)
    add_cube("RightApronStrap", (0.145, -0.180, 1.40), (0.055, 0.035, 0.26), mats["accent"], root, "Chest", bevel=0.012)

    # Short boots with a colored cuff; no realistic fine shoelace details.
    add_cube("LeftBootCuff", (-0.145, -0.055, 0.295), (0.235, 0.28, 0.10), mats["team"], root, "Foot.R", bevel=0.020)
    add_cube("RightBootCuff", (0.145, -0.055, 0.295), (0.235, 0.28, 0.10), mats["team"], root, "Foot.L", bevel=0.020)

    # Three chunky potion bottles, small but readable at gameplay distance.
    for name, x, color in (("PotionLeft", -0.29, mats["accent"]), ("PotionCenter", 0.0, mats["team"]), ("PotionRight", 0.29, mats["accent"])):
        add_cylinder(name + "Bottle", (x, -0.185, 0.94), 0.060, 0.16, color, root, "Hips", vertices=6, bevel=0.008)
        add_cylinder(name + "Stopper", (x, -0.185, 1.045), 0.028, 0.052, mats["dark"], root, "Hips", vertices=6)

    add_hair_cap(root, mats, style="bob")
    add_ico("HairClip", (0.145, -0.205, 1.87), (0.12, 0.022, 0.07), mats["team"], root, "Head")
    add_team_badge(root, mats, y=-0.228, z=1.29)
    return root


def build_assistant(team_name):
    root = create_root("FTF_Character_Assistant_" + team_name)
    mats = create_role_materials("Assistant", team_name)
    add_female_body(root, mats, mats["primary"], mats["accent"], mats["dark"], sleeve_material=mats["primary"], cute=True)

    # Casual practical outfit: cream top, denim jeans, large team-color scarf.
    add_cube("DenimWaistband", (0.0, 0.0, 0.89), (0.46, 0.30, 0.08), mats["accent"], root, "Hips", bevel=0.018)
    add_cube("LeftJeanPatch", (-0.145, -0.143, 0.58), (0.145, 0.025, 0.13), mats["team"], root, "Thigh.R", bevel=0.012)
    add_cube("RightJeanPatch", (0.145, -0.143, 0.58), (0.145, 0.025, 0.13), mats["team"], root, "Thigh.L", bevel=0.012)
    add_cube("ScarfFront", (0.0, -0.205, 1.42), (0.30, 0.045, 0.11), mats["team"], root, "Chest", bevel=0.025)
    add_cube("ScarfTail", (0.205, 0.145, 1.20), (0.10, 0.055, 0.37), mats["team"], root, "Chest", bevel=0.025)
    add_cube("UtilityPouch", (-0.23, -0.175, 0.88), (0.17, 0.10, 0.17), mats["dark"], root, "Hips", bevel=0.025)
    add_ico("PouchButton", (-0.23, -0.235, 0.89), (0.050, 0.018, 0.050), mats["team"], root, "Hips")

    add_hair_cap(root, mats, style="ponytail")
    add_ico("HairBow", (0.0, 0.210, 1.82), (0.22, 0.050, 0.10), mats["team"], root, "Head")
    add_team_badge(root, mats, y=-0.225, z=1.27)
    return root


ROLE_BUILDERS = {
    "Mage": build_mage,
    "Apothecary": build_apothecary,
    "Assistant": build_assistant,
}


# =============================================================================
# RIGGING
# =============================================================================

BONES = {
    "Root": ((0.0, 0.0, 0.02), (0.0, 0.0, 0.25), None, False),
    "Hips": ((0.0, 0.0, 0.25), (0.0, 0.0, 0.76), "Root", False),
    "Spine": ((0.0, 0.0, 0.76), (0.0, 0.0, 1.10), "Hips", True),
    "Chest": ((0.0, 0.0, 1.10), (0.0, 0.0, 1.50), "Spine", True),
    "Neck": ((0.0, 0.0, 1.50), (0.0, 0.0, 1.59), "Chest", True),
    "Head": ((0.0, 0.0, 1.59), (0.0, 0.0, 1.96), "Neck", True),
    # Character faces -Y. Anatomical right is the -X side.
    "UpperArm.R": ((-0.25, 0.0, 1.43), (-0.49, 0.0, 1.15), "Chest", False),
    "Forearm.R": ((-0.49, 0.0, 1.15), (-0.60, 0.0, 0.98), "UpperArm.R", True),
    "Hand.R": ((-0.60, 0.0, 0.98), (-0.62, 0.0, 0.84), "Forearm.R", True),
    "UpperArm.L": ((0.25, 0.0, 1.43), (0.49, 0.0, 1.15), "Chest", False),
    "Forearm.L": ((0.49, 0.0, 1.15), (0.60, 0.0, 0.98), "UpperArm.L", True),
    "Hand.L": ((0.60, 0.0, 0.98), (0.62, 0.0, 0.84), "Forearm.L", True),
    "Thigh.R": ((-0.13, 0.0, 0.76), (-0.17, 0.0, 0.42), "Hips", False),
    "Shin.R": ((-0.17, 0.0, 0.42), (-0.17, 0.0, 0.16), "Thigh.R", True),
    "Foot.R": ((-0.17, 0.0, 0.16), (-0.17, -0.24, 0.11), "Shin.R", False),
    "Thigh.L": ((0.13, 0.0, 0.76), (0.17, 0.0, 0.42), "Hips", False),
    "Shin.L": ((0.17, 0.0, 0.42), (0.17, 0.0, 0.16), "Thigh.L", True),
    "Foot.L": ((0.17, 0.0, 0.16), (0.17, -0.24, 0.11), "Shin.L", False),
}


def create_armature(root):
    armature_data = bpy.data.armatures.new("CharacterSkeleton")
    armature = bpy.data.objects.new("CharacterSkeleton", armature_data)
    bpy.context.collection.objects.link(armature)
    armature.parent = root
    armature.show_in_front = True
    armature.data.display_type = "OCTAHEDRAL"

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = {}
    for name, (head, tail, parent_name, connected) in BONES.items():
        bone = armature.data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = name != "Root"
        edit_bones[name] = bone
        if parent_name:
            bone.parent = edit_bones[parent_name]
            bone.use_connect = connected
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def bind_mesh_rigid(mesh, armature):
    world_matrix = mesh.matrix_world.copy()
    mesh.parent = None
    mesh.matrix_world = world_matrix
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            mesh.modifiers.remove(modifier)
    mesh.vertex_groups.clear()

    bone_name = mesh.get("bind_bone", "Chest")
    if bone_name not in armature.data.bones:
        raise RuntimeError(f"Unknown bind bone {bone_name} for {mesh.name}")
    group = mesh.vertex_groups.new(name=bone_name)
    group.add(list(range(len(mesh.data.vertices))), 1.0, "REPLACE")
    modifier = mesh.modifiers.new(name="CharacterSkeleton", type="ARMATURE")
    modifier.object = armature
    modifier.use_vertex_groups = True
    mesh.parent = armature
    mesh["bound_bone"] = bone_name


def rig_character(root):
    armature = create_armature(root)
    meshes = [child for child in root.children if child.type == "MESH"]
    for mesh in meshes:
        bind_mesh_rigid(mesh, armature)
    root["rig_type"] = "rigid_low_poly_humanoid"
    root["skeleton_bones"] = len(BONES)
    root["animation_ready"] = True
    return armature, meshes


# =============================================================================
# ANIMATION CREATION
# =============================================================================

def reset_pose(armature):
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def point_bone_between(bone, start, end):
    direction = Vector(end) - Vector(start)
    if direction.length_squared < 0.000001:
        return
    rotation = direction.normalized().to_track_quat("Y", "Z").to_matrix().to_4x4()
    bone.matrix = Matrix.Translation(Vector(start)) @ rotation


def solve_right_arm(armature, target, bend_hint):
    bpy.context.view_layer.update()
    upper = armature.pose.bones["UpperArm.R"]
    forearm = armature.pose.bones["Forearm.R"]
    shoulder = upper.head.copy()
    wrist = Vector(target)
    to_target = wrist - shoulder
    distance = max(0.0001, to_target.length)
    length_upper = upper.bone.length
    length_forearm = forearm.bone.length
    max_reach = (length_upper + length_forearm) * 0.985
    if distance > max_reach:
        wrist = shoulder + to_target.normalized() * max_reach
        to_target = wrist - shoulder
        distance = max_reach

    axis = to_target.normalized()
    along = (length_upper * length_upper - length_forearm * length_forearm + distance * distance) / (2.0 * distance)
    height = math.sqrt(max(0.0, length_upper * length_upper - along * along))
    bend = Vector(bend_hint)
    perpendicular = bend - axis * bend.dot(axis)
    if perpendicular.length_squared < 0.000001:
        perpendicular = Vector((1.0, 0.0, 0.0))
    perpendicular.normalize()
    elbow = shoulder + axis * along + perpendicular * height

    point_bone_between(upper, shoulder, elbow)
    bpy.context.view_layer.update()
    point_bone_between(forearm, elbow, wrist)
    bpy.context.view_layer.update()


def insert_full_pose(armature, frame, transforms):
    reset_pose(armature)
    for bone_name, transform in transforms.items():
        if bone_name.startswith("__"):
            continue
        bone = armature.pose.bones.get(bone_name)
        if bone is None:
            continue
        if "rot" in transform:
            bone.rotation_euler = transform["rot"]
        if "loc" in transform:
            bone.location = transform["loc"]
    if "__right_arm_ik" in transforms:
        ik = transforms["__right_arm_ik"]
        solve_right_arm(armature, ik["target"], ik["bend"])
    for bone in armature.pose.bones:
        if bone.name == "Root":
            continue
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)


def create_actions(armature):
    armature.animation_data_create()
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)

    for old_action in list(bpy.data.actions):
        bpy.data.actions.remove(old_action)

    for name, spec in ANIMATIONS.items():
        action = bpy.data.actions.new(name=name)
        armature.animation_data.action = action
        for frame, transforms in spec["keys"]:
            insert_full_pose(armature, frame, transforms)
        action["loop"] = spec["loop"]
        action["fps"] = FPS
        action.use_fake_user = True

        for fcurve in action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "BEZIER"

        # Separate NLA track per action. Matches the prior pipeline's GLB export mode.
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.action_frame_start = 1.0
        strip.action_frame_end = float(spec["end"])

    armature.animation_data.action = None
    reset_pose(armature)


# =============================================================================
# VALIDATION / EXPORT
# =============================================================================

def iter_hierarchy(root):
    yield root
    for child in root.children:
        yield from iter_hierarchy(child)


def validate_character(root, armature, meshes):
    failures = []
    if root.type != "EMPTY":
        failures.append("root must be Empty")
    if len([obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]) != 1:
        failures.append("expected exactly one armature in build scene")
    if len(armature.data.bones) != len(BONES):
        failures.append("unexpected skeleton bone count")

    for obj in meshes:
        upper_name = obj.name.upper()
        if upper_name.startswith(("UCX_", "MESH_UCX_")):
            failures.append("collision mesh: " + obj.name)
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001:
            failures.append("zero scale: " + obj.name)
        if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0:
            failures.append("negative scale: " + obj.name)
        if "." in obj.name:
            failures.append("generated non-semantic suffix: " + obj.name)
        if obj.get("bound_bone") not in armature.data.bones:
            failures.append("missing valid rigid bind: " + obj.name)
        for vertex in obj.data.vertices:
            co = obj.matrix_world @ vertex.co
            if not all(math.isfinite(value) for value in co):
                failures.append("non-finite vertex: " + obj.name)
                break

    if failures:
        raise RuntimeError("; ".join(failures))

    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)
    attached_materials = {mat.name for mesh in meshes for mat in mesh.data.materials if mat}
    expression_meshes = [mesh for mesh in meshes if mesh.data.shape_keys]
    if not expression_meshes:
        raise RuntimeError("No blend-shape facial meshes found")
    for mesh in expression_meshes:
        names = {block.name for block in mesh.data.shape_keys.key_blocks}
        if not set(EXPRESSIONS).issubset(names):
            raise RuntimeError(f"Missing facial expressions on {mesh.name}: {sorted(set(EXPRESSIONS) - names)}")

    print(
        f"VALID {root.name}: meshes={len(meshes)}, materials={len(attached_materials)}, "
        f"triangles={triangles}, bones={len(armature.data.bones)}, expression_meshes={len(expression_meshes)}"
    )


def export_character(root, output_path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in iter_hierarchy(root):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        # Keep the non-deforming Root bone in the GLB. With export_def_bones=True
        # Blender 4.4 filters it out, because Root.use_deform is False. That leads
        # to a 17-bone import even though the authored rig has 18 bones.
        export_def_bones=False,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
    )


def action_matches(imported_actions, wanted_name):
    direct = next((action for action in imported_actions if action.name == wanted_name), None)
    if direct:
        return direct
    return next((action for action in imported_actions if action.name.endswith(wanted_name)), None)


def verify_export(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    collision_meshes = [obj.name for obj in meshes if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))]
    zero_scale = [obj.name for obj in meshes if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001]
    negative_scale = [obj.name for obj in meshes if obj.scale.x < 0.0 or obj.scale.y < 0.0 or obj.scale.z < 0.0]
    actions = list(bpy.data.actions)
    missing_actions = [name for name in ANIMATIONS if action_matches(actions, name) is None]

    expression_meshes = []
    incomplete_expressions = []
    for mesh in meshes:
        if mesh.data.shape_keys is None:
            continue
        names = {block.name for block in mesh.data.shape_keys.key_blocks if block.name != "Basis"}
        if names:
            expression_meshes.append(mesh.name)
            if not set(EXPRESSIONS).issubset(names):
                incomplete_expressions.append(mesh.name)

    # The exported GLB must retain all authored bones, including the non-deforming
    # Root bone. This is why export_character uses export_def_bones=False.
    if (
        len(armatures) != 1
        or len(armatures[0].data.bones) != len(BONES)
        or collision_meshes
        or zero_scale
        or negative_scale
        or missing_actions
        or not expression_meshes
        or incomplete_expressions
    ):
        raise RuntimeError(
            f"Invalid GLB {path}: armatures={len(armatures)}, bones="
            f"{len(armatures[0].data.bones) if armatures else 0}, collision={collision_meshes}, "
            f"zero={zero_scale}, negative={negative_scale}, missing_actions={missing_actions}, "
            f"expression_meshes={expression_meshes}, incomplete_expressions={incomplete_expressions}"
        )

    print(
        f"REIMPORT OK {os.path.basename(path)}: meshes={len(meshes)}, bones={len(armatures[0].data.bones)}, "
        f"actions={len(actions)}, expression_meshes={len(expression_meshes)}"
    )


# =============================================================================
# POSE RENDER CHECKS
# =============================================================================

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_lighting_and_camera():
    bpy.ops.mesh.primitive_plane_add(size=7.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_mat = make_material("MAT_PreviewGround", "#19241F", roughness=0.96)
    ground.data.materials.append(ground_mat)

    bpy.ops.object.camera_add(location=(3.45, -5.30, 2.75))
    camera = bpy.context.object
    look_at(camera, (0.0, 0.0, 1.10))
    bpy.context.scene.camera = camera

    for name, location, energy, size in (
        ("Key", (-3.0, -4.0, 5.0), 950.0, 4.0),
        ("Fill", (4.0, -1.0, 3.4), 620.0, 3.0),
        ("Rim", (1.0, 3.2, 4.2), 460.0, 2.5),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, (0.0, 0.0, 1.0))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.012, 0.018, 0.025)


def render_pose_checks(glb_path, output_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    add_preview_lighting_and_camera()

    role_stem = os.path.splitext(os.path.basename(glb_path))[0]
    pose_dir = os.path.join(output_dir, "pose_checks", role_stem)
    os.makedirs(pose_dir, exist_ok=True)
    imported_actions = list(bpy.data.actions)

    # Disable NLA influence for a deterministic direct action preview.
    armature.animation_data_create()
    for track in armature.animation_data.nla_tracks:
        track.mute = True

    for action_name, frame in POSE_CHECKS.items():
        action = action_matches(imported_actions, action_name)
        if action is None:
            raise RuntimeError(f"Cannot render missing action {action_name} from {glb_path}")
        armature.animation_data.action = action
        bpy.context.scene.frame_set(frame)
        bpy.context.scene.render.filepath = os.path.join(pose_dir, action_name + ".png")
        bpy.ops.render.render(write_still=True)
        print(f"POSECHECK {role_stem} {action_name}: {bpy.context.scene.render.filepath}")


# =============================================================================
# BUILD / MAIN
# =============================================================================

def build_export_validate_variant(role_name, team_name, output_dir, render_checks):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ensure_metric_scene()
    root = ROLE_BUILDERS[role_name](team_name)
    armature, meshes = rig_character(root)
    create_actions(armature)
    validate_character(root, armature, meshes)

    output_path = os.path.join(output_dir, f"FTF_Character_{role_name}_{team_name}_Rigged.glb")
    export_character(root, output_path)
    print("EXPORTED", output_path)

    verify_export(output_path)
    if render_checks:
        render_pose_checks(output_path, output_dir)
    return output_path


def main():
    args = parse_args()
    output_dir = os.path.abspath(args.output)
    os.makedirs(output_dir, exist_ok=True)

    output_paths = []
    for role_name in ("Mage", "Apothecary", "Assistant"):
        for team_name in ("Red", "Blue"):
            output_paths.append(
                build_export_validate_variant(
                    role_name,
                    team_name,
                    output_dir,
                    render_checks=RENDER_POSE_CHECKS and not args.skip_pose_renders,
                )
            )

    print("DONE: generated %d animated character GLBs in %s" % (len(output_paths), output_dir))


if __name__ == "__main__":
    main()
