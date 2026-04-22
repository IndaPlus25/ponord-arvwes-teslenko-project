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
    fov: f32 = 80, // field of view in degrees
    near: f32 = 0.1, // distance to near plane
    far: f32 = 1000.0, // distance to far plane
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
        @memset(self.data, 1.0);
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
        if (x0 >= 0 and y0 >= 0 and x0 <= fb.width and y0 <= fb.height) {
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

pub fn fillTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, zb: *ZBuffer, color: u32) void {
    var p0 = v1;
    var p1 = v2;
    var p2 = v3;
    if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);
    if (p1.y > p2.y) std.mem.swap(Vec3, &p1, &p2);
    if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);

    if (p0.y == p2.y) return; // not a triangle

    fillScanlines(p0, p1, p0, p2, fb, zb, color); // a = p0 -> p1 (short), b = p0 -> p2 (long)
    fillScanlines(p1, p2, p0, p2, fb, zb, color); // a = p1 -> p2 (short), b = p0 -> p2 (long)
}

// TODO: we're drawing the middle vertex twice since both are inclusive, idk if this will cause a problem
// TODO: handle off screen triangles so we don't waste resources
fn fillScanlines(a0: Vec3, a1: Vec3, b0: Vec3, b1: Vec3, fb: FrameBuffer, zb: *ZBuffer, color: u32) void {
    // a is the short edge, b is the long edge
    const a_dy = a1.y - a0.y;
    const b_dy = b1.y - b0.y;
    if (a_dy == 0 or b_dy == 0) return;

    var y = floatToPixel(a0.y);
    const y_end = floatToPixel(a1.y);

    while (y <= y_end) : (y += 1) {
        const fy = @as(f32, @floatFromInt(y));
        const a = Vec3.lerp(a0, a1, (fy - a0.y) / a_dy);
        const b = Vec3.lerp(b0, b1, (fy - b0.y) / b_dy);

        const left = if (a.x < b.x) a else b;
        const right = if (a.x < b.x) b else a;

        var x = floatToPixel(left.x);
        const x_end = floatToPixel(right.x);

        const dy_dx: f32 = if (right.x - left.x > 0)
            (right.z - left.z) / (right.x - left.x)
        else
            0;

        var z = left.z;

        while (x <= x_end) : (x += 1) {
            if (isInBounds(x, y, fb.width, fb.height)) {
                const ux: usize = @intCast(x);
                const uy: usize = @intCast(y);
                if (zb.getDepth(ux, uy) > z) {
                    fb.setPixel(ux, uy, color);
                    zb.setDepth(ux, uy, z);
                }
            }
            z += dy_dx;
        }
    }
}

// Is the triangle facing away from us?
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

pub fn isInBounds(x: isize, y: isize, width: c_int, height: c_int) bool {
    return (x >= 0 and y >= 0 and x <= @as(isize, @intCast(width)) and y <= @as(isize, @intCast(height)));
}
