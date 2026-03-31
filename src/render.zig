const std = @import("std");

// Remove this later and just use a Vec3,
// we can scale x, y with z component
pub const Point2D = struct {
    x: isize,
    y: isize,
};

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

// Draws a hollow triangle between three points using drawLine
pub fn drawTriangle(v1: Point2D, v2: Point2D, v3: Point2D, fb: FrameBuffer, color: u32) void {
    drawLine(v1, v2, fb, color);
    drawLine(v1, v3, fb, color);
    drawLine(v2, v3, fb, color);
}

// TODO: Clean up this code if possible, optimize & test
pub fn drawLine(start: Point2D, end: Point2D, fb: FrameBuffer, color: u32) void {
    var x0 = start.x;
    var y0 = start.y;
    const x1 = end.x;
    const y1 = end.y;

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

// pub fn fillTriangle(v1: Point2D, v2: Point2D, v3: Point2D) void {
// Sort the points by y-axis (edges[0] has the smallest y and is furthest up)
// var edges = [3]Point2D{ v1, v2, v3 };
// if (edges[0].y > edges[1].y) std.mem.swap(Point2D, &edges[0], &edges[1]);
// if (edges[1].y > edges[2].y) std.mem.swap(Point2D, &edges[1], &edges[2]);
// if (edges[0].y > edges[1].y) std.mem.swap(Point2D, &edges[0], &edges[1]);
// }
