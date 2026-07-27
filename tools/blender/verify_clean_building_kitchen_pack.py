import bpy
import os
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

FILES = [
    os.path.join(PROJECT_ROOT, "assets", "buildings", filename)
    for filename in (
        "FTF_Building_Wall_2m.glb",
        "FTF_Building_Door_2m.glb",
        "FTF_Building_Window_2m.glb",
        "FTF_Building_Roof_2m.glb",
    )
]

FILES += [
    os.path.join(PROJECT_ROOT, "assets", "kitchen", filename)
    for filename in (
        "FTF_Kitchen_Chopping_Station_Red.glb",
        "FTF_Kitchen_Chopping_Station_Blue.glb",
        "FTF_Kitchen_Chopping_Station_Green.glb",
        "FTF_Kitchen_Chopping_Station_Yellow.glb",
        "FTF_Kitchen_Oven_Red.glb",
        "FTF_Kitchen_Oven_Blue.glb",
        "FTF_Kitchen_Oven_Green.glb",
        "FTF_Kitchen_Oven_Yellow.glb",
        "FTF_Kitchen_Pot_Red.glb",
        "FTF_Kitchen_Pot_Blue.glb",
        "FTF_Kitchen_Pot_Green.glb",
        "FTF_Kitchen_Pot_Yellow.glb",
        "FTF_Kitchen_Double_Door_Freezer_Blue.glb",
        "FTF_Kitchen_Induction_Counter_Red.glb",
        "FTF_Kitchen_Induction_Counter_Blue.glb",
        "FTF_Kitchen_Sink_Red.glb",
        "FTF_Kitchen_Sink_Blue.glb",
        "FTF_Kitchen_Cleaver.glb",
    )
]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


failed = False
for path in FILES:
    if not os.path.isfile(path):
        print("MISSING", path)
        failed = True
        continue

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    collision = [
        obj.name
        for obj in meshes
        if obj.name.upper().startswith(("UCX_", "MESH_UCX_"))
        or obj.get("ftf_role") == "collision"
    ]
    zero_scale = [
        obj.name
        for obj in meshes
        if min(abs(obj.scale.x), abs(obj.scale.y), abs(obj.scale.z)) < 0.000001
    ]
    failed = failed or bool(collision) or bool(zero_scale)
    print(
        f"VERIFY {os.path.basename(path)} meshes={len(meshes)} "
        f"collision={collision} zero_scale={zero_scale}"
    )

print(f"VERIFIED {len(FILES)} FILES result={'FAILED' if failed else 'OK'}")
sys.exit(1 if failed else 0)
