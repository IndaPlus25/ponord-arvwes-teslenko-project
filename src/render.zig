const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const Camera = struct {
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 }, // world pos
    target: Vec3 = .{ .x = 0, .y = 0, .z = -1 }, // looking at
    up: Vec3 = .{ .x = 0, .y = 1, .z = 0 }, // y is up dir
    fov: f32 = 80, // degrees
    near: f32 = 0.1, // distance to near plane
    far: f32 = 1000.0, // distance to far plane
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
};

pub fn drawTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, color: u32) void {
    drawLine(v1, v2, fb, color);
    drawLine(v1, v3, fb, color);
    drawLine(v2, v3, fb, color);
}

fn floatToPixel(v: f32) usize {
    return @as(usize, @intFromFloat(@round(v)));
}

pub fn drawLine(start: Vec3, end: Vec3, fb: FrameBuffer, color: u32) void {
    var x0: isize = @intCast(floatToPixel(start.x));
    var y0: isize = @intCast(floatToPixel(start.y));
    const x1: isize = @intCast(floatToPixel(end.x));
    const y1: isize = @intCast(floatToPixel(end.y));

    const dx: isize = @as(isize, @intCast(@abs(x1 - x0)));
    const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
    const sx: isize = if (x0 < x1) 1 else -1;
    const sy: isize = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        fb.setPixel(@intCast(x0), @intCast(y0), color);

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
            if (zb.getDepth(x, y) > z) {
                fb.setPixel(x, y, color);
                zb.setDepth(x, y, z);
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
