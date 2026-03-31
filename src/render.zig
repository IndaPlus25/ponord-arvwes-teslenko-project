const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;

pub const FrameBuffer = struct {
    data: [*]u32,
    stride: usize,
    width: c_int,
    height: c_int,

    pub fn setPixel(self: FrameBuffer, x: isize, y: isize, color: u32) void {
        if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
            self.data[@as(usize, @intCast(y)) * self.stride + @as(usize, @intCast(x))] = color;
        }
    }

    pub fn clear(self: FrameBuffer) void {
        @memset(self.data[0 .. self.stride * @as(usize, @intCast(self.height))], 0);
    }
};

pub fn drawTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, color: u32) void {
    drawLine(v1, v2, fb, color);
    drawLine(v1, v3, fb, color);
    drawLine(v2, v3, fb, color);
}

fn floatToPixel(v: f32) isize {
    return @as(isize, @intFromFloat(@round(v)));
}

// TODO: Clean up this code if possible, optimize & test
pub fn drawLine(start: Vec3, end: Vec3, fb: FrameBuffer, color: u32) void {
    var x0 = floatToPixel(start.x);
    var y0 = floatToPixel(start.y);
    const x1 = floatToPixel(end.x);
    const y1 = floatToPixel(end.y);

    const dx: isize = @as(isize, @intCast(@abs(x1 - x0)));
    const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
    const sx: isize = if (x0 < x1) 1 else -1;
    const sy: isize = if (y0 < y1) 1 else -1;

    var err = dx + dy;

    while (true) {
        fb.setPixel(x0, y0, color);

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

// pub fn fillTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, color: u32) void {
// sort the triangles by y-axis
// var p0 = v1;
// var p1 = v2;
// var p2 = v3;
// if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);
// if (p1.y > p2.y) std.mem.swap(Vec3, &p1, &p2);
// if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);
// }
