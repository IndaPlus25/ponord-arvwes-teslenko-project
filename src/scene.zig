// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const objects = @import("objects.zig");

pub const Scene = struct {
    objects: std.ArrayList(objects.Object),

    pub fn deinit(self: *Scene, allocator: std.mem.Allocator) void {
        for (self.objects.items) |*object| {
            object.deinit();
        }

        self.objects.deinit(allocator);
    }
};

pub fn loadKokiriForest(allocator: std.mem.Allocator) !Scene {
    var kokiri_model = try objects.loadModel("assets/models/Kokiri Forest/KF.obj", &allocator);
    errdefer kokiri_model.deinit();

    const world_scale: f32 = 0.05;

    for (kokiri_model.triangles.items) |*tri| {
        for (0..3) |i| {
            tri[i].x *= world_scale;
            tri[i].y *= world_scale;
            tri[i].z *= world_scale;
        }
    }

    var object_list: std.ArrayList(objects.Object) = .empty;
    errdefer object_list.deinit(allocator);

    var kokiri_obj = try objects.Object.init(kokiri_model, &allocator);
    kokiri_obj.moveTo(0, 0, 0);

    try object_list.append(allocator, kokiri_obj);

    return .{
        .objects = object_list,
    };
}
