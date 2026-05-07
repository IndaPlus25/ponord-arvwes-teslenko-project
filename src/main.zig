// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT
const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");
const objects = @import("objects.zig");

const Object = objects.Object;

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("dcimgui.h");
    @cInclude("dcimgui_impl_sdl3.h");
    @cInclude("dcimgui_impl_sdlrenderer3.h");
});

const screen_width: c_int = 1920;
const screen_height: c_int = 1080;
const screen_title: [*c]const u8 = "working-title";

const graph_samples: usize = 120; // Amount of data points to display in graphs

const SdlContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    fb_width: c_int,
    fb_height: c_int,

    pub fn deinit(self: SdlContext) void {
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }

    pub fn resizeFramebuffer(self: *SdlContext, new_w: c_int, new_h: c_int) !void {
        if (new_w == self.fb_width and new_h == self.fb_height) return;
        c.SDL_DestroyTexture(self.texture);
        const new_tex = c.SDL_CreateTexture(
            self.renderer,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            new_w,
            new_h,
        ) orelse return error.SdlCreateTextureFailed;
        _ = c.SDL_SetTextureScaleMode(new_tex, c.SDL_SCALEMODE_NEAREST);
        self.texture = new_tex;
        self.fb_width = new_w;
        self.fb_height = new_h;
    }
};

const AppState = struct {
    is_running: bool = true,
    mouse_captured: bool = true,
};

const ViewportSettings = struct {
    render_scale: f32 = 0.25,
};

fn initSdl(fb_w: c_int, fb_h: c_int) !SdlContext {
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlInitFailed;
    }
    errdefer c.SDL_Quit();

    if (!c.SDL_CreateWindowAndRenderer(screen_title, screen_width, screen_height, 0, &window, &renderer)) {
        std.debug.print("SDL_CreateWindowAndRenderer failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlWindowCreationFailed;
    }

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        fb_w,
        fb_h,
    ) orelse {
        std.debug.print("SDL_CreateTexture failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlCreateTextureFailed;
    };

    _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

    return SdlContext{
        .window = window.?,
        .renderer = renderer.?,
        .texture = texture,
        .fb_width = fb_w,
        .fb_height = fb_h,
    };
}

fn initImGui(window: *c.SDL_Window, renderer: *c.SDL_Renderer) *c.ImGuiContext {
    const context = c.ImGui_CreateContext(null).?;
    const io = c.ImGui_GetIO();
    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.IniFilename = "./src/config/imgui.ini"; // This makes the program both load and save the config automatically. TODO: Look into removing auto save of the config
    _ = c.cImGui_ImplSDL3_InitForSDLRenderer(window, renderer);
    _ = c.cImGui_ImplSDLRenderer3_Init(renderer);
    return context;
}

fn deinitImGui(context: *c.ImGuiContext) void {
    c.cImGui_ImplSDLRenderer3_Shutdown();
    c.cImGui_ImplSDL3_Shutdown();
    c.ImGui_DestroyContext(context);
}

fn processEvents(app_state: *AppState, world_camera: *render.Camera) void {
    var event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&event)) {
        _ = c.cImGui_ImplSDL3_ProcessEvent(&event);

        // Capture mouse input
        if (app_state.mouse_captured) {
            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                world_camera.yaw += event.motion.xrel * world_camera.sensitivity;
                world_camera.pitch -= event.motion.yrel * world_camera.sensitivity;

                const cutoff = std.math.pi / 2.0 - 0.01; // Dont divide by zero
                world_camera.pitch = std.math.clamp(world_camera.pitch, -cutoff, cutoff); // Clamp
                world_camera.yaw = @mod(world_camera.yaw, std.math.tau); // tau = 2pi
            }
            if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_ESCAPE) {
                app_state.mouse_captured = false;
            }
        }

        // Terminate window
        if (event.type == c.SDL_EVENT_QUIT) {
            app_state.is_running = false;
        }
    }
}

