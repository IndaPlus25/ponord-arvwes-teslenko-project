// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

pub const WindowSettings = struct {
    screen_width: c_int = 1920,
    screen_height: c_int = 1080,
    screen_title: [*c]const u8 = "working-title",
};

pub const AppState = struct {
    is_running: bool = true,
    mouse_captured: bool = true,
};

pub const ViewportSettings = struct {
    render_scale: f32 = 0.25,
    fixed_res: bool = true,
    fixed_width: c_int = 320,
    fixed_height: c_int = 240,
};

pub const RenderStats = struct {
    total_triangles: u64 = 0,
    drawn_triangles: u64 = 0,
    clipped_triangles: u64 = 0,
};

pub const DesiredFramebufferSize = struct {
    width: c_int,
    height: c_int,
};

// Frame graph data points
pub const frame_time_sample_count: usize = 120;
