# Project Specification

## Links

- **Repository:** https://github.com/IndaPlus25/ponord-arvwes-teslenko-project
- **Project board:** https://github.com/orgs/IndaPlus25/projects/9/views/1

## Project Description

We are building a software rasterizer from scratch using low-level dependencies, specifically *SDL3* for window management and pixel buffer access. The goal is to implement the entire graphics pipeline in software, without relying on GPU APIs like OpenGL or Vulkan.

### MVP (Model Renderer)

Our minimum viable product is a 3D model renderer capable of:

- Loading and parsing 3D model files (e.g. OBJ)
- Triangle rasterization
- Depth buffering (Z-buffer)
- Basic shading
- Camera controls

# Our goal

If we have time to, we would like to use non-Euclidean geometry within our rasterizer, drawing inspiration from hyperbolic and/or spherical spaces.

## Feasibility/weekly plan
I think the project is feasible given the following timeline. The core rasterization pipeline is well-documented, and it's something that at least one of us has done before. The "stretch goal" is independent of the core MVP, so it won't block progress.

| Week | Focus |
|------|-------|
| 1 | Project setup, SDL3 window + framebuffer, basic 2D line/triangle drawing |
| 2 | Math utilities (vectors, matrices), vertex transformations, wireframe rendering |
| 3 | Triangle rasterization, Z-buffer, OBJ loading |
| 4 | Shading, camera controls, basic lighting |
| 5 | Polish, performance tuning, bug fixes |
| 6+ | Stretch: non-Euclidean geometry experiments |

## Division of work (subject to change)

| Member | Responsibility |
|--------|---------------|
| Pontus Nordström | Engine/SDL3/Testing |
| Arvid Westman | Engine/UI |
| Michael Teslenko | UI/Environments |

> Note that we expect overlap and collaboration throughout the project, these roles are not set in stone.
