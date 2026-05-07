// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

pub const c = @cImport({
    // SDL
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");

    // ImGui
    @cInclude("dcimgui.h");
    @cInclude("dcimgui_impl_sdl3.h");
    @cInclude("dcimgui_impl_sdlrenderer3.h");

    // stb_image
    @cInclude("lib/stb_image.h");
});
