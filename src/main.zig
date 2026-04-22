// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT
const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");
const objects = @import("objects.zig");

const Model = objects.Model;
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

    pub fn deinit(self: SdlContext) void {
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }
};

fn initSdl() !SdlContext {
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;
    var texture: ?*c.SDL_Texture = null;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlInitFailed;
    }
    errdefer c.SDL_Quit();

    if (!c.SDL_CreateWindowAndRenderer(screen_title, screen_width, screen_height, 0, &window, &renderer)) {
        std.debug.print("SDL_CreateWindowAndRenderer failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlWindowCreationFailed;
    }

    _ = c.SDL_SetRenderVSync(renderer.?, 1); // enable vsync

    texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, screen_width, screen_height);

    if (texture == null) {
        std.debug.print("SDL_CreateTexture failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlCreateTextureFailed;
    }

    return SdlContext{ .window = window.?, .renderer = renderer.?, .texture = texture.? };
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

fn processEvents(is_running: *bool) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        _ = c.cImGui_ImplSDL3_ProcessEvent(&event);
        if (event.type == c.SDL_EVENT_QUIT) {
            is_running.* = false;
        }
    }
}

fn renderScene(fb: render.FrameBuffer, zb: *render.ZBuffer, object_list: *std.ArrayList(Object)) struct { u64, u64 } {
    fb.clear();
    const world_camera = render.Camera{
        .position = .{ .x = 3, .y = 2, .z = 6 },
        .target = .{ .x = 1, .y = 1, .z = 3 }, // point at the cube
    };
    const aspect = @as(f32, @floatFromInt(fb.width)) / @as(f32, @floatFromInt(fb.height));

    const light_sources = [_]render.LightSource{
        .{ .SkyLight = .{ .brightness = 1 } },
        .{ .PointLight = .{ .position = .{ .x = 0, .y = -10, .z = -2 }, .brightness = 0.5 } },
    };

    const world_lighting = render.WorldLighting{ .ambient = 0.3, .light_sources = &light_sources };

    const proj_matrix = math.Mat4.perspective(world_camera.fov, aspect, world_camera.near, world_camera.far);
    const view_matrix = math.Mat4.viewMatrix(world_camera.position, world_camera.target, world_camera.up);
    const vp = proj_matrix.mul(view_matrix); // world to view to clip space in one matrix

    var total_triangles: u64 = 0;
    var drawn_triangles: u64 = 0;

    for (object_list.*.items) |object| {
        for (object.triangles.items) |tri_v| {
            total_triangles += 1;

            const c0 = vp.mulVec4(tri_v[0]);
            const c1 = vp.mulVec4(tri_v[1]);
            const c2 = vp.mulVec4(tri_v[2]);

            if (c0.w <= world_camera.near or c1.w <= world_camera.near or c2.w <= world_camera.near) continue;

            const p0 = tri_v[0].toVec3();
            const p1 = tri_v[1].toVec3();
            const p2 = tri_v[2].toVec3();

            const tri_ilum: f32 = world_lighting.triangleIlum(p0, p1, p2);

            const v1 = c0.toPixel(fb.width, fb.height);
            const v2 = c1.toPixel(fb.width, fb.height);
            const v3 = c2.toPixel(fb.width, fb.height);

            if (render.facingAway(v1, v2, v3)) continue;
            const color: u32 = if (object.z > -4.0) 0x0000FFFF else 0xFF0000FF;
            const color2: u32 = render.multiplyRgb(color, tri_ilum);
            render.fillTriangle(v1, v2, v3, fb, zb, color2);
            // render.drawTriangle(v1, v2, v3, fb, zb, 0x000000FF);


            drawn_triangles += 1;
        }
    }

    return .{ total_triangles, drawn_triangles };
}

