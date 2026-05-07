// SPDX-FileCopyrightText: 2026 Pontus Nordström, Michael Teslenko, Arvid Westman
// SPDX-License-Identifier: MIT

const std = @import("std");
const render = @import("render.zig");
const math = @import("math.zig");
const objects = @import("objects.zig");

const Object = objects.Object;

// TODO: Look into if there's a better solution than this...
// We need depth bias to avoid z-fighting in these textures
const water_depth_bias: f32 = 0.004;
fn textureDepthBias(texture_id: usize) f32 {
    // Helps water win when it is almost coplanar with riverbed geometry.
    return switch (texture_id) {
        19, 20 => water_depth_bias,
        else => 0.0,
    };
}

// It renders as gray patches so skip for now
fn textureShouldSkip(texture_id: usize) bool {
    return switch (texture_id) {
        19 => true,
        else => false,
    };
}

pub fn renderScene(
    fb: render.FrameBuffer,
    zb: *render.ZBuffer,
    object_list: *std.ArrayList(Object),
    world_camera: *render.Camera,
) struct { u64, u64, u64 } {
    render.drawSky(fb);

    // Construct the camera's forward direction (spherical coordinates, y is polar axis)
    const forward = math.Vec3{
        .x = @cos(world_camera.pitch) * @sin(world_camera.yaw),
        .y = @sin(world_camera.pitch),
        .z = -@cos(world_camera.pitch) * @cos(world_camera.yaw),
    };
    // Point camera at position + forward direction
    const target = world_camera.position.add(forward);

    // Aspect ratio to avoid stretching the image in perspective matrix
    const aspect = @as(f32, @floatFromInt(fb.width)) / @as(f32, @floatFromInt(fb.height));

    // Construct the matrices to transform world space into clip space
    const proj_matrix = math.Mat4.perspective(world_camera.fov, aspect, world_camera.near, world_camera.far);
    const view_matrix = math.Mat4.viewMatrix(world_camera.position, target, world_camera.up);

    // Combine the two into one matrix so each vertex only needs one matrix multiplication
    // (World to view to clip space)
    const vp = proj_matrix.mul(view_matrix);

    var total_triangles: u64 = 0;
    var drawn_triangles: u64 = 0;
    var clipped_triangles: u64 = 0;

    // Loop over all the objects & then every triangle in the object
    for (object_list.*.items) |object| {
        for (object.triangles.items, 0..) |tri_v, tri_index| {
            total_triangles += 1;

            const tex_id: usize = @intCast(object.triangle_groups.items[tri_index]);
            if (textureShouldSkip(tex_id)) continue;
            const tb = object.textures.items[tex_id];
            const db = textureDepthBias(tex_id);

            var ca = [4]?math.Vec4{ // Array of vertexes
                vp.mulVec4(tri_v[0]),
                vp.mulVec4(tri_v[1]),
                vp.mulVec4(tri_v[2]),
                null, // Incase the near face clipping gives us a fourth vertex (quad)
            };

            // use the fog_end as far plane culling distance
            if (ca[0].?.w >= render.fog_end and
                ca[1].?.w >= render.fog_end and
                ca[2].?.w >= render.fog_end)
            {
                continue;
            }

            var cu = [4]?math.Vec2{
                object.triangle_uvs.items[tri_index][0],
                object.triangle_uvs.items[tri_index][1],
                object.triangle_uvs.items[tri_index][2],
                null,
            };

            var cn: usize = 3; // Amount of vertexes that we have
            var did_clip: bool = false; // Whether or not any triangles have been clipped

            if (ca[0].?.w <= world_camera.near or ca[1].?.w <= world_camera.near or ca[2].?.w <= world_camera.near) {
                const x = render.nearPlaneClip(ca, cu, world_camera.near);
                ca = x[0];
                cu = x[1];
                cn = x[2];
                did_clip = true;
            }
            if (cn < 3) continue; // Only continue if we have 3 or more vertexes

            const v1 = ca[0].?.toPixel(fb.width, fb.height);
            const v2 = ca[1].?.toPixel(fb.width, fb.height);
            const v3 = ca[2].?.toPixel(fb.width, fb.height);

            const uv1 = cu[0].?;
            const uv2 = cu[1].?;
            const uv3 = cu[2].?;

            // Skip triangles facing away
            if (render.facingAway(v1, v2, v3)) continue;

            render.fillTriangle(v1, v2, v3, uv1, uv2, uv3, fb, zb, tb, db);

            if (cn == 4) {
                const v4 = ca[3].?.toPixel(fb.width, fb.height);
                const uv4 = cu[3].?;

                render.fillTriangle(v1, v3, v4, uv1, uv3, uv4, fb, zb, tb, db);
                drawn_triangles += 1;
            }

            drawn_triangles += 1;
            if (did_clip) clipped_triangles += cn - 2;
        }
    }

    return .{ total_triangles, drawn_triangles, clipped_triangles };
}
