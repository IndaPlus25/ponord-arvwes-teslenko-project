// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT
const std = @import("std");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

// We can define our math types here for ease of use
const Vec3 = @import("math.zig").Vec3;

// Program information
const screen_width: c_int = 640;
const screen_height: c_int = 480;
const screen_title: [*c]const u8 = "working-title";

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

    texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, screen_width, screen_height);

    if (texture == null) {
        std.debug.print("SDL_CreateTexture failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlCreateTextureFailed;
    }

    return SdlContext{ .window = window.?, .renderer = renderer.?, .texture = texture.? };
}

// Remove this later and just use a Vec3,
// we can scale x, y with z component
const Point2D = struct {
    x: isize,
    y: isize,
};

fn drawTriangle(v1: Point2D, v2: Point2D, v3: Point2D, frame_buffer: [*]u32, stride: usize, color: u32) void {
    drawLine(v1, v2, frame_buffer, stride, color);
    drawLine(v1, v3, frame_buffer, stride, color);
    drawLine(v2, v3, frame_buffer, stride, color);
}

// TODO: Clean up this code if possible, optimize & test
fn drawLine(start: Point2D, end: Point2D, frame_buffer: [*]u32, stride: usize, color: u32) void {
    var x0 = start.x;
    var y0 = start.y;
    const x1 = end.x;
    const y1 = end.y;

    const dx: isize = @as(isize, @intCast(@abs(x1 - x0)));
    const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
    const sx: isize = if (x0 < x1) 1 else -1;
    const sy: isize = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        if (x0 >= 0 and x0 < screen_width and y0 >= 0 and y0 < screen_height) {
            frame_buffer[@as(usize, @intCast(y0)) * stride + @as(usize, @intCast(x0))] = color;
        }

        const e2 = 2 * err;
        if (e2 >= dy) {
            if (x0 == x1) break;
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            if (y0 == y1) break;
            err += dx;
            y0 += sy;
        }
    }
}

pub fn main() !void {
    const sdl_context = try initSdl();
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    var is_running: bool = true;
    var event: c.SDL_Event = undefined;

    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // TODO: This is kinda stupid, most of these can throw errors
    // so we probably want to look into what to handle explicitly
    while (is_running) {
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                is_running = false;
            }
        }

        // Pixels is pointer to memory
        // Pitch is the number of bytes per row
        _ = c.SDL_LockTexture(sdl_context.texture, null, &pixels, &pitch);

        const pixel_data: [*]u32 = @ptrCast(@alignCast(pixels.?));
        const stride = @divExact(@as(usize, @intCast(pitch)), 4);
        @memset(pixel_data[0 .. stride * screen_height], 0);

        // DO STUFF HERE
        // Draw line for debugging
        const tri_color: u32 = 0x00FF00FF;
        const p1 = Point2D{ .x = 30, .y = 70 };
        const p2 = Point2D{ .x = 200, .y = 150 };
        const p3 = Point2D{ .x = 300, .y = 50 };
        drawTriangle(p1, p2, p3, pixel_data, stride, tri_color);
        const line_color: u32 = 0xFF0000FF;
        drawLine(Point2D{ .x = 10, .y = 10 }, Point2D{ .x = 200, .y = 150 }, pixel_data, stride, line_color);

        // Render to screen
        _ = c.SDL_UnlockTexture(sdl_context.texture);
        _ = c.SDL_RenderTexture(sdl_context.renderer, sdl_context.texture, null, null);
        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
