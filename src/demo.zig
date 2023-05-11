const std = @import("std");

const Mirage3D = @import("mirage3d.zig");
const ProxyHead = @import("ProxyHead");

const COLOR_BLACK = Mirage3D.Color{ .index = 0 };
const COLOR_GRAY = Mirage3D.Color{ .index = 128 };
const COLOR_WHITE = Mirage3D.Color{ .index = 255 };

const TARGET_WIDTH = 80;
const TARGET_HEIGHT = 60;

pub fn main() !void {
    var head = try ProxyHead.open();
    defer head.close();

    const framebuffer = try head.requestFramebuffer(.index8, 80, 60, 200 * std.time.ns_per_ms);

    if (comptime (@sizeOf(@TypeOf(framebuffer.base[0])) != @sizeOf(Mirage3D.Color)))
        @compileError("Configuration mismatch!");

    const vertices = [3]Vertex{
        Vertex{ .position = .{ .x = -0.75, .y = -0.75, .z = 0.0 }, .texcoord = .{ .x = 0.0, .y = 0.0 }, .alpha = 0x00 },
        Vertex{ .position = .{ .x = 0.75, .y = -0.75, .z = 0.0 }, .texcoord = .{ .x = 1.0, .y = 0.0 }, .alpha = 0x80 },
        Vertex{ .position = .{ .x = 0.75, .y = 0.75, .z = 0.0 }, .texcoord = .{ .x = 1.0, .y = 1.0 }, .alpha = 0xFF },
    };

    // const offscreen_target_bitmap = try std.heap.c_allocator.alloc(Mirage3D.Color, TARGET_WIDTH * TARGET_HEIGHT);
    // defer std.heap.c_allocator.free(offscreen_target_bitmap);

    var mirage = try Mirage3D.createContext(std.heap.c_allocator);
    defer mirage.destroy();

    // resource setup

    const vertex_format = try mirage.createVertexFormat(.{
        .element_stride = @sizeOf(Vertex),
        .position_offset = @offsetOf(Vertex, "position"),
        .texture_coord_offset = @offsetOf(Vertex, "texcoord"),
        .alpha_offset = @offsetOf(Vertex, "alpha"),
    });
    defer mirage.destroyVertexFormat(vertex_format);

    const pipeline_setup = try mirage.createPipelineConfiguration(.{
        .blend_mode = .alpha_to_coverage,
        .depth_mode = .normal,
        .vertex_format = vertex_format,
        .index_format = .none,
        .texture_wrap = .wrap,
    });
    defer mirage.destroyPipelineConfiguration(pipeline_setup);

    const vertex_buffer = try mirage.createBuffer(@sizeOf(Vertex) * vertices.len);
    defer mirage.destroyBuffer(vertex_buffer);

    const target_texture = try mirage.createTexture(TARGET_WIDTH, TARGET_HEIGHT);
    defer mirage.destroyTexture(target_texture);

    const color_target = try mirage.createColorTarget(target_texture, 0, 0, TARGET_WIDTH, TARGET_HEIGHT);
    defer mirage.destroyColorTarget(color_target);

    const render_queue = try mirage.createRenderQueue();
    defer mirage.destroyRenderQueue(render_queue);

    var t: f32 = 0.0;

    while (!head.input.keyboard.escape) {
        defer t += 0.1;

        var matrix: Mirage3D.Matrix4 = .{
            .{ @sin(0.3 * t), -@cos(t), 0, 0 },
            .{ @cos(0.3 * t), @sin(t), 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        };

        // render pass:
        {
            try mirage.begin(render_queue);

            try mirage.updateBuffer(render_queue, vertex_buffer, 0, std.mem.sliceAsBytes(&vertices));

            try mirage.clearColorTarget(render_queue, color_target, COLOR_BLACK);

            try mirage.drawTriangles(.{
                .queue = render_queue,

                .configuration = pipeline_setup,

                .color_target = color_target,
                .depth_target = .none,

                .vertex_buffer = vertex_buffer,
                .index_buffer = .none,

                .primitive_type = .triangles,
                .front_fill = .{ .uniform = COLOR_WHITE },
                .back_fill = .{ .wireframe = COLOR_GRAY },
                .transform = matrix,
            });

            try mirage.fetchTexture(
                render_queue,
                target_texture,
                0,
                0,
                @intCast(u16, framebuffer.width),
                @intCast(u16, framebuffer.height),
                framebuffer.stride,
                @ptrCast([]Mirage3D.Color, framebuffer.base[0 .. framebuffer.stride * framebuffer.height]),
            );

            try mirage.end(render_queue);
        }

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    // // Writeout offscreen_target_bitmap data as RGB encoded image
    // {
    //     var f = try std.fs.cwd().createFile("test-render.pgm", .{});
    //     defer f.close();

    //     try f.writer().print("P5 {} {} 255\n", .{
    //         TARGET_WIDTH,
    //         TARGET_HEIGHT,
    //     });
    //     try f.writeAll(std.mem.sliceAsBytes(offscreen_target_bitmap));
    // }
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