fn renderImGui(texture: *c.SDL_Texture, frame_times: *[graph_samples]f32, triangles: struct { u64, u64 }) void {
    c.cImGui_ImplSDLRenderer3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    _ = c.ImGui_DockSpaceOverViewport();

    // viewport window
    // TODO: is there a better way to do the aspect ratio letterboxing without having to calculate every frame?
    if (c.ImGui_Begin("Viewport", null, 0)) {
        const avail = c.ImGui_GetContentRegionAvail();
        const tex_aspect = @as(f32, @floatFromInt(screen_width)) / @as(f32, @floatFromInt(screen_height));
        const avail_aspect = avail.x / avail.y;

        var img_size: c.ImVec2 = undefined;
        if (avail_aspect > tex_aspect) {
            img_size.y = avail.y;
            img_size.x = avail.y * tex_aspect;
        } else {
            img_size.x = avail.x;
            img_size.y = avail.x / tex_aspect;
        }

        const pad_x = (avail.x - img_size.x) * 0.5;
        const pad_y = (avail.y - img_size.y) * 0.5;
        if (pad_x > 0 or pad_y > 0) {
            const pos = c.ImGui_GetCursorPos();
            c.ImGui_SetCursorPos(.{ .x = pos.x + pad_x, .y = pos.y + pad_y });
        }

        c.ImGui_Image(c.struct_ImTextureRef_t{
            ._TexData = null,
            ._TexID = @intFromPtr(texture),
        }, img_size);
    }
    c.ImGui_End();

    // demo window thing
    if (c.ImGui_Begin("hello", null, 0)) {
        c.ImGui_Text("this is a window");
    }
    c.ImGui_End();

    // Performance Metrics (FPS, etc)
    if (c.ImGui_Begin("Performance Metrics", null, 0)) {
        const avg_delay = @reduce(.Add, @as(@Vector(graph_samples, f32), frame_times.*)) / graph_samples; // Sums array and divides by amount of samples to get average

        c.ImGui_Text("FPS: %.2f", 1000.0 / frame_times.*[graph_samples-1]);
        c.ImGui_Text("Avg. FPS: %.2f", 1000.0 / avg_delay);

        c.ImGui_Dummy(c.ImVec2{ .x = 10, .y = 5 }); // Add a bit of space
        c.ImGui_Text("Frame Time: %.2f ms", frame_times.*[graph_samples-1]);
        c.ImGui_Text("Avg. Frame Time: %.2f ms", avg_delay);

        c.ImGui_Dummy(c.ImVec2{ .x = 10, .y = 5 }); // Add a bit of space
        c.ImGui_PlotLines("Frame Times", frame_times, graph_samples);
    }
    c.ImGui_End();

    // Render Metrics (Triangle counts, etc)
    if (c.ImGui_Begin("Render Metrics", null, 0)) {
        c.ImGui_Text("Total Triangles: %d", triangles[0]);
        c.ImGui_Text("Drawn Triangles: %d", triangles[1]);
    }
    c.ImGui_End();

    c.ImGui_Render();
}

pub fn main() !void {
    const allocator = std.heap.page_allocator; // TODO Maybe move into a global variable, and look into using a more efficient allocator for our intents and purposes

    const sdl_context = try initSdl();
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    const imgui_context = initImGui(sdl_context.window, sdl_context.renderer);
    defer deinitImGui(imgui_context);

    var is_running: bool = true;
    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // Load models
    var cow_model = try objects.loadModel("models/cow.obj", &allocator);
    defer cow_model.deinit();

    var teapot_model = try objects.loadModel("models/teapot.obj", &allocator);
    defer teapot_model.deinit();

    // Prepare objects
    var object_list: std.ArrayList(Object) = .empty;
    defer object_list.deinit(allocator);

    var cow_obj = try Object.init(cow_model, &allocator);
    cow_obj.moveTo(-4, 2, -1); //
    defer cow_obj.deinit();
    try object_list.append(allocator, cow_obj);

    var teapotobj = try Object.init(teapot_model, &allocator);
    teapotobj.moveTo(-2, 0, -5);
    defer teapotobj.deinit();
    try object_list.append(allocator, teapotobj);

    // Performance variables
    const frequency = c.SDL_GetPerformanceFrequency(); // Get SDL counter ticks per second
    var last_count: u64 = c.SDL_GetPerformanceCounter(); // Last time that a frame was counted
    var frame_times: [graph_samples]f32 = undefined; // An array with all frame time data points

    // TODO: better error handling
    while (is_running) {
        // Calculate performance metrics
        const current_count = c.SDL_GetPerformanceCounter(); // Get current tick count
        const delta = @as(f32, @floatFromInt(current_count - last_count)) / @as(f32, @floatFromInt(frequency));  // Calculate delay between frames in seconds
        last_count = current_count;

        @memmove(frame_times[0..graph_samples-1], frame_times[1..graph_samples]);  // Shift array contents one step to the left
        frame_times[graph_samples - 1] = delta * 1000;  // Add data point at the end

        // Process events
        processEvents(&is_running);

        // rasterize to texture
        _ = c.SDL_LockTexture(sdl_context.texture, null, &pixels, &pitch);
        const fb = render.FrameBuffer{
            .data = @ptrCast(@alignCast(pixels.?)),
            .stride = @divExact(@as(usize, @intCast(pitch)), 4),
            .width = screen_width,
            .height = screen_height,
        };
        var zb = try render.ZBuffer.init(screen_width, screen_height);
        const triangles = renderScene(fb, &zb, &object_list);
        _ = c.SDL_UnlockTexture(sdl_context.texture);

        // present texture & draw imgui
        _ = c.SDL_SetRenderDrawColorFloat(sdl_context.renderer, 0, 0, 0, 1);
        _ = c.SDL_RenderClear(sdl_context.renderer);

        renderImGui(sdl_context.texture, &frame_times, triangles);
        c.cImGui_ImplSDLRenderer3_RenderDrawData(c.ImGui_GetDrawData(), sdl_context.renderer);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
