// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const math = @import("math.zig");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const Camera = struct {
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 }, // initial world pos
    yaw: f32 = 0.0, // rotation around the up vector (left/right) in radians
    pitch: f32 = 0.0, // rotation around the camera right axis (up/down) in radians
    sensitivity: f32 = 0.0018, // mouse sensitivity
    move_speed: f32 = 18.0, // move speed
    up: Vec3 = .{ .x = 0, .y = 1, .z = 0 }, // y is up dir
    fov: f32 = 60.0, // field of view in degrees
    near: f32 = 0.2, // distance to near plane
    far: f32 = 450.0, // distance to far plane
};

// TODO: Add these to ImGui so we can play with values
// TODO: Maybe put these in a struct?
const sky_color: u32 = 0xaeb982ff;
const sky_horizon_color: u32 = 0xd2cc95ff;
const fog_color: u32 = 0xb8b982ff;
const fog_strength: f32 = 1.25;
pub const fog_start: f32 = 70.0; // used in main
pub const fog_end: f32 = 220.0; // used in main

// keeps UVs inside [0, 1], so textures tile normally
fn repeatWrap(value: f32) f32 {
    return value - @floor(value);
}

// gets one 8-bit channel from a packed RGBA (u32)
// shift = 24 red
// shift = 16 green
// shift = 8 blue
// shift = 0 alpha
fn colorChannel(color: u32, shift: u5) f32 {
    return @floatFromInt((color >> shift) & 0xff);
}

// takes 4 channels and packs it into RGBA
// clamps each channel to [0, 255]
fn packRgba(r: f32, g: f32, b: f32, a: f32) u32 {
    const red: u32 = @intFromFloat(std.math.clamp(r, 0.0, 255.0));
    const green: u32 = @intFromFloat(std.math.clamp(g, 0.0, 255.0));
    const blue: u32 = @intFromFloat(std.math.clamp(b, 0.0, 255.0));
    const alpha: u32 = @intFromFloat(std.math.clamp(a, 0.0, 255.0));
    return (red << 24) | (green << 16) | (blue << 8) | alpha;
}

// lerp between two colors to mix them
// amt = 0.0 gives color a
// amt = 1.0 gives color b
// amt = 0.5 gives a mix of a, b
fn mixColor(a: u32, b: u32, amt: f32) u32 {
    const t = std.math.clamp(amt, 0.0, 1.0);

    // a + (b - a) * t is the lerp formula
    return packRgba(
        colorChannel(a, 24) + (colorChannel(b, 24) - colorChannel(a, 24)) * t,
        colorChannel(a, 16) + (colorChannel(b, 16) - colorChannel(a, 16)) * t,
        colorChannel(a, 8) + (colorChannel(b, 8) - colorChannel(a, 8)) * t,
        colorChannel(a, 0) + (colorChannel(b, 0) - colorChannel(a, 0)) * t,
    );
}

// classic bayer4 dithering matrix
// https://en.wikipedia.org/wiki/Ordered_dithering
fn bayer4(x: usize, y: usize) f32 {
    const matrix = [_]u8{
        0,  8,  2,  10,
        12, 4,  14, 6,
        3,  11, 1,  9,
        15, 7,  13, 5,
    };

    const index = (y % 4) * 4 + (x % 4);

    // takes the bayer value [0, 15] and converts to [-0.5, 0.5]
    return (@as(f32, @floatFromInt(matrix[index])) / 15.0) - 0.5;
}

// takes in a single channel, applies dithering, quantizes to 5-bit then turn to 8-bit for RGBA
fn quantizeChannel(value: f32, dither: f32) f32 {
    // 255 is max for u8, 31 is max for u5, so (255/31) is one u5 step in u8 space
    // 0.7 is just a scalar to make dithering less aggressive
    const adj_color = std.math.clamp(value + dither * (255.0 / 31.0) * 0.7, 0.0, 255.0);

    // converts from u8 to u5 and rounds it
    const new_color: u32 = @intFromFloat(std.math.round(adj_color * 31.0 / 255.0));

    // expand u5 back to u8 to fit in our RGBA fb
    // << 3 turns to u8, >> 2 fills the empty bits from shifting
    return @floatFromInt((new_color << 3) | (new_color >> 2));
}

// takes a packed RGBA and quantizes RGB to 5-bit
// NOTE: alpha is unchanged
fn quantizeColor(color: u32, x: usize, y: usize, use_dither: bool) u32 {
    const dither = if (use_dither) bayer4(x, y) else 0.0;

    return packRgba(
        quantizeChannel(colorChannel(color, 24), dither), // r
        quantizeChannel(colorChannel(color, 16), dither), // g
        quantizeChannel(colorChannel(color, 8), dither), // b
        colorChannel(color, 0), // a
    );
}

