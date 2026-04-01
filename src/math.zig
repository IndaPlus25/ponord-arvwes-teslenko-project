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
