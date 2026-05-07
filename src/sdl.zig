// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const c = @import("c.zig").c;
const app = @import("app.zig");

pub const SdlContext = struct {
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
        _ = c.SDL_SetTextureScaleMode(new_tex, c.SDL_SCALEMODE_LINEAR);
        self.texture = new_tex;
        self.fb_width = new_w;
        self.fb_height = new_h;
    }
};

pub fn initSdl(fb_w: c_int, fb_h: c_int, ws: app.WindowSettings) !SdlContext {
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SdlInitFailed;
    }
    errdefer c.SDL_Quit();

    if (!c.SDL_CreateWindowAndRenderer(ws.screen_title, ws.screen_width, ws.screen_height, 0, &window, &renderer)) {
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

    _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR);

    return SdlContext{
        .window = window.?,
        .renderer = renderer.?,
        .texture = texture,
        .fb_width = fb_w,
        .fb_height = fb_h,
    };
}
