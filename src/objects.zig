const std = @import("std");
const math = @import("math.zig");

// An object with a position
pub const Object = struct {
    x: f32,
    y: f32,
    z: f32,

    triangles: std.ArrayList([3]math.Vec4),
    triangle_uvs: std.ArrayList([3][2]f32),
    triangle_groups: std.ArrayList(u32),
    allocator: *const std.mem.Allocator,

    pub fn init(model: Model, allocator: *const std.mem.Allocator) !Object {
        return .{
            .x = 0,
            .y = 0,
            .z = 0,
            .triangles = try model.triangles.clone(allocator.*),
            .triangle_uvs = try model.triangle_uvs.clone(allocator.*),
            .triangle_groups = try model.triangle_groups.clone(allocator.*),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Object) void {
        self.triangles.deinit(self.allocator.*);
        self.triangle_uvs.deinit(self.allocator.*);
        self.triangle_groups.deinit(self.allocator.*);
    }

    // Move object by a vector
    // TODO Refactor to accept a Vec3 or Vec4 as position
    pub fn moveBy(self: *Object, x: f32, y: f32, z: f32) void {
        // Update internal position
        self.x += x;
        self.y += y;
        self.z += z;

        // Update position of every triangle
        for (0..self.*.triangles.items.len) |i| {
            // Get old vectors
            var vecs: [3]math.Vec4 = self.*.triangles.items[i];

            // Loop over and update vectors
            for (vecs, 0..) |vec, j| {
                vecs[j] = .{
                    .x = vec.x + x,
                    .y = vec.y + y,
                    .z = vec.z + z,
                    .w = 1,
                };
            }

            // Set triangle to updated version
            self.*.triangles.items[i] = vecs;
        }
    }

    // Move object to a position
    // TODO Refactor to accept a Vec3 or Vec4 as position
    pub fn moveTo(self: *Object, x: f32, y: f32, z: f32) void {
        // Calculate difference and just "moveBy"
        self.moveBy(
            x - self.x,
            y - self.y,
            z - self.z,
        );
    }

    // TODO Add functions for rotating object
};

// A loaded 3D model
pub const Model = struct {
    triangles: std.ArrayList([3]math.Vec4),
    triangle_uvs: std.ArrayList([3][2]f32),
    triangle_groups: std.ArrayList(u32),
    allocator: *const std.mem.Allocator,

    pub fn deinit(self: *Model) void {
        self.triangles.deinit(self.allocator.*);
        self.triangle_uvs.deinit(self.allocator.*);
        self.triangle_groups.deinit(self.allocator.*);
    }
};

// Use to load a 3D model from an .obj file
pub fn loadModel(file_path: []const u8, allocator: *const std.mem.Allocator) !Model {
    // Create arrays
    var vertexes: std.ArrayList(math.Vec4) = .empty;
    var uvs: std.ArrayList([2]f32) = .empty;
    var faces: std.ArrayList([3]math.Vec4) = .empty;
    var face_uvs: std.ArrayList([3][2]f32) = .empty;
    var face_groups: std.ArrayList(u32) = .empty;
    defer vertexes.deinit(allocator.*);
    defer uvs.deinit(allocator.*);

    var group_idx: u32 = 0;

    // Get file reader
    var line_buf: [64]u8 = undefined;
    var file: std.fs.File = try std.fs.cwd().openFile(
        file_path,
        .{ .mode = .read_only },
    );
    defer file.close();
    var file_reader: std.fs.File.Reader = file.reader(&line_buf);

    // Iterate over and parse each line
    while (file_reader.interface.takeDelimiterInclusive('\n')) |str| {

        // Tokenize line by whitespace and linebreaks
        var iter = std.mem.tokenizeAny(u8, str, " \n\r\t");

        // Check for line type and parse accordingly
        const nxt = iter.next();
        if (nxt == null) continue; // Means that we have a blank line
        const key = nxt.?;

        if (std.mem.eql(u8, key, "v")) { // Parse for vertexes
            try vertexes.append(allocator.*, .{
                .x = try std.fmt.parseFloat(f32, iter.next().?),
                .y = try std.fmt.parseFloat(f32, iter.next().?),
                .z = try std.fmt.parseFloat(f32, iter.next().?),
                .w = 1,
            });
        } else if (std.mem.eql(u8, key, "f")) { // Parse for faces
            // The first element in the sequence
            var anchor_s = std.mem.splitSequence(u8, iter.next().?, "/"); // Split it up by "/"
            const anchor_v = try std.fmt.parseInt(u32, anchor_s.next().?, 10); // Get the vertex data
            const anchor_uv = try std.fmt.parseInt(u32, anchor_s.next().?, 10);

            // The element previous to iter.next()
            var prev_s = std.mem.splitSequence(u8, iter.next().?, "/");
            var prev_v = try std.fmt.parseInt(u32, prev_s.next().?, 10);
            var prev_uv = try std.fmt.parseInt(u32, prev_s.next().?, 10);

            while (iter.next()) |entry| {
                var curr_s = std.mem.splitSequence(u8, entry, "/");
                const curr_v = try std.fmt.parseInt(u32, curr_s.next().?, 10);
                const curr_uv = try std.fmt.parseInt(u32, curr_s.next().?, 10);

                try faces.append(allocator.*, .{
                    vertexes.items[anchor_v - 1],
                    vertexes.items[prev_v - 1],
                    vertexes.items[curr_v - 1],
                });

                try face_uvs.append(allocator.*, .{
                    uvs.items[anchor_uv - 1],
                    uvs.items[prev_uv - 1],
                    uvs.items[curr_uv - 1],
                });

                try face_groups.append(allocator.*, group_idx);

                prev_v = curr_v;
                prev_uv = curr_uv;
            }
        } else if (std.mem.eql(u8, key, "usemtl")) { // new group
            group_idx += 1;
        } else if (std.mem.eql(u8, key, "vt")) { // Parse for textures
            const u = try std.fmt.parseFloat(f32, iter.next().?);
            const v = try std.fmt.parseFloat(f32, iter.next().?);
            try uvs.append(allocator.*, .{ u, v });
        }
    } else |err| if (err != error.EndOfStream) {
        return err;
    }

    // Return a model
    return Model{
        .triangles = faces,
        .triangle_uvs = face_uvs,
        .triangle_groups = face_groups,
        .allocator = allocator,
    };
}
