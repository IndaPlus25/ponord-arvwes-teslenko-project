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

    pub fn deinit(self: SdlContext) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
    }
};

fn initSdl() !SdlContext {
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

    // We can unwrap safely because of the assertion above
    return SdlContext{
        .window = window.?,
        .renderer = renderer.?,
    };
}

pub fn main() !void {
    const sdl_context = try initSdl();
    // NOTE: Defer runs in reverse order.
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    var is_running: bool = true;
    var event: c.SDL_Event = undefined;

    // TODO: This is kinda stupid, most of these can throw errors
    // so we probably want to look into what to handle explicitly
    while (is_running) {
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                is_running = false;
            }
        }

        _ = c.SDL_SetRenderDrawColor(sdl_context.renderer, 255, 255, 255, 255);
        _ = c.SDL_RenderClear(sdl_context.renderer);
        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
