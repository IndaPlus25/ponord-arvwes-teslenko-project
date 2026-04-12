const std = @import("std");
const math = @import("math.zig");

// A loaded 3D model
pub const Model = struct {
    triangles: std.ArrayList([3]math.Vec4),
    allocator: *const std.mem.Allocator,

    pub fn deinit(self: *Model) void {
        self.triangles.deinit(self.allocator.*);
    }
};

// Use to load a 3D model from an .obj file
pub fn loadModel(file_path: []const u8, allocator: *const std.mem.Allocator) !Model {
    // Create arrays
    var vertexes: std.ArrayList(math.Vec4) = .empty;
    var faces: std.ArrayList([3]math.Vec4) = .empty;
    defer vertexes.deinit(allocator.*);

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
        var iter = std.mem.tokenizeAny(u8, str, " \n");
        
        // Check for line type and parse accordingly
        const key = iter.next().?;
        
        if (std.mem.eql(u8, key, "v")) {  // Parse for vertexes
            try vertexes.append(allocator.*, .{
                .x = try std.fmt.parseFloat(f32, iter.next().?),
                .y = try std.fmt.parseFloat(f32, iter.next().?),
                .z = try std.fmt.parseFloat(f32, iter.next().?),
                .w = 1,
            });

        } else if (std.mem.eql(u8, key, "f")) {  // Parse for faces
            // The first element in the sequence
            var anchor_s = std.mem.splitSequence(u8, iter.next().?, "\\\\");  // Split it up by "\\" 
            const anchor_v = try std.fmt.parseInt(u32, anchor_s.next().?, 10);  // Get the vertex data
            // const anchor_n = try std.fmt.parseInt(u32, anchor_s.next().?, 10);  
            // ^ Incomplete example of how you would get face normal data if we were to use it
            // When/If we start using it, uncomment and figure out how to also handle cases where it isn't provided

            // The element previous to iter.next()
            var prev_s = std.mem.splitSequence(u8, iter.next().?, "\\\\");
            var prev_v = try std.fmt.parseInt(u32, prev_s.next().?, 10);

            while (iter.next()) |entry| {
                var curr_s = std.mem.splitSequence(u8, entry, "\\\\");
                const curr_v = try std.fmt.parseInt(u32, curr_s.next().?, 10);

                try faces.append(allocator.*, .{
                    vertexes.items[anchor_v - 1],
                    vertexes.items[prev_v - 1],
                    vertexes.items[curr_v - 1],
                });

                prev_v = curr_v;
            }

        } else if (std.mem.eql(u8, key, "vn")) {  // Parse for normals
            // TODO Implement if we start using vertex normals

        } else if (std.mem.eql(u8, key, "vt")) {  // Parse for textures
            // TODO Implement if we start using texture coordinates

        }
    } else |err| if (err != error.EndOfStream) {
        return err;
    }

    // Return a model
    return Model{ 
        .triangles = faces,
        .allocator = allocator,
    };
}