// bilinear interpolation between 4 neighbouring pixels
fn sampleBilinearColor(
    top_left: u32,
    top_right: u32,
    bottom_left: u32,
    bottom_right: u32,
    blend_x: f32,
    blend_y: f32,
) u32 {
    // blend top row horizontally
    // blend bottom row horizontally
    // blend those vertically
    const top = mixColor(top_left, top_right, blend_x);
    const bottom = mixColor(bottom_left, bottom_right, blend_x);
    return mixColor(top, bottom, blend_y);
}

// Adds a basic sky gradient, doesn't touch the z-buffer so shouldn't mess with anything
pub fn drawSky(fb: FrameBuffer) void {
    const width: usize = @intCast(fb.width);
    const height: usize = @intCast(fb.height);
    const max_y: f32 = @floatFromInt(if (height > 1) height - 1 else 1);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        // 1.0 is top of screen, 0.0 bottom
        const t = @as(f32, @floatFromInt(y)) / max_y;
        const color = mixColor(sky_color, sky_horizon_color, t);

        var x: usize = 0;
        while (x < width) : (x += 1) {
            // TODO: Add param to function to enable/disable dither
            fb.data[y * fb.stride + x] = quantizeColor(color, x, y, true);
        }
    }
}

// Fade pixels far away for fog effect
fn addFog(color: u32, depth: f32) u32 {
    if (depth <= fog_start) return color;
    if (depth >= fog_end) return fog_color;
    var fog_amt = (depth - fog_start) / (fog_end - fog_start);
    fog_amt = std.math.clamp(fog_amt * fog_strength, 0.0, 1.0);
    return mixColor(color, fog_color, fog_amt);
}

pub const TextureBuffer = struct {
    data: []u32,
    width: usize,
    height: usize,

    pub fn getColor(self: TextureBuffer, u: f32, v: f32) u32 {
        // convert uv to (repeated) texture position
        // also flip V because obj assumes different orientation
        const x = repeatWrap(u) * @as(f32, @floatFromInt(self.width - 1));
        const y = (1.0 - repeatWrap(v)) * @as(f32, @floatFromInt(self.height - 1));

        // find texture pixel above/left of sample point
        const left: usize = @intFromFloat(@floor(x));
        const top: usize = @intFromFloat(@floor(y));

        // find texture pixel below/right of sample point
        const right = @min(left + 1, self.width - 1);
        const bottom = @min(top + 1, self.height - 1);

        // fractional pos inside 2x2 pixel area (for blend weights)
        const blend_x = x - @floor(x);
        const blend_y = y - @floor(y);

        // index = row * width + column
        const top_row = top * self.width;
        const bottom_row = bottom * self.width;

        const top_left = self.data[top_row + left];
        const top_right = self.data[top_row + right];
        const bottom_left = self.data[bottom_row + left];
        const bottom_right = self.data[bottom_row + right];

        // blend the neighboring pixels into one color
        return sampleBilinearColor(top_left, top_right, bottom_left, bottom_right, blend_x, blend_y);
    }
};

// TODO: Vertex lighting instead of per triangle?
pub const WorldLighting = struct {
    ambient: f32 = 0.3,
    light_sources: []const LightSource,
    pub fn SkyDirection() Vec3 {
        return .{ .x = 0, .y = 1, .z = 0 };
    }
    pub fn triangleIlum(self: WorldLighting, v1: Vec3, v2: Vec3, v3: Vec3) f32 {
        var total: f32 = 0;

        const normal = v1.normalVector(v2, v3);
        for (0..3) |i| {
            const v: Vec3 = switch (i) {
                0 => v1,
                1 => v2,
                2 => v3,
                else => unreachable,
            };
            var vertex_brightness = self.ambient;

            for (self.light_sources) |source| {
                var light_dir = Vec3{ .x = 0, .y = 0, .z = 0 };
                var source_brightness: f32 = 0;
                switch (source) {
                    .SkyLight => |sky| {
                        light_dir = Vec3{ .x = 0, .y = 1, .z = 0 };
                        source_brightness = sky.brightness;
                    },
                    .PointLight => |pt_light| {
                        light_dir = pt_light.position.sub(v);
                        source_brightness = pt_light.brightness;
                    },
                }
                const diffuse_light = normal.dot(light_dir.norm()) * source_brightness;
                if (diffuse_light > 0) {
                    vertex_brightness += diffuse_light;
                }
            }
            if (vertex_brightness > 1.0) {
                vertex_brightness = 1.0;
            }
            total += vertex_brightness;
        }
        return total / 3;
    }
};

pub const LightSource = union(enum) {
    SkyLight: struct { brightness: f32 },
    PointLight: struct { position: Vec3, brightness: f32 },
};

