// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const render = @import("render.zig");
const app = @import("app.zig");
const c = @import("c.zig").c;
const math = @import("math.zig");

pub fn processEvents(app_state: *app.AppState, world_camera: *render.Camera) void {
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

pub fn updateMovement(world_camera: *render.Camera, delta: f32) void {
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
