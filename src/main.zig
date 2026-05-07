// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");
const objects = @import("objects.zig");
const app = @import("app.zig");
const ui = @import("ui.zig");
const c = @import("c.zig").c;
const sdl = @import("sdl.zig");
const input = @import("input.zig");
const scene_mod = @import("scene.zig");
const scene_renderer = @import("scene_renderer.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var viewport_settings = app.ViewportSettings{};
    const window_settings = app.WindowSettings{};
    var app_state = app.AppState{};

    const initial_fb_w: c_int = viewport_settings.fixed_width;
    const initial_fb_h: c_int = viewport_settings.fixed_height;

    var sdl_context = try sdl.initSdl(initial_fb_w, initial_fb_h, window_settings);
    defer sdl_context.deinit();

    const imgui_context = ui.initImGui(sdl_context.window, sdl_context.renderer);
    defer ui.deinitImGui(imgui_context);

    var scene = try scene_mod.loadKokiriForest(allocator);
    defer scene.deinit(allocator);

    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // Scene constants
    var world_camera = render.Camera{
        .position = .{ .x = 3, .y = 2, .z = 6 },
    };

    // Performance variables
    const frequency = c.SDL_GetPerformanceFrequency(); // Get SDL counter ticks per second
    var last_count: u64 = c.SDL_GetPerformanceCounter(); // Last time that a frame was counted
    var frame_times: [app.frame_time_sample_count]f32 = undefined; // An array with all frame time data points

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

        @memmove(frame_times[0 .. app.frame_time_sample_count - 1], frame_times[1..app.frame_time_sample_count]); // Shift array contents one step to the left
        frame_times[app.frame_time_sample_count - 1] = delta * 1000; // Add data point at the end

        // Process events & handle cursor
        input.processEvents(&app_state, &world_camera);
        const sdl_has_capture = c.SDL_GetWindowRelativeMouseMode(sdl_context.window);
        if (app_state.mouse_captured != sdl_has_capture) {
            _ = c.SDL_SetWindowRelativeMouseMode(sdl_context.window, app_state.mouse_captured);
        }

        // Handle movement
        if (app_state.mouse_captured) {
            input.updateMovement(&world_camera, delta);
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
        const triangles = scene_renderer.renderScene(fb, &zb, &scene.objects, &world_camera);
        _ = c.SDL_UnlockTexture(sdl_context.texture);

        // Present texture & draw imgui
        _ = c.SDL_SetRenderDrawColorFloat(sdl_context.renderer, 0, 0, 0, 1);
        _ = c.SDL_RenderClear(sdl_context.renderer);

        // renderImGui returns desired size for the NEXT frame
        const new_size = ui.renderImGui(sdl_context.texture, &frame_times, triangles, &world_camera, &app_state, &viewport_settings);
        desired_fb_w = new_size.width;
        desired_fb_h = new_size.height;

        c.cImGui_ImplSDLRenderer3_RenderDrawData(c.ImGui_GetDrawData(), sdl_context.renderer);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
