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

const screen_width: c_int = 640;
const screen_height: c_int = 480;
const screen_title: [*c]const u8 = "working-title";

const SdlContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,

    pub fn deinit(self: SdlContext) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyTexture(self.texture);
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

    // We can unwrap safely because of the assertion above
    return SdlContext{ .window = window.?, .renderer = renderer.?, .texture = texture.? };
}

const Point2D = struct {
    x: isize,
    y: isize,
};

//TODO create a framebuffer to Plot points to
//TODO create tests for drawLine function and optimize
/// drawLine plots a 1 pixel wide line between a start and end point using
/// Bresenham's line algorithm (https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm)
fn drawLine(start: Point2D, end: Point2D) !void {
    var x0 = start.x;
    var y0 = start.y;
    const x1 = end.x;
    const y1 = end.y;

    const dx: isize = @intCast(@abs(x1 - x0));
    const dy: isize = @intCast(-@abs(y1 - y0));

    // draw lines start to end
    const sx: isize = if (x0 < x1) 1 else -1;
    const sy: isize = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        //TODO plot(x0, y0);

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
    // NOTE: Defer runs in reverse order.
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

        // pixels is the pointer to the raw memory where the pixels live
        // pitch is the number of bytes PER ROW so we know how many steps to take
        _ = c.SDL_LockTexture(sdl_context.texture, null, &pixels, &pitch);

        // This allows us to index into the pixel array and modify it
        const pixel_data: [*]u32 = @ptrCast(@alignCast(pixels.?));
        const stride = @divExact(@as(usize, @intCast(pitch)), 4);
        @memset(pixel_data[0 .. stride * screen_height], 0);

        // Draw
        _ = c.SDL_UnlockTexture(sdl_context.texture);
        _ = c.SDL_RenderTexture(sdl_context.renderer, sdl_context.texture, null, null);
        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
