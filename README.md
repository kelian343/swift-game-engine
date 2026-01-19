# Swift Game Engine (Metal)

基于 Metal 的 Swift 游戏引擎原型，包含光线追踪计算路径与传统光栅路径，围绕 RenderGraph 组织离屏渲染、合成与 UI 叠加，并配套程序化网格、材质、动画姿态与碰撞系统。

![Demo Screenshot](ExternalResources/Screenshot%202026-01-19%20at%208.24.27%E2%80%AFPM.png)

演示视频：`ExternalResources/Screen Recording 2026-01-19 at 8.25.26 PM.mov`

## 主要特性
- 金属渲染：RT 计算路径 + Raster 路径，共用命令缓冲区
- RenderGraph：驱动离屏 RT 输出、合成到 drawable、UI 叠加
- 程序化网格：描述符驱动顶点/索引流，支持静态与动态更新
- 程序化材质：PBR 贴图生成与参数统一描述
- 程序化姿态：骨架/姿态组件 + MotionProfile JSON 动画
- 碰撞与角色：胶囊体 CCD、网格碰撞、move-and-slide
- 离线工具链：FBX -> Mesh/Material/MotionProfile JSON

## 目录结构
- `Game/` 运行时代码与渲染/物理/动画系统
- `Tools/` 离线转换工具（Blender/Python）
- `ExternalResources/` FBX 源资源与演示媒体（仅用于离线拟合与展示）
- `Game.xcodeproj/` Xcode 工程

## 构建与运行
1. 使用 Xcode 打开 `Game.xcodeproj`
2. 选择 `Game` scheme
3. 运行到 macOS 目标（需支持 Metal）

## 离线资产流程（可选）
- `Tools/FitMotion/`：FBX -> MotionProfile JSON
- `Tools/FbxToSkinnedJson/`：FBX -> Skinned Mesh JSON
- `Tools/FbxToMaterialJson/`：FBX -> Materials JSON
- `Tools/FbxToStaticMeshJson/`：FBX -> Static Mesh + Collision JSON

## 说明
- 渲染与运行时系统使用 JSON 资产格式（网格/材质/骨架/动画）。
- `ExternalResources/` 中的 FBX 仅供离线工具使用，运行时不直接解析 FBX。

## 相关更新摘要
- 2025-01-14：新增 Blender 导出工具与 JSON 驱动材质/骨架/网格加载
- 2026-03-09：新增静态网格与碰撞导出工具、分部件材质与性能统计
