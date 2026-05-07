// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT
const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");
const objects = @import("objects.zig");
const app = @import("app.zig");
const ui = @import("ui.zig");
const c = @import("platform/c.zig").c;
const sdl = @import("platform/sdl.zig");
const input = @import("input.zig");

const Object = objects.Object;

// TODO: Look into if there's a better solution than this...
// We need depth bias to avoid z-fighting in these textures
const water_depth_bias: f32 = 0.004;
fn textureDepthBias(texture_id: usize) f32 {
    // Helps water win when it is almost coplanar with riverbed geometry.
    return switch (texture_id) {
        19, 20 => water_depth_bias,
        else => 0.0,
    };
}

// It renders as gray patches so skip for now
fn textureShouldSkip(texture_id: usize) bool {
    return switch (texture_id) {
        19 => true,
        else => false,
    };
}

fn renderScene(
    fb: render.FrameBuffer,
    zb: *render.ZBuffer,
    object_list: *std.ArrayList(Object),
    world_camera: *render.Camera,
) struct { u64, u64, u64 } {
    render.drawSky(fb);

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
        for (object.triangles.items, 0..) |tri_v, tri_index| {
            total_triangles += 1;

            const tex_id: usize = @intCast(object.triangle_groups.items[tri_index]);
            if (textureShouldSkip(tex_id)) continue;
            const tb = object.textures.items[tex_id];
            const db = textureDepthBias(tex_id);

            var ca = [4]?math.Vec4{ // Array of vertexes
                vp.mulVec4(tri_v[0]),
                vp.mulVec4(tri_v[1]),
                vp.mulVec4(tri_v[2]),
                null, // Incase the near face clipping gives us a fourth vertex (quad)
            };

            // use the fog_end as far plane culling distance
            if (ca[0].?.w >= render.fog_end and
                ca[1].?.w >= render.fog_end and
                ca[2].?.w >= render.fog_end)
            {
                continue;
            }

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

            render.fillTriangle(v1, v2, v3, uv1, uv2, uv3, fb, zb, tb, db);

            if (cn == 4) {
                const v4 = ca[3].?.toPixel(fb.width, fb.height);
                const uv4 = cu[3].?;

                render.fillTriangle(v1, v3, v4, uv1, uv3, uv4, fb, zb, tb, db);
                drawn_triangles += 1;
            }

            drawn_triangles += 1;
            if (did_clip) clipped_triangles += cn - 2;
        }
    }

    return .{ total_triangles, drawn_triangles, clipped_triangles };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var viewport_settings = app.ViewportSettings{};
    const window_settings = app.WindowSettings{};
    var app_state = app.AppState{};

    const initial_fb_w: c_int = viewport_settings.fixed_width;
    const initial_fb_h: c_int = viewport_settings.fixed_height;

    var sdl_context = try sdl.initSdl(initial_fb_w, initial_fb_h, window_settings);
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    const imgui_context = ui.initImGui(sdl_context.window, sdl_context.renderer);
    defer ui.deinitImGui(imgui_context);

    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // Load models
    var kokiri_model = try objects.loadModel("models/Kokiri Forest/KF.obj", &allocator);

    const world_scale: f32 = 0.05;

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
        const triangles = renderScene(fb, &zb, &object_list, &world_camera);
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
