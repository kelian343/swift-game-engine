FbxToStaticMeshJson

Offline conversion pipeline for FBX static meshes.

Usage
1) Export static mesh JSON from FBX (Blender headless):
   blender -b -P export_static_mesh_json.py -- /Users/karpellus/Desktop/Game/ExternalResources/17-Cheese.fbx /Users/karpellus/Desktop/Game/Game/17-Cheese.static.json

Notes
- Each FBX mesh becomes a separate entry in "meshes" with its own transform.
- Vertex data is stored in the mesh's local space; transform preserves the original placement.
