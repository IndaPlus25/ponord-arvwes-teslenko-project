const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn mul(self: Vec3, scalar: f32) Vec3 {
        return .{ .x = self.x * scalar, .y = self.y * scalar, .z = self.z * scalar };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return (self.x * other.x) + (self.y * other.y) + (self.z * other.z);
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.y * other.z - self.z * other.y, .y = self.z * other.x - self.x * other.z, .z = self.x * other.y - self.y * other.x };
    }

    pub fn len(self: Vec3) f32 {
        return @sqrt(self.dot(self));
    }

    pub fn proj(u: Vec3, v: Vec3) Vec3 {
        return v.mul(u.dot(v) / v.dot(v));
    }

    pub fn norm(self: Vec3) Vec3 {
        return self.mul(1.0 / self.len());
    }

    pub fn lerp(u: Vec3, v: Vec3, t: f32) Vec3 {
        return v.sub(u).mul(t).add(u);
    }
};

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32, // 0 or 1 depending on direction or point

    // Point has w = 1
    pub fn point(x: f32, y: f32, z: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = 1 };
    }

    // Direction has w = 0
    pub fn direction(x: f32, y: f32, z: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = 0 };
    }

    pub fn toVec3(self: Vec4) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = self.z };
    }

    pub fn toPixel(self: Vec4, fb_w: c_int, fb_h: c_int) Vec3 {
        // After projection we have our vectors in clip space
        // We normalize the vectors by multiplying with 1/self.w
        const inverse = 1.0 / self.w;

        return .{
            .x = (self.x * inverse + 1) * 0.5 * @as(f32, @floatFromInt(fb_w)),
            .y = (self.y * inverse + 1) * 0.5 * @as(f32, @floatFromInt(fb_h)),
            .z = (self.z * inverse + 1) * 0.5,
        };
    }
};

pub const Mat4 = struct {
    rows: [4]Vec4,

    pub fn mulVec4(self: Mat4, v: Vec4) Vec4 {
        return .{
            .x = self.rows[0].x * v.x + self.rows[0].y * v.y + self.rows[0].z * v.z + self.rows[0].w * v.w,
            .y = self.rows[1].x * v.x + self.rows[1].y * v.y + self.rows[1].z * v.z + self.rows[1].w * v.w,
            .z = self.rows[2].x * v.x + self.rows[2].y * v.y + self.rows[2].z * v.z + self.rows[2].w * v.w,
            .w = self.rows[3].x * v.x + self.rows[3].y * v.y + self.rows[3].z * v.z + self.rows[3].w * v.w,
        };
    }

    pub fn identity() Mat4 {
        return .{ .rows = .{
            .{ .x = 1, .y = 0, .z = 0, .w = 0 },
            .{ .x = 0, .y = 1, .z = 0, .w = 0 },
            .{ .x = 0, .y = 0, .z = 1, .w = 0 },
            .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        } };
    }

    // Cursed transform matrix taken from
    // https://www.scratchapixel.com/lessons/3d-basic-rendering/perspective-and-orthographic-projection-matrix/building-basic-perspective-projection-matrix.html
    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const s = 1.0 / @tan(fov / 2.0 * std.math.pi / 180.0);
        return .{ .rows = .{
            .{ .x = s / aspect, .y = 0, .z = 0, .w = 0 },
            .{ .x = 0, .y = s, .z = 0, .w = 0 },
            .{ .x = 0, .y = 0, .z = -far / (far - near), .w = -(far * near) / (far - near) },
            .{ .x = 0, .y = 0, .z = -1, .w = 0 },
        } };
    }
};
