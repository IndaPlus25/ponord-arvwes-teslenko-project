const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const Camera = struct {
    look: Vec3,
    position: Vec3,
    fov: f32, // radian?
    up: Vec3,
    // z_far (z-buffer?)
    // z_near:

    pub fn new() Camera {
        Camera{
            .look = .{ .x = 0, .y = 0, .z = 2 },
            .position = .{ .x = 0, .y = 0, .z = 0 },
            .fov = 80.0, // ???
            .up = .{ .x = 0, .y = 1, .z = 0 },
        };
    }
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

pub fn drawTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, color: u32) void {
    drawLine(v1, v2, fb, color);
    drawLine(v1, v3, fb, color);
    drawLine(v2, v3, fb, color);
}

fn floatToPixel(v: f32) isize {
    return @as(isize, @intFromFloat(@round(v)));
}

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

pub fn fillTriangle(v1: Vec3, v2: Vec3, v3: Vec3, fb: FrameBuffer, color: u32) void {
    var p0 = v1;
    var p1 = v2;
    var p2 = v3;
    if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);
    if (p1.y > p2.y) std.mem.swap(Vec3, &p1, &p2);
    if (p0.y > p1.y) std.mem.swap(Vec3, &p0, &p1);

    if (p0.y == p2.y) return; // not a triangle

    fillScanlines(p0, p1, p0, p2, fb, color); // a = p0 -> p1 (short), b = p0 -> p2 (long)
    fillScanlines(p1, p2, p0, p2, fb, color); // a = p1 -> p2 (short), b = p0 -> p2 (long)
}

// TODO: we're drawing the middle vertex twice since both are inclusive, idk if this will cause a problem
// TODO: handle off screen triangles so we don't waste resources
// TODO: we probably want to clamp the t value for lerp so it doesnt go negative or bigger than 1
fn fillScanlines(a0: Vec3, a1: Vec3, b0: Vec3, b1: Vec3, fb: FrameBuffer, color: u32) void {
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

        var x = floatToPixel(@min(a.x, b.x));
        const x_end = floatToPixel(@max(a.x, b.x));
        while (x <= x_end) : (x += 1) {
            fb.setPixel(x, y, color);
        }
    }
}

pub fn cullTriangle(v1: Vec3, v2: Vec3, v3: Vec3, camera_pos: Vec3) bool {
    const l1 = v2.sub(v1);
    const l2 = v3.sub(v1);
    // normal n, following CCW winding order
    const n = l1.cross(l2);
    //if triangle face is rotated 90 degrees or less from the camera. => normal pointing away from camera
    if ((v1.sub(camera_pos).dot(n)) >= 0) {
        return true;
    }
    return false;
}