fn updateMovement(world_camera: *render.Camera, delta: f32) void {
    const keys = c.SDL_GetKeyboardState(null);

    // Same matrices as forward just without pitch since y = 0
    const move_forward = math.Vec3{
        .x = @sin(world_camera.yaw),
        .y = 0,
        .z = -@cos(world_camera.yaw),
    };
    const move_right = math.Vec3{
        .x = @cos(world_camera.yaw),
        .y = 0,
        .z = @sin(world_camera.yaw),
    };

    // Horizontal movement
    var velocity = math.Vec3{ .x = 0, .y = 0, .z = 0 };
    if (keys[c.SDL_SCANCODE_W]) velocity = velocity.add(move_forward);
    if (keys[c.SDL_SCANCODE_S]) velocity = velocity.sub(move_forward);
    if (keys[c.SDL_SCANCODE_D]) velocity = velocity.add(move_right);
    if (keys[c.SDL_SCANCODE_A]) velocity = velocity.sub(move_right);

    // Normalize horizontal movement so W+D isn't sqr(2) faster
    if (velocity.len() > 0.0) {
        velocity = velocity.norm();
    }

    // Vertical movement
    if (keys[c.SDL_SCANCODE_SPACE]) velocity.y += 1;
    if (keys[c.SDL_SCANCODE_LSHIFT]) velocity.y -= 1;

    // Apply movement
    world_camera.position = world_camera.position.add(velocity.mul(world_camera.move_speed * delta));
}

// TODO: Look into if there's a better solution than this...
// We need depth bias to avoid z-fighting in these textures
const depth_bias: f32 = 0.004;
fn texDepthBias(texture_id: usize) f32 {
    return switch (texture_id) {
        8, 32, 36, 37 => depth_bias,
        else => 0.0,
    };
}

// TODO: Is there a better way than hardcoded stuff for this too?
// This is for the road color tint
fn texShouldTintRoad(texture_id: usize) bool {
    return switch (texture_id) {
        8, 36, 37 => true,
        else => false,
    };
}

fn renderScene(
    fb: render.FrameBuffer,
    zb: *render.ZBuffer,
    object_list: *std.ArrayList(Object),
    world_camera: *render.Camera,
) struct { u64, u64, u64 } {
    fb.clear();

    // Construct the camera's forward direction (spherical coordinates, y is polar axis)
    const forward = math.Vec3{
        .x = @cos(world_camera.pitch) * @sin(world_camera.yaw),
        .y = @sin(world_camera.pitch),
        .z = -@cos(world_camera.pitch) * @cos(world_camera.yaw),
    };
    // Point camera at position + forward direction
    const target = world_camera.position.add(forward);

    // Aspect ratio to avoid stretching the image in perspective matrix
    const aspect = @as(f32, @floatFromInt(fb.width)) / @as(f32, @floatFromInt(fb.height));

    // Construct the matrices to transform world space into clip space
    const proj_matrix = math.Mat4.perspective(world_camera.fov, aspect, world_camera.near, world_camera.far);
    const view_matrix = math.Mat4.viewMatrix(world_camera.position, target, world_camera.up);

    // Combine the two into one matrix so each vertex only needs one matrix multiplication
    // (World to view to clip space)
    const vp = proj_matrix.mul(view_matrix);

    var total_triangles: u64 = 0;
    var drawn_triangles: u64 = 0;
    var clipped_triangles: u64 = 0;

    // Loop over all the objects & then every triangle in the object
    for (object_list.*.items) |object| {
        // TEMP: capture tri_index for random colors, remove this when adding textures
        for (object.triangles.items, 0..) |tri_v, tri_index| {
            total_triangles += 1;

            var ca = [4]?math.Vec4{ // Array of vertexes
                vp.mulVec4(tri_v[0]),
                vp.mulVec4(tri_v[1]),
                vp.mulVec4(tri_v[2]),
                null, // Incase the near face clipping gives us a fourth vertex (quad)
            };

            var cu = [4]?math.Vec2{
                object.triangle_uvs.items[tri_index][0],
                object.triangle_uvs.items[tri_index][1],
                object.triangle_uvs.items[tri_index][2],
                null,
            };

            var cn: usize = 3; // Amount of vertexes that we have
            var did_clip: bool = false; // Whether or not any triangles have been clipped

            if (ca[0].?.w <= world_camera.near or ca[1].?.w <= world_camera.near or ca[2].?.w <= world_camera.near) {
                const x = render.nearPlaneClip(ca, cu, world_camera.near);
                ca = x[0];
                cu = x[1];
                cn = x[2];
                did_clip = true;
            }
            if (cn < 3) continue; // Only continue if we have 3 or more vertexes

            const v1 = ca[0].?.toPixel(fb.width, fb.height);
            const v2 = ca[1].?.toPixel(fb.width, fb.height);
            const v3 = ca[2].?.toPixel(fb.width, fb.height);

            const uv1 = cu[0].?;
            const uv2 = cu[1].?;
            const uv3 = cu[2].?;

            // Skip triangles facing away
            if (render.facingAway(v1, v2, v3)) continue;

            const tex_id: usize = @intCast(object.triangle_groups.items[tri_index]);
            const tb = object.textures.items[tex_id];

            const db = texDepthBias(tex_id);
            const should_tint_grayscale = texShouldTintRoad(tex_id);

            render.fillTriangle(v1, v2, v3, uv1, uv2, uv3, fb, zb, tb, db, should_tint_grayscale);

            if (cn == 4) {
                const v4 = ca[3].?.toPixel(fb.width, fb.height);
                const uv4 = cu[3].?;

                render.fillTriangle(v1, v3, v4, uv1, uv3, uv4, fb, zb, tb, db, should_tint_grayscale);
                drawn_triangles += 1;
            }

            drawn_triangles += 1;
            if (did_clip) clipped_triangles += cn - 2;
        }
    }

    return .{ total_triangles, drawn_triangles, clipped_triangles };
}

