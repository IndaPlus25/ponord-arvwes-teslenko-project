const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");

const Vec4 = @import("math.zig").Vec4;
const Mat4 = @import("math.zig").Mat4;

test "testing mat4 vec4 multiplication" {
    const vec: Vec4 = .{ .x = 4, .y = 5, .z = 3, .w = 1 };
    const mat: Mat4 = Mat4.identity();
    const result = mat.mulVec4(vec);

    try std.testing.expectEqual(vec, result);
}
