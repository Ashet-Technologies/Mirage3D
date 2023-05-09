const std = @import("std");

const Mirage3D = @import("mirage3d.zig");

const COLOR_BLACK = Mirage3D.Color{ .index = 0 };
const COLOR_WHITE = Mirage3D.Color{ .index = 1 };

pub fn main() !void {
    var mirage = try Mirage3D.createContext(std.heap.c_allocator);
    defer mirage.destroy();

    const vertex_format = try mirage.createVertexFormat(.{
        .element_stride = @sizeOf(Vertex),
        .position_offset = @offsetOf(Vertex, "position"),
        .texture_coord_offset = @offsetOf(Vertex, "texcoord"),
        .alpha_offset = @offsetOf(Vertex, "alpha"),
    });
    defer mirage.destroyVertexFormat(vertex_format);

    const pipeline_setup = try mirage.createPipelineConfiguration(.{
        .primitive_type = .triangles,
        .blend_mode = .@"opaque",
        .depth_mode = .normal,
        .vertex_format = vertex_format,
        .index_format = .none,
        .texture_wrap = .wrap,
    });
    defer mirage.destroyPipelineConfiguration(pipeline_setup);

    const vertices = [3]Vertex{
        Vertex{ .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .texcoord = .{ .x = 0.0, .y = 0.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .texcoord = .{ .x = 1.0, .y = 0.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = 1.0, .y = 1.0, .z = 0.0 }, .texcoord = .{ .x = 1.0, .y = 1.0 }, .alpha = 0xFF },
    };

    const vertex_buffer = try mirage.createBuffer(@sizeOf(Vertex) * vertices.len);
    defer mirage.destroyBuffer(vertex_buffer);

    const render_queue = try mirage.createRenderQueue();
    defer mirage.destroyRenderQueue(render_queue);

    try mirage.begin(render_queue);

    try mirage.updateBuffer(render_queue, vertex_buffer, 0, std.mem.sliceAsBytes(&vertices));

    try mirage.clearColorTarget(render_queue, .screen, COLOR_BLACK);

    try mirage.drawTriangles(.{
        .queue = render_queue,
        .color_target = .screen,
        .depth_target = .none,
        .vertex_buffer = vertex_buffer,
        .index_buffer = .none,
        .fill = .{ .uniform = COLOR_WHITE },
        .transform = Mirage3D.identity_matrix,
    });

    try mirage.end(render_queue);
}

const Vertex = struct {
    position: Vector3,
    texcoord: UV,
    alpha: u8,
};

const Vector3 = extern struct { x: f32, y: f32, z: f32 };
const UV = extern struct { x: f16, y: f16 };

comptime {
    // ref all api calls to ensure they are always analyzed:
    _ = Mirage3D.createContext;
    _ = Mirage3D.destroy;
    _ = Mirage3D.createTexture;
    _ = Mirage3D.destroyTexture;
    _ = Mirage3D.updateTexture;
    _ = Mirage3D.fetchTexture;
    _ = Mirage3D.createBuffer;
    _ = Mirage3D.destroyBuffer;
    _ = Mirage3D.updateBuffer;
    _ = Mirage3D.createColorTarget;
    _ = Mirage3D.destroyColorTarget;
    _ = Mirage3D.createDepthTarget;
    _ = Mirage3D.destroyDepthTarget;
    _ = Mirage3D.destroyVertexFormat;
    _ = Mirage3D.createPipelineConfiguration;
    _ = Mirage3D.destroyPipelineConfiguration;
    _ = Mirage3D.createRenderQueue;
    _ = Mirage3D.destroyRenderQueue;
    _ = Mirage3D.begin;
    _ = Mirage3D.end;
    _ = Mirage3D.clearColorTarget;
    _ = Mirage3D.clearDepthTarget;
    _ = Mirage3D.drawTriangles;
}
