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
    io.*.IniFilename = "config/imgui.ini";
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
    const world_camera = render.Camera{}; // default camera
    const aspect = @as(f32, @floatFromInt(fb.width)) / @as(f32, @floatFromInt(fb.height));

    const proj_matrix = math.Mat4.perspective(world_camera.fov, aspect, world_camera.near, world_camera.far);

    const cx: f32 = 3;
    const cy: f32 = 1;
    const cz: f32 = -4;

    const tris = [_][3]math.Vec4{
        // back face
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 } },
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 } },
        // front face
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 } },
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 } },
        // left face
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 } },
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 } },
        // right face
        .{ .{ .x = 1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 } },
        .{ .{ .x = 1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 } },
        // bottom face
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 } },
        .{ .{ .x = -1 + cx, .y = -1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = -1 + cy, .z = 1 + cz, .w = 1 } },
        // top face
        .{ .{ .x = -1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 } },
        .{ .{ .x = -1 + cx, .y = 1 + cy, .z = -1 + cz, .w = 1 }, .{ .x = -1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 }, .{ .x = 1 + cx, .y = 1 + cy, .z = 1 + cz, .w = 1 } },
    };

    for (tris) |tri_v| {
        const c0 = proj_matrix.mulVec4(tri_v[0]);
        const c1 = proj_matrix.mulVec4(tri_v[1]);
        const c2 = proj_matrix.mulVec4(tri_v[2]);

        if (c0.w <= world_camera.near or c1.w <= world_camera.near or c2.w <= world_camera.near) continue;

        const v1 = c0.toPixel(fb.width, fb.height);
        const v2 = c1.toPixel(fb.width, fb.height);
        const v3 = c2.toPixel(fb.width, fb.height);

        // TODO: Change culltriangle to use screen space not world space
        // TODO: Change of basis to camera coordinates so we can use different camera positions
        if (!render.cullTriangle(v1, v2, v3, world_camera.position)) {
            render.fillTriangle(v1, v2, v3, fb, 0xFFFFFFFF);
            render.drawTriangle(v1, v2, v3, fb, 0xFF0000FF);
        }
    }
}

fn renderImGui(texture: *c.SDL_Texture) void {
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

        renderImGui(sdl_context.texture);
        c.cImGui_ImplSDLRenderer3_RenderDrawData(c.ImGui_GetDrawData(), sdl_context.renderer);

        _ = c.SDL_RenderPresent(sdl_context.renderer);
    }
}