pub const FrameBuffer = struct {
    data: [*]u32,
    stride: usize, // pixels per row
    width: c_int,
    height: c_int,

    pub fn setPixel(self: FrameBuffer, x: usize, y: usize, color: u32) void {
        if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
            // jump to the correct row & add x
            self.data[@as(usize, @intCast(y)) * self.stride + @as(usize, @intCast(x))] = color;
        }
    }

    pub fn clear(self: FrameBuffer) void {
        @memset(self.data[0 .. self.stride * @as(usize, @intCast(self.height))], 0);
    }
};

pub const ZBuffer = struct {
    data: []f32,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    pub fn init(width: c_int, height: c_int) !ZBuffer {
        const uWidth = @as(usize, @intCast(width));
        const uHeight = @as(usize, @intCast(height));
        const allocator = std.heap.page_allocator;

        const data = try allocator.alloc(f32, uWidth * uHeight);
        var zBuffer = ZBuffer{ .data = data, .width = uWidth, .height = uHeight, .allocator = allocator };
        zBuffer.clear();
        return zBuffer;
    }

    pub fn clear(self: ZBuffer) void {
        @memset(self.data, 20000.0); // Should be the same as Camera.far, or larger
    }

    pub fn deinit(self: ZBuffer) void {
        self.allocator.free(self.data);
    }

    pub fn getDepth(self: ZBuffer, x: usize, y: usize) f32 {
        const index = x + y * self.width;
        return self.data[index];
    }

    pub fn setDepth(self: ZBuffer, x: usize, y: usize, depth: f32) void {
        const index = x + y * self.width;
        self.data[index] = depth;
    }

    pub fn resize(self: *ZBuffer, new_w: usize, new_h: usize) !void {
        if (new_w == self.width and new_h == self.height) return;
        self.allocator.free(self.data);
        self.data = try self.allocator.alloc(f32, new_w * new_h);
        self.width = new_w;
        self.height = new_h;
    }
};

// This is equivalent to the z component of the cross product (b-a) x (c-a), by the right hand rule
// we can see that either z points "into" the screen, or out, if it's pointing away from the camera we don't render it
fn edgeFunction(a: Vec3, b: Vec3, c: Vec3) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

