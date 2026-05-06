const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const Camera = struct {
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 }, // initial world pos
    yaw: f32 = 0, // rotation around the up vector (left/right) in radians
    pitch: f32 = 0, // rotation around the camera right axis (up/down) in radians
    sensitivity: f32 = 0.002, // mouse sensitivity
    up: Vec3 = .{ .x = 0, .y = 1, .z = 0 }, // y is up dir
    fov: f32 = 60, // field of view in degrees
    near: f32 = 0.1, // distance to near plane
    far: f32 = 20000.0, // distance to far plane
};

pub const WorldLighting = struct {
    ambient: f32 = 0.3,
    light_sources: []const LightSource,
    pub fn SkyDirection() Vec3 {
        return .{ .x = 0, .y = 1, .z = 0 };
    }
    //returns a scalefactor 0..=1 based on avg brightnes on the given triangle
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
    stride: usize,
    width: c_int,
    height: c_int,

    pub fn setPixel(self: FrameBuffer, x: usize, y: usize, color: u32) void {
        if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
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
        @memset(self.data, 20000.0);  // Should be the same as Camera.far, or larger
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

pub fn drawTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, zb: *ZBuffer, color: u32) void {
    drawLine(v1, v2, fb, zb, color);
    drawLine(v1, v3, fb, zb, color);
    drawLine(v2, v3, fb, zb, color);
}

fn floatToPixel(v: f32) isize {
    return @as(isize, @intFromFloat(@round(v)));
}

pub fn drawLine(start: Vec3, end: Vec3, fb: FrameBuffer, zb: *ZBuffer, color: u32) void {
    var x0: isize = (floatToPixel(start.x));
    var y0: isize = (floatToPixel(start.y));
    var z0: f32 = start.z;
    const x1: isize = (floatToPixel(end.x));
    const y1: isize = (floatToPixel(end.y));
    const z1: f32 = end.z;

    const dx: isize = @as(isize, @intCast(@abs(x1 - x0)));
    const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
    const dz: f32 = z1 - z0;

    const sx: isize = if (x0 < x1) 1 else -1;
    const sy: isize = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    const steps: f32 = @floatFromInt(if (dx >= -dy) dx else -dy);
    const dz_dsteps: f32 = if (steps > 0) dz / steps else 0.0;

    while (true) {
        if (x0 >= 0 and y0 >= 0 and x0 < fb.width and y0 < fb.height) {
            const ux0: usize = @intCast(x0);
            const uy0: usize = @intCast(y0);
            if (zb.getDepth(ux0, uy0) > z0) {
                fb.setPixel(ux0, uy0, color);
                zb.setDepth(ux0, uy0, z0);
            }
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
        z0 += dz_dsteps;
    }
}

fn edgeFunction(a: Vec3, b: Vec3, c: Vec3) f32 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

// https://github.com/ssloy/tinyrenderer/wiki/Lesson-2:-Triangle-rasterization-and-back-face-culling
// https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/perspective-correct-interpolation-vertex-attributes.html
// https://fgiesen.wordpress.com/2013/02/08/triangle-rasterization-in-practice/
pub fn fillTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, zb: *ZBuffer, color: u32) void {
    const min_x_f = @min(v1.x, @min(v2.x, v3.x));
    const min_y_f = @min(v1.y, @min(v2.y, v3.y));
    const max_x_f = @max(v1.x, @max(v2.x, v3.x));
    const max_y_f = @max(v1.y, @max(v2.y, v3.y));

    var min_x: isize = @intFromFloat(@floor(min_x_f));
    var min_y: isize = @intFromFloat(@floor(min_y_f));
    var max_x: isize = @intFromFloat(@ceil(max_x_f));
    var max_y: isize = @intFromFloat(@ceil(max_y_f));

    min_x = @max(min_x, 0);
    min_y = @max(min_y, 0);
    max_x = @min(max_x, @as(isize, @intCast(fb.width)) - 1);
    max_y = @min(max_y, @as(isize, @intCast(fb.height)) - 1);

    const tri_area = edgeFunction(v1, v2, v3);
    if (tri_area == 0) return; // not a triangle

    // Optimization by precalculating a bunch of stuff
    const inv_area = 1.0 / tri_area;
    const inv_z1 = 1.0 / v1.z;
    const inv_z2 = 1.0 / v2.z;
    const inv_z3 = 1.0 / v3.z;

    const dw0_dx = v2.y - v3.y;
    const dw0_dy = v3.x - v2.x;
    const dw1_dx = v3.y - v1.y;
    const dw1_dy = v1.x - v3.x;
    const dw2_dx = v1.y - v2.y;
    const dw2_dy = v2.x - v1.x;

    const start = Vec3{ .x = @floatFromInt(min_x), .y = @floatFromInt(min_y), .z = 0 };
    var w0_row = edgeFunction(v2, v3, start);
    var w1_row = edgeFunction(v3, v1, start);
    var w2_row = edgeFunction(v1, v2, start);

    var py: isize = min_y;
    while (py <= max_y) : (py += 1) {
        var w0 = w0_row;
        var w1 = w1_row;
        var w2 = w2_row;

        var px: isize = min_x;
        while (px <= max_x) : (px += 1) {
            // Check if the point p is on or inside the edges of the triangle
            // We multiply by area to fix CCW since our toPixel function flips y in screen space
            if (w0 * tri_area >= 0 and w1 * tri_area >= 0 and w2 * tri_area >= 0) {
                // Perspective correct z
                const z = 1.0 / ((w0 * inv_z1 + w1 * inv_z2 + w2 * inv_z3) * inv_area);
                const ux: usize = @intCast(px);
                const uy: usize = @intCast(py);
                if (zb.getDepth(ux, uy) > z) {
                    fb.setPixel(ux, uy, color);
                    zb.setDepth(ux, uy, z);
                }
            }
            w0 += dw0_dx;
            w1 += dw1_dx;
            w2 += dw2_dx;
        }
        w0_row += dw0_dy;
        w1_row += dw1_dy;
        w2_row += dw2_dy;
    }
}

pub fn facingAway(v1: Vec3, v2: Vec3, v3: Vec3) bool {
    const edge1 = v2.sub(v1);
    const edge2 = v3.sub(v1);
    return edge1.cross(edge2).z >= 0;
}

pub fn multiplyRgb(color: u32, factor: f32) u32 {
    // 1. Extract the individual channels using bitwise operations
    const r = (color >> 24) & 0xFF;
    const g = (color >> 16) & 0xFF;
    const b = (color >> 8) & 0xFF;
    const a = color & 0xFF;

    // 2. Convert to f32, multiply, and clamp
    // We use std.math.clamp to ensure the float stays between 0.0 and 255.0
    const new_r_f = std.math.clamp(@as(f32, @floatFromInt(r)) * factor, 0.0, 255.0);
    const new_g_f = std.math.clamp(@as(f32, @floatFromInt(g)) * factor, 0.0, 255.0);
    const new_b_f = std.math.clamp(@as(f32, @floatFromInt(b)) * factor, 0.0, 255.0);

    // 3. Convert back to u32
    // @intFromFloat implicitly truncates the decimal portion
    const new_r: u32 = @intFromFloat(new_r_f);
    const new_g: u32 = @intFromFloat(new_g_f);
    const new_b: u32 = @intFromFloat(new_b_f);

    // 4. Shift the channels back to their positions and combine them
    return (new_r << 24) | (new_g << 16) | (new_b << 8) | a;
}
