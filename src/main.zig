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
};

fn sdlInit() !SdlContext {
    // WARNING: Caller needs to free destroy these
    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        return error.SdlInitFailed;
    }

    if (!c.SDL_CreateWindowAndRenderer(screen_title, screen_width, screen_height, 0, &window, &renderer)) {
        c.SDL_Quit();
        return error.SdlWindowCreationFailed;
    }

    return SdlContext{
        .window = window orelse unreachable,
        .renderer = renderer orelse unreachable,
    };
}

pub fn main() !void {
    const sdl_context = try sdlInit();
    // NOTE: Defer runs in backwards order
    defer c.SDL_Quit();
    defer c.SDL_DestroyWindow(sdl_context.window);
    defer c.SDL_DestroyRenderer(sdl_context.renderer);

    // TODO: Handle this better, just for debugging rn
    _ = c.SDL_RenderPresent(sdl_context.renderer);
    c.SDL_Delay(2000);
    std.debug.print("Successfully initialized SDL!", .{});
}