// https://github.com/ssloy/tinyrenderer/wiki/Lesson-2:-Triangle-rasterization-and-back-face-culling
// https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes.html
// https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
pub fn fillTriangle(
    v1: Vec3,
    v2: Vec3,
    v3: Vec3,
    uv1: Vec2, //TODO create vertex struct
    uv2: Vec2,
    uv3: Vec2,
    fb: FrameBuffer,
    zb: *ZBuffer,
    tb: TextureBuffer,
    db: f32,
) void {
    // Find the smallest possible rectangle that the triangle fits inside,
    // only loop through the pixels in this rectangle to avoid unnecessary work.
    const min_x_f = @min(v1.x, @min(v2.x, v3.x)); // leftmost point
    const min_y_f = @min(v1.y, @min(v2.y, v3.y)); // topmost point (y = 0 is top)
    const max_x_f = @max(v1.x, @max(v2.x, v3.x)); // rightmost point
    const max_y_f = @max(v1.y, @max(v2.y, v3.y)); // topmost point

    // Convert to ints
    var min_x: isize = @intFromFloat(@floor(min_x_f));
    var min_y: isize = @intFromFloat(@floor(min_y_f));
    var max_x: isize = @intFromFloat(@ceil(max_x_f));
    var max_y: isize = @intFromFloat(@ceil(max_y_f));

    // Clamp the bounding box, imagine if a triangle points off the side of the screen,
    // we don't want to render that
    min_x = @max(min_x, 0);
    min_y = @max(min_y, 0);
    max_x = @min(max_x, @as(isize, @intCast(fb.width)) - 1);
    max_y = @min(max_y, @as(isize, @intCast(fb.height)) - 1);

    // Get the signed area of the parallelogram that the points span
    const area = edgeFunction(v1, v2, v3);
    if (area == 0) return; // not a triangle

    // Precalculate the inverses
    const inv_area = 1.0 / area;
    const inv_z1 = 1.0 / v1.z;
    const inv_z2 = 1.0 / v2.z;
    const inv_z3 = 1.0 / v3.z;

    // Precalculate the per-pixel deltas, we do this to avoid calling edgeFunction in the loop,
    // we know that the edge function is linear, i.e. (x, y) to (x + 1, y) changes by a constant amount,
    const dw0_dx = v2.y - v3.y; // change in w0 when stepping one pixel right
    const dw0_dy = v3.x - v2.x; // change in w0 when stepping one pixel down
    const dw1_dx = v3.y - v1.y; // ...
    const dw1_dy = v1.x - v3.x;
    const dw2_dx = v1.y - v2.y;
    const dw2_dy = v2.x - v1.x;

    // Start at the top left corner of the bounding box with pixel offset
    const start = Vec3{
        .x = @as(f32, @floatFromInt(min_x)) + 0.5,
        .y = @as(f32, @floatFromInt(min_y)) + 0.5,
        .z = 0,
    };

    // Get the edgeFunction values at starting pixel, all of these have to match the sign
    // of area for us to draw the pixel, otherwise it's not inside the triangle
    var w0_row = edgeFunction(v2, v3, start); // which side of v2->v3 is start on
    var w1_row = edgeFunction(v3, v1, start); // which side of v3->v1 is start on
    var w2_row = edgeFunction(v1, v2, start); // which sode of v1->v2 is start on

    // Walks down row by row
    var py: isize = min_y;
    while (py <= max_y) : (py += 1) {
        // save the starting values
        var w0 = w0_row;
        var w1 = w1_row;
        var w2 = w2_row;

        // Walks right pixel by pixel
        var px: isize = min_x;
        while (px <= max_x) : (px += 1) {
            // Check if the point p is on or inside the edges of the triangle
            // If all three w*area is bigger or equal to zero, the pixel is on or in the triangle
            if (w0 * area >= 0 and w1 * area >= 0 and w2 * area >= 0) {
                // Cursed expression to get the perspective correct depth at this pixel
                const z = 1.0 / ((w0 * inv_z1 + w1 * inv_z2 + w2 * inv_z3) * inv_area);
                // Dumb fix for z-fighting with road/path
                const z_test = z - db;

                const ux: usize = @intCast(px);
                const uy: usize = @intCast(py);
                // If the depth of whatever is at this pixel is bigger than what we want to draw,
                // that means our new pixel is closer, so we draw it and update the buffer
                if (zb.getDepth(ux, uy) > z_test) {
                    const uPixel = z * (w0 * uv1.u * inv_z1 + w1 * uv2.u * inv_z2 + w2 * uv3.u * inv_z3) * inv_area;
                    const vPixel = z * (w0 * uv1.v * inv_z1 + w1 * uv2.v * inv_z2 + w2 * uv3.v * inv_z3) * inv_area;

                    const color = tb.getColor(uPixel, vPixel);
                    const alpha = color & 0xff;

                    // NOTE: Don't use z_test here, we need the original z distance
                    const final_color = addFog(color, z);

                    if (alpha > 127) {
                        // TODO: Add a param to the function so we can enable/disable dither
                        fb.setPixel(ux, uy, quantizeColor(final_color, ux, uy, true));
                        zb.setDepth(ux, uy, z_test);
                    }
                }
            }
            // add the delta to walk one pixel right
            w0 += dw0_dx;
            w1 += dw1_dx;
            w2 += dw2_dx;
        }
        // add the delta to walk one row down
        w0_row += dw0_dy;
        w1_row += dw1_dy;
        w2_row += dw2_dy;
    }
}

// Essentially does the same thing as edgeFunction, used in main as a helper
pub fn facingAway(v1: Vec3, v2: Vec3, v3: Vec3) bool {
    const edge1 = v2.sub(v1);
    const edge2 = v3.sub(v1);
    return edge1.cross(edge2).z >= 0;
}

pub fn nearPlaneClip(c: [4]?Vec4, uv: [4]?Vec2, near_plane: f32) struct { [4]?Vec4, [4]?Vec2, usize } {
    var new_c: [4]?Vec4 = undefined;
    var new_uv: [4]?Vec2 = undefined;
    var cn: usize = 0;

    for (0..3) |i| {
        const curr_c = c[i].?;
        const next_c = c[(i + 1) % 3].?;

        const curr_uv = uv[i].?;
        const next_uv = uv[(i + 1) % 3].?;

        const curr_in = curr_c.w > near_plane;
        const next_in = next_c.w > near_plane;

        if (curr_in != next_in) {
            const t = (near_plane - curr_c.w) / (next_c.w - curr_c.w);

            new_c[cn] = Vec4{
                .x = curr_c.x + t * (next_c.x - curr_c.x),
                .y = curr_c.y + t * (next_c.y - curr_c.y),
                .z = curr_c.z + t * (next_c.z - curr_c.z),
                .w = near_plane,
            };

            new_uv[cn] = Vec2{
                .u = curr_uv.u + t * (next_uv.u - curr_uv.u),
                .v = curr_uv.v + t * (next_uv.v - curr_uv.v),
            };

            cn += 1;
        }

        if (next_in) {
            new_c[cn] = next_c;
            new_uv[cn] = next_uv;
            cn += 1;
        }
    }

    return .{ new_c, new_uv, cn };
}
