// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT
const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");

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

fn initImGui(window: *c.SDL_Window, renderer: *c.SDL_Renderer) *c.ImGuiContext {
    const context = c.ImGui_CreateContext(null).?;
    const io = c.ImGui_GetIO();
    io.*.IniFilename = null; // don't save the imgui.ini file
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

fn renderScene(fb: render.FrameBuffer) void {
    fb.clear();

    const tri_color: u32 = 0x00FF00FF;
    const p1 = math.Vec3{ .x = 960, .y = 100, .z = 0 };
    const p2 = math.Vec3{ .x = 400, .y = 900, .z = 0 };
    const p3 = math.Vec3{ .x = 1520, .y = 900, .z = 0 };

    render.drawTriangle(p1, p2, p3, fb, tri_color);
}

fn renderImGui() void {
    c.cImGui_ImplSDLRenderer3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    // TODO: add own ui
    c.ImGui_ShowDemoWindow(null);

    c.ImGui_Render();
}

pub fn main() !void {
    const sdl_context = try initSdl();
    defer c.SDL_Quit();
    defer sdl_context.deinit();

    const imgui_context = initImGui(sdl_context.window, sdl_context.renderer);
    defer deinitImGui(imgui_context);

    var is_running: bool = true;
    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;

    // TODO: better error handling
    while (is_running) {
        processEvents(&is_running);

        // rasterize to texture
        _ = c.SDL_LockTexture(sdl_context.texture, null, &pixels, &pitch);
        const fb = render.FrameBuffer{
            .data = @ptrCast(@alignCast(pixels.?)),
            .stride = @divExact(@as(usize, @intCast(pitch)), 4),
            .width = screen_width,
            .height = screen_height,
        };
        renderScene(fb);
        _ = c.SDL_UnlockTexture(sdl_context.texture);

        // present texture & draw imgui
        _ = c.SDL_SetRenderDrawColorFloat(sdl_context.renderer, 0, 0, 0, 1);
        _ = c.SDL_RenderClear(sdl_context.renderer);
        _ = c.SDL_RenderTexture(sdl_context.renderer, sdl_context.texture, null, null);

        renderImGui();
        c.cImGui_ImplSDLRenderer3_RenderDrawData(c.ImGui_GetDrawData(), sdl_context.renderer);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
        c.SDL_Delay(16); // 60fps
    }
}
