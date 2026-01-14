FbxToSkinnedJson

Offline conversion pipeline for FBX skinned meshes.

Usage
1) Export skinned mesh JSON from FBX (Blender headless):
   blender -b -P export_skinned_json.py -- /Users/karpellus/Desktop/Game/ExternalResources/Y\ Bot.fbx /Users/karpellus/Desktop/Game/Game/YBot.skinned.json

Notes
- export_gltf.py and convert_gltf_to_skinned_json.py remain available if you prefer the glTF pipeline.
