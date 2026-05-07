const std = @import("std");
const app = @import("app.zig");
const render = @import("render.zig");
const c = @import("platform/c.zig").c;

pub const UiState = struct {
    graph_samples: usize = 120,
};

pub fn initImGui(window: *c.SDL_Window, renderer: *c.SDL_Renderer) *c.ImGuiContext {
    const context = c.ImGui_CreateContext(null).?;
    const io = c.ImGui_GetIO();
    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.IniFilename = "./src/config/imgui.ini";
    _ = c.cImGui_ImplSDL3_InitForSDLRenderer(window, renderer);
    _ = c.cImGui_ImplSDLRenderer3_Init(renderer);
    return context;
}

pub fn deinitImGui(context: *c.ImGuiContext) void {
    c.cImGui_ImplSDLRenderer3_Shutdown();
    c.cImGui_ImplSDL3_Shutdown();
    c.ImGui_DestroyContext(context);
}

pub fn renderImGui(
    texture: *c.SDL_Texture,
    frame_times: *[app.frame_time_sample_count]f32,
    triangles: struct { u64, u64, u64 },
    world_camera: *render.Camera,
    app_state: *app.AppState,
    viewport_settings: *app.ViewportSettings,
) app.DesiredFramebufferSize {
    c.cImGui_ImplSDLRenderer3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    _ = c.ImGui_DockSpaceOverViewport();

    var desired_w: c_int = 1;
    var desired_h: c_int = 1;

    // Viewport stuff
    if (c.ImGui_Begin("Viewport", null, 0)) {
        if (c.ImGui_IsWindowHovered(0) and c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left)) {
            app_state.mouse_captured = true;
        }

        const avail = c.ImGui_GetContentRegionAvail();

        if (viewport_settings.fixed_res) {
            desired_w = viewport_settings.fixed_width;
            desired_h = viewport_settings.fixed_height;
        } else {
            desired_w = @max(1, @as(c_int, @intFromFloat(avail.x * viewport_settings.render_scale)));
            desired_h = @max(1, @as(c_int, @intFromFloat(avail.y * viewport_settings.render_scale)));
        }

        // Letterbox in fixed res mode
        const aspect = @as(f32, @floatFromInt(desired_w)) / @as(f32, @floatFromInt(desired_h));
        var image_size = avail;

        // Clamp
        if (image_size.x / image_size.y > aspect) {
            image_size.x = image_size.y * aspect;
        } else {
            image_size.y = image_size.x / aspect;
        }

        c.ImGui_Image(c.struct_ImTextureRef_t{
            ._TexData = null,
            ._TexID = @intFromPtr(texture),
        }, image_size);
    }
    c.ImGui_End();

    if (c.ImGui_Begin("Camera Settings", null, 0)) {
        if (c.ImGui_CollapsingHeader("Position", c.ImGuiTreeNodeFlags_DefaultOpen)) {
            _ = c.ImGui_InputFloat("X", &world_camera.position.x);
            _ = c.ImGui_InputFloat("Y", &world_camera.position.y);
            _ = c.ImGui_InputFloat("Z", &world_camera.position.z);
        }

        if (c.ImGui_CollapsingHeader("Rotation", c.ImGuiTreeNodeFlags_DefaultOpen)) {
            _ = c.ImGui_InputFloat("Yaw", &world_camera.yaw);
            _ = c.ImGui_InputFloat("Pitch", &world_camera.pitch);
        }

        if (c.ImGui_CollapsingHeader("Movement", c.ImGuiTreeNodeFlags_DefaultOpen)) {
            _ = c.ImGui_InputFloat("Move Speed", &world_camera.move_speed);
            _ = c.ImGui_InputFloat("Sensitivity", &world_camera.sensitivity);
        }

        if (c.ImGui_CollapsingHeader("Projection", c.ImGuiTreeNodeFlags_DefaultOpen)) {
            _ = c.ImGui_InputFloat("FOV", &world_camera.fov);
            _ = c.ImGui_InputFloat("Near Plane", &world_camera.near);
            _ = c.ImGui_InputFloat("Far Plane", &world_camera.far);
        }

        if (c.ImGui_CollapsingHeader("Post Processing", c.ImGuiTreeNodeFlags_DefaultOpen)) {
            _ = c.ImGui_Checkbox("Fixed N64 Res", &viewport_settings.fixed_res);
            _ = c.ImGui_InputFloat("Render Scale", &viewport_settings.render_scale);
        }
    }
    c.ImGui_End();

    if (c.ImGui_Begin("Performance Metrics", null, 0)) {
        const avg_delay = @reduce(.Add, @as(@Vector(app.frame_time_sample_count, f32), frame_times.*)) / app.frame_time_sample_count;
        const fps = 1000.0 / avg_delay;

        c.ImGui_Text("FPS: %.1f", fps);
        c.ImGui_Text("Frame Time: %.2f ms", frame_times.*[app.frame_time_sample_count - 1]);

        c.ImGui_Separator();

        c.ImGui_PlotLines("Frame Times", frame_times, app.frame_time_sample_count);
        c.ImGui_Text("Avg Frame Time: %.2f ms", avg_delay);
    }
    c.ImGui_End();

    if (c.ImGui_Begin("Render Metrics", null, 0)) {
        c.ImGui_Text("Total Triangles: %d", triangles[0]);
        c.ImGui_Text("Drawn Triangles: %d", triangles[1]);
        c.ImGui_Text("Clipped Triangles: %d", triangles[2]);
    }
    c.ImGui_End();

    if (c.ImGui_Begin("Input Information", null, 0)) {
        c.ImGui_Text("Yaw:   %.2f", world_camera.yaw);
        c.ImGui_Text("Pitch: %.2f", world_camera.pitch);
        _ = c.ImGui_Checkbox("Mouse Captured", &app_state.mouse_captured);
    }
    c.ImGui_End();

    c.ImGui_Render();

    return .{
        .width = desired_w,
        .height = desired_h,
    };
}