fn renderImGui(
    texture: *c.SDL_Texture,
    frame_times: *[graph_samples]f32,
    triangles: struct { u64, u64, u64 },
    world_camera: *render.Camera,
    app_state: *AppState,
    viewport_settings: *ViewportSettings,
) struct { c_int, c_int } {
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
        desired_w = @max(1, @as(c_int, @intFromFloat(avail.x * viewport_settings.render_scale)));
        desired_h = @max(1, @as(c_int, @intFromFloat(avail.y * viewport_settings.render_scale)));

        c.ImGui_Image(c.struct_ImTextureRef_t{
            ._TexData = null,
            ._TexID = @intFromPtr(texture),
        }, avail);
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
            _ = c.ImGui_InputFloat("Render Scale", &viewport_settings.render_scale);
        }
    }
    c.ImGui_End();

    if (c.ImGui_Begin("Performance Metrics", null, 0)) {
        const avg_delay = @reduce(.Add, @as(@Vector(graph_samples, f32), frame_times.*)) / graph_samples;
        const fps = 1000.0 / avg_delay;

        c.ImGui_Text("FPS: %.1f", fps);
        c.ImGui_Text("Frame Time: %.2f ms", frame_times.*[graph_samples - 1]);

        c.ImGui_Separator();

        c.ImGui_PlotLines("Frame Times", frame_times, graph_samples);
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

    return .{ desired_w, desired_h };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator; // TODO Maybe move into a global variable, and look into using a more efficient allocator for our intents and purposes

    var viewport_settings = ViewportSettings{};
    const initial_fb_w: c_int = 640;
    const initial_fb_h: c_int = 480;
    var sdl_context = try initSdl(initial_fb_w, initial_fb_h);
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    const imgui_context = initImGui(sdl_context.window, sdl_context.renderer);
    defer deinitImGui(imgui_context);

    var app_state = AppState{
        .is_running = true,
        .mouse_captured = false,
    };

    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // Load models
    var kokiri_model = try objects.loadModel("models/Kokiri Forest/Kokiri Forest.obj", &allocator);

    const world_scale: f32 = 0.02;

    // Scale down the world
    for (kokiri_model.triangles.items) |*tri| {
        for (0..3) |i| {
            tri[i].x *= world_scale;
            tri[i].y *= world_scale;
            tri[i].z *= world_scale;
        }
    }
    defer kokiri_model.deinit();

    // Prepare objects
    var object_list: std.ArrayList(Object) = .empty;
    defer object_list.deinit(allocator);

    var kokiri_obj = try Object.init(kokiri_model, &allocator);
    kokiri_obj.moveTo(0, 0, 0);
    defer kokiri_obj.deinit();
    try object_list.append(allocator, kokiri_obj);

    // Scene constants
    var world_camera = render.Camera{
        .position = .{ .x = 3, .y = 2, .z = 6 },
    };

    // Performance variables
    const frequency = c.SDL_GetPerformanceFrequency(); // Get SDL counter ticks per second
    var last_count: u64 = c.SDL_GetPerformanceCounter(); // Last time that a frame was counted
    var frame_times: [graph_samples]f32 = undefined; // An array with all frame time data points

    // Init zbuffer
    var zb = try render.ZBuffer.init(initial_fb_w, initial_fb_h);
    defer zb.deinit();

    var desired_fb_w: c_int = initial_fb_w;
    var desired_fb_h: c_int = initial_fb_h;

    // TODO: better error handling
    while (app_state.is_running) {
        // Calculate performance metrics
        const current_count = c.SDL_GetPerformanceCounter(); // Get current tick count
        const delta = @as(f32, @floatFromInt(current_count - last_count)) / @as(f32, @floatFromInt(frequency)); // Calculate delay between frames in seconds
        last_count = current_count;

        @memmove(frame_times[0 .. graph_samples - 1], frame_times[1..graph_samples]); // Shift array contents one step to the left
        frame_times[graph_samples - 1] = delta * 1000; // Add data point at the end

        // Process events & handle cursor
        processEvents(&app_state, &world_camera);
        const sdl_has_capture = c.SDL_GetWindowRelativeMouseMode(sdl_context.window);
        if (app_state.mouse_captured != sdl_has_capture) {
            _ = c.SDL_SetWindowRelativeMouseMode(sdl_context.window, app_state.mouse_captured);
        }

        // Handle movement
        if (app_state.mouse_captured) {
            updateMovement(&world_camera, delta);
        }

        // Resize framebuffer/zbuffer if window size changed
        try sdl_context.resizeFramebuffer(desired_fb_w, desired_fb_h);
        try zb.resize(@intCast(desired_fb_w), @intCast(desired_fb_h));

        // Rasterize to texture
        _ = c.SDL_LockTexture(sdl_context.texture, null, &pixels, &pitch);
        const fb = render.FrameBuffer{
            .data = @ptrCast(@alignCast(pixels.?)),
            .stride = @divExact(@as(usize, @intCast(pitch)), 4), // pitch is bytes per row, each pixel is RGBA8888 (4 bytes)
            .width = sdl_context.fb_width,
            .height = sdl_context.fb_height,
        };
        zb.clear();
        // TODO: Add back lighting
        const triangles = renderScene(fb, &zb, &object_list, &world_camera);
        _ = c.SDL_UnlockTexture(sdl_context.texture);

        // Present texture & draw imgui
        _ = c.SDL_SetRenderDrawColorFloat(sdl_context.renderer, 0, 0, 0, 1);
        _ = c.SDL_RenderClear(sdl_context.renderer);

        // renderImGui returns desired size for the NEXT frame
        const new_size = renderImGui(sdl_context.texture, &frame_times, triangles, &world_camera, &app_state, &viewport_settings);
        desired_fb_w = new_size[0];
        desired_fb_h = new_size[1];

        c.cImGui_ImplSDLRenderer3_RenderDrawData(c.ImGui_GetDrawData(), sdl_context.renderer);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
