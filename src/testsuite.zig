const std = @import("std");
const Mirage3D = @import("Mirage3D.zig");

test "create context" {
    var ctx = try Mirage3D.createContext(std.testing.allocator);
    defer ctx.destroy();
}

test "create and destroy vertex formats" {
    var ctx = try Mirage3D.createContext(std.testing.allocator);
    defer ctx.destroy();

    const configs = [_]Mirage3D.VertexFormatDescription{
        .{ .element_stride = 24, .position_offset = 0, .texture_coord_offset = null, .alpha_offset = null },
        .{ .element_stride = 24, .position_offset = 0, .texture_coord_offset = 8, .alpha_offset = null },
        .{ .element_stride = 24, .position_offset = 0, .texture_coord_offset = null, .alpha_offset = 8 },
    };

    for (configs) |cfg| {
        const vertex_format = try ctx.createVertexFormat(cfg);
        ctx.destroyVertexFormat(vertex_format);
    }
}

test "create and destroy all possible pipeline configurations" {
    var ctx = try Mirage3D.createContext(std.testing.allocator);
    defer ctx.destroy();

    const vertex_format = try ctx.createVertexFormat(.{ .element_stride = 16, .position_offset = 0, .texture_coord_offset = null, .alpha_offset = null });
    ctx.destroyVertexFormat(vertex_format);

    for (std.enums.values(Mirage3D.BlendMode)) |blend_mode| {
        for (std.enums.values(Mirage3D.DepthMode)) |depth_mode| {
            for (std.enums.values(Mirage3D.IndexFormat)) |index_format| {
                for (std.enums.values(Mirage3D.TextureWrapMode)) |texture_wrap| {
                    var pipeline = try ctx.createPipelineConfiguration(.{
                        .blend_mode = blend_mode,
                        .depth_mode = depth_mode,
                        .index_format = index_format,
                        .texture_wrap = texture_wrap,
                        .vertex_format = vertex_format,
                    });
                    ctx.destroyPipelineConfiguration(pipeline);
                }
            }
        }
    }
}
