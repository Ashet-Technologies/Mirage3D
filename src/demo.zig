const std = @import("std");
const zlm = @import("zlm");

const Mirage3D = @import("Mirage3D");
const ProxyHead = @import("ProxyHead");

const COLOR_BLACK = Mirage3D.Color{ .index = 0 };
const COLOR_GRAY = Mirage3D.Color{ .index = 128 };
const COLOR_WHITE = Mirage3D.Color{ .index = 255 };

const TARGET_WIDTH = 400;
const TARGET_HEIGHT = 300;

pub fn main() !void {
    var head = try ProxyHead.open();
    defer head.close();

    const framebuffer = try head.requestFramebuffer(.index8, TARGET_WIDTH, TARGET_HEIGHT, 200 * std.time.ns_per_ms);

    if (comptime (@sizeOf(@TypeOf(framebuffer.base[0])) != @sizeOf(Mirage3D.Color)))
        @compileError("Configuration mismatch!");

    const L = -1.0;
    const P = 1.0;

    // Faces are CCW:
    //    6---------7
    //   /|        /|
    //  / |       / |
    // 4---------5  |
    // |  |      |  |
    // |  2 -----|- 3
    // | /       | /
    // |/        |/
    // 0---------1

    const vertices = [8]Vertex{
        Vertex{ .position = .{ .x = L, .y = L, .z = L }, .texcoord = .{ .x = 0.0, .y = 0.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = L, .y = L, .z = P }, .texcoord = .{ .x = 1.0, .y = 0.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = L, .y = P, .z = L }, .texcoord = .{ .x = 0.0, .y = 1.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = L, .y = P, .z = P }, .texcoord = .{ .x = 1.0, .y = 1.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = P, .y = L, .z = L }, .texcoord = .{ .x = 1.0, .y = 1.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = P, .y = L, .z = P }, .texcoord = .{ .x = 0.0, .y = 1.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = P, .y = P, .z = L }, .texcoord = .{ .x = 1.0, .y = 0.0 }, .alpha = 0xFF },
        Vertex{ .position = .{ .x = P, .y = P, .z = P }, .texcoord = .{ .x = 0.0, .y = 0.0 }, .alpha = 0xFF },
    };

    const indices = [6 * 3 * 2]u8{
        // bot
        0, 2, 1,
        2, 3, 1,

        // top
        4, 5, 7,
        7, 6, 4,

        // right
        1, 3, 7,
        7, 5, 1,

        // left
        0, 4, 6,
        6, 2, 0,

        // front
        0, 1, 5,
        5, 4, 0,

        // back
        2, 6, 7,
        7, 3, 2,
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
        .blend_mode = .@"opaque", // .alpha_to_coverage,
        .depth_mode = .normal,
        .vertex_format = vertex_format,
        .index_format = .u8,
        .texture_wrap = .wrap,
    });
    defer mirage.destroyPipelineConfiguration(pipeline_setup);

    const vertex_buffer = try mirage.createBuffer(@sizeOf(Vertex) * vertices.len);
    defer mirage.destroyBuffer(vertex_buffer);

    const index_buffer = try mirage.createBuffer(@sizeOf(u8) * indices.len);
    defer mirage.destroyBuffer(index_buffer);

    const target_texture = try mirage.createTexture(TARGET_WIDTH, TARGET_HEIGHT);
    defer mirage.destroyTexture(target_texture);

    const surface_texture = try mirage.createTexture(64, 64);
    defer mirage.destroyTexture(surface_texture);

    const color_target = try mirage.createColorTarget(target_texture, 0, 0, TARGET_WIDTH, TARGET_HEIGHT);
    defer mirage.destroyColorTarget(color_target);

    const depth_target = try mirage.createDepthTarget(TARGET_WIDTH, TARGET_HEIGHT, .@"16 bit");
    defer mirage.destroyDepthTarget(depth_target);

    const render_queue = try mirage.createRenderQueue();
    defer mirage.destroyRenderQueue(render_queue);

    var t: f32 = 0.0;
    var paused = true;

    while (!head.input.keyboard.escape) {
        defer if (!paused) {
            t += 0.05;
        };

        if (head.input.keyboard.space) {
            while (head.input.keyboard.space) {}
            paused = !paused;
        }

        var rot_mat = zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, t);
        var view_mat = zlm.Mat4.createLookAt(
            zlm.vec3(0, 3, -5),
            zlm.vec3(0, 0, 0),
            zlm.Vec3.unitY,
        );
        var proj_mat = zlm.Mat4.createPerspective(
            zlm.toRadians(60.0),
            @as(f32, TARGET_WIDTH) / TARGET_HEIGHT,
            1.0,
            10000.0,
        );

        var world_view_proj_mat = zlm.Mat4.batchMul(&.{ rot_mat, view_mat, proj_mat });

        const matrix: Mirage3D.Matrix4 = world_view_proj_mat.fields;

        // var matrix: Mirage3D.Matrix4 = .{
        //     .{ @sin(0.3 * t), -@cos(t), 0, 0 },
        //     .{ @cos(0.3 * t), @sin(t), 0, 0 },
        //     .{ 0, 0, 1, 0 },
        //     .{ 0, 0, 0, 1 },
        // };

        // render pass:
        {
            try mirage.begin(render_queue);

            try mirage.updateTexture(render_queue, surface_texture, 0, 0, 64, 64, 64, @ptrCast(*const [4096]Mirage3D.Color, &tile_pattern_64x64));

            try mirage.updateBuffer(render_queue, vertex_buffer, 0, std.mem.sliceAsBytes(&vertices));
            try mirage.updateBuffer(render_queue, index_buffer, 0, std.mem.sliceAsBytes(&indices));

            try mirage.clearColorTarget(render_queue, color_target, COLOR_BLACK);
            try mirage.clearDepthTarget(render_queue, depth_target, 1.0);

            try mirage.drawTriangles(.{
                .queue = render_queue,

                .configuration = pipeline_setup,

                .color_target = color_target,
                .depth_target = depth_target,

                .vertex_buffer = vertex_buffer,
                .index_buffer = index_buffer,

                .primitive_type = .triangles,
                .front_fill = .{ .textured = surface_texture },
                .back_fill = .{ .uniform = COLOR_GRAY },
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

        std.time.sleep(50 * std.time.ns_per_ms);
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

const tile_pattern_64x64 = [64 * 64]u8{
    108, 101, 118, 203, 204, 206, 207, 209, 211, 213, 214, 216, 217, 219, 221, 223, 224, 226, 191, 96,  101, 101, 101, 85,  191, 204, 205, 207, 209, 210, 212, 214,
    215, 217, 219, 220, 222, 224, 225, 224, 95,  101, 101, 101, 101, 154, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 226, 150, 101, 99,
    109, 102, 119, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 226, 192, 97,  102, 102, 102, 87,  192, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 213, 215, 217, 218, 220, 222, 223, 225, 226, 151, 102, 100,
    143, 142, 133, 196, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 224, 226, 172, 138, 140, 140, 142, 136, 174, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 225, 205, 131, 139, 140, 141, 142, 146, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 225, 223, 143, 139, 139,
    217, 217, 217, 161, 197, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 180, 192, 211, 213, 215, 216, 218, 185, 178, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 206, 170, 211, 212, 214, 216, 218, 207, 159, 204, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 221, 162, 206, 212, 213,
    217, 218, 219, 219, 162, 199, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 179, 190, 210, 212, 214, 215, 217, 218, 220, 186, 180, 206, 208, 210, 212, 214,
    216, 217, 219, 221, 222, 204, 168, 210, 211, 213, 214, 216, 218, 220, 209, 161, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 220, 161, 204, 211, 212, 214,
    217, 218, 219, 221, 220, 164, 200, 210, 211, 213, 215, 216, 218, 220, 222, 177, 188, 208, 210, 212, 214, 215, 217, 219, 219, 221, 186, 179, 208, 210, 211, 214,
    216, 217, 219, 221, 203, 167, 208, 209, 211, 213, 214, 216, 218, 219, 221, 211, 162, 208, 210, 212, 214, 215, 217, 218, 220, 218, 160, 202, 209, 211, 212, 214,
    217, 218, 219, 221, 223, 222, 164, 202, 211, 213, 215, 216, 218, 219, 176, 187, 206, 208, 210, 212, 214, 215, 217, 218, 219, 221, 224, 185, 185, 208, 210, 213,
    215, 217, 219, 201, 166, 206, 208, 209, 211, 213, 214, 216, 218, 219, 221, 223, 212, 163, 209, 212, 214, 215, 217, 218, 216, 159, 201, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 224, 166, 196, 202, 203, 205, 206, 174, 186, 205, 207, 208, 210, 212, 214, 215, 217, 218, 219, 219, 224, 225, 190, 178, 199, 201,
    203, 205, 194, 165, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 221, 223, 225, 213, 165, 200, 202, 204, 205, 205, 157, 199, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 223, 74,  88,  87,  87,  87,  155, 203, 205, 207, 208, 210, 212, 214, 215, 217, 218, 218, 220, 221, 225, 230, 143, 94,  88,
    87,  87,  106, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 190, 83,  87,  87,  88,  76,  187, 204, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 226, 85,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 216, 217, 217, 224, 219, 219, 228, 149, 102, 101,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 225, 85,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 212, 213, 214, 215, 215, 216, 224, 219, 221, 226, 146, 102, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 225, 86,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 211, 213, 213, 215, 220, 220, 222, 225, 226, 225, 145, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  188, 204, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 225, 83,  99,  99,  99,  99,  157, 203, 205, 207, 207, 209, 210, 211, 211, 218, 214, 219, 222, 220, 222, 225, 146, 100, 99,
    99,  99,  112, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 94,  99,  99,  100, 87,  188, 204, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 182, 171, 177, 178, 179, 180, 157, 196, 205, 206, 207, 208, 211, 213, 213, 217, 215, 216, 223, 220, 223, 206, 161, 176, 178,
    179, 180, 168, 178, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 222, 163, 175, 177, 178, 180, 179, 158, 203, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 222, 224, 180, 191, 211, 213, 214, 216, 218, 217, 161, 197, 205, 206, 210, 209, 216, 214, 212, 220, 222, 220, 222, 204, 169, 211, 212, 214,
    216, 217, 219, 184, 179, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 221, 162, 205, 212, 213, 215, 217, 218, 208, 160, 205, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 222, 179, 189, 209, 211, 213, 215, 216, 218, 220, 219, 162, 197, 210, 209, 206, 210, 216, 216, 216, 216, 220, 202, 168, 209, 211, 212, 214,
    216, 217, 219, 221, 186, 181, 208, 209, 211, 213, 214, 216, 218, 219, 221, 219, 161, 203, 210, 212, 214, 215, 217, 218, 219, 208, 160, 205, 208, 209, 212, 213,
    217, 218, 219, 221, 178, 188, 207, 210, 211, 213, 215, 216, 218, 220, 221, 220, 163, 204, 208, 212, 214, 212, 217, 216, 218, 201, 166, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 223, 187, 183, 209, 211, 213, 214, 216, 218, 219, 218, 160, 202, 209, 210, 212, 214, 215, 217, 218, 219, 221, 208, 161, 209, 209, 211, 213,
    217, 217, 219, 176, 186, 206, 208, 210, 211, 213, 215, 216, 218, 220, 221, 221, 220, 165, 204, 210, 213, 213, 213, 216, 200, 165, 205, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 188, 184, 211, 213, 214, 216, 218, 216, 158, 200, 206, 208, 210, 212, 214, 215, 217, 218, 218, 222, 224, 209, 165, 206, 210, 212,
    170, 169, 157, 185, 204, 206, 208, 210, 211, 213, 215, 216, 218, 219, 220, 221, 221, 220, 161, 162, 169, 167, 167, 167, 162, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 189, 159, 166, 167, 169, 170, 152, 198, 205, 206, 208, 210, 212, 214, 215, 217, 217, 217, 219, 223, 226, 216, 157, 167, 165,
    108, 101, 118, 203, 205, 206, 208, 210, 211, 213, 215, 216, 217, 218, 220, 224, 224, 222, 188, 100, 103, 100, 101, 86,  192, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 95,  101, 101, 101, 101, 154, 203, 205, 206, 208, 210, 212, 214, 215, 216, 217, 217, 224, 219, 225, 227, 150, 102, 98,
    109, 102, 118, 203, 205, 206, 208, 210, 211, 212, 214, 215, 216, 216, 223, 220, 225, 223, 189, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 213, 214, 216, 215, 219, 221, 217, 220, 226, 151, 101, 100,
    109, 102, 118, 203, 205, 206, 208, 210, 210, 212, 213, 213, 214, 215, 222, 224, 220, 227, 189, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 210, 211, 213, 213, 214, 216, 218, 223, 221, 226, 223, 149, 102, 100,
    109, 102, 118, 203, 205, 206, 208, 209, 210, 212, 216, 214, 219, 221, 221, 224, 226, 225, 189, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 209, 210, 211, 212, 218, 218, 221, 220, 223, 224, 224, 150, 102, 100,
    98,  91,  109, 203, 205, 206, 208, 209, 210, 210, 212, 218, 214, 214, 223, 218, 221, 224, 185, 88,  92,  92,  91,  80,  187, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 221, 87,  92,  92,  92,  92,  149, 203, 205, 206, 207, 208, 211, 210, 213, 217, 211, 219, 221, 220, 223, 225, 143, 91,  90,
    212, 212, 201, 160, 204, 205, 207, 208, 209, 210, 211, 213, 219, 216, 223, 220, 223, 205, 169, 207, 208, 209, 211, 211, 161, 197, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 222, 163, 202, 208, 209, 211, 212, 182, 179, 204, 205, 206, 207, 213, 215, 211, 218, 217, 221, 220, 221, 224, 184, 187, 207, 208,
    217, 218, 219, 205, 161, 205, 206, 207, 209, 214, 215, 216, 215, 221, 219, 221, 204, 168, 210, 212, 214, 215, 217, 218, 218, 162, 198, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 223, 220, 162, 205, 211, 213, 214, 216, 218, 220, 184, 180, 204, 209, 209, 210, 215, 214, 212, 217, 218, 220, 223, 182, 187, 211, 212, 214,
    217, 218, 219, 221, 206, 163, 210, 206, 210, 211, 208, 217, 215, 217, 219, 202, 167, 208, 210, 212, 214, 215, 217, 219, 220, 220, 163, 200, 209, 211, 212, 214,
    216, 217, 219, 221, 219, 160, 203, 209, 211, 213, 214, 216, 218, 220, 221, 184, 182, 209, 205, 208, 209, 216, 219, 216, 218, 221, 181, 186, 209, 211, 212, 214,
    217, 218, 219, 220, 221, 205, 166, 211, 208, 214, 213, 217, 215, 217, 201, 165, 206, 208, 210, 212, 214, 215, 217, 219, 220, 222, 221, 165, 202, 210, 212, 214,
    216, 217, 219, 217, 159, 201, 208, 209, 211, 213, 214, 216, 218, 219, 221, 221, 186, 186, 212, 213, 215, 211, 214, 216, 220, 179, 185, 207, 209, 211, 212, 214,
    217, 217, 218, 220, 220, 221, 211, 168, 214, 211, 215, 215, 217, 200, 164, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 223, 222, 165, 204, 213, 215,
    217, 219, 216, 158, 199, 206, 208, 209, 211, 213, 214, 216, 217, 219, 220, 221, 222, 186, 181, 209, 216, 213, 216, 219, 178, 183, 205, 207, 209, 210, 212, 214,
    217, 216, 217, 218, 218, 221, 227, 204, 115, 125, 121, 123, 124, 147, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 225, 138, 122, 122,
    124, 124, 120, 198, 204, 206, 208, 209, 211, 213, 214, 216, 217, 218, 219, 221, 221, 223, 175, 124, 124, 122, 124, 119, 175, 204, 206, 207, 209, 210, 212, 214,
    216, 216, 219, 222, 221, 219, 226, 226, 93,  104, 101, 102, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    103, 103, 113, 204, 204, 206, 208, 209, 211, 213, 214, 215, 216, 217, 222, 224, 224, 222, 189, 97,  101, 102, 103, 89,  188, 204, 206, 207, 209, 210, 212, 214,
    217, 216, 218, 220, 222, 226, 224, 223, 86,  101, 101, 102, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 210, 212, 213, 214, 214, 216, 222, 223, 221, 225, 190, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 210, 212, 214,
    217, 216, 216, 222, 223, 223, 226, 223, 85,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 210, 213, 212, 213, 217, 217, 222, 223, 226, 225, 190, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 210, 212, 214,
    217, 216, 216, 220, 223, 219, 223, 223, 86,  103, 103, 103, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 103,
    103, 103, 113, 204, 205, 206, 208, 209, 210, 211, 216, 218, 215, 220, 219, 221, 223, 224, 191, 98,  103, 103, 103, 90,  188, 204, 206, 207, 209, 210, 212, 214,
    217, 217, 217, 218, 224, 222, 224, 206, 122, 132, 133, 134, 135, 147, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 223, 140, 132, 133,
    134, 134, 127, 196, 205, 206, 207, 208, 209, 209, 211, 218, 214, 216, 221, 219, 222, 226, 174, 131, 133, 134, 134, 131, 173, 204, 206, 207, 209, 210, 212, 214,
    217, 217, 218, 220, 221, 222, 205, 169, 212, 214, 216, 217, 219, 205, 161, 204, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 221, 162, 206, 213, 215,
    217, 218, 217, 161, 196, 205, 207, 207, 209, 214, 214, 214, 219, 220, 219, 221, 223, 183, 189, 213, 214, 216, 218, 219, 183, 179, 206, 207, 209, 210, 212, 214,
    217, 218, 219, 220, 222, 205, 168, 209, 211, 213, 215, 216, 218, 220, 206, 163, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 220, 162, 203, 211, 212, 214,
    216, 217, 219, 217, 161, 199, 206, 205, 213, 210, 213, 216, 215, 218, 219, 222, 182, 186, 210, 212, 213, 215, 217, 218, 220, 185, 181, 207, 209, 211, 212, 214,
    217, 218, 219, 221, 204, 166, 208, 209, 211, 213, 215, 216, 218, 220, 222, 207, 164, 208, 210, 212, 214, 215, 217, 219, 220, 218, 160, 202, 209, 211, 212, 214,
    216, 217, 219, 220, 218, 163, 203, 205, 212, 210, 210, 217, 214, 218, 220, 181, 185, 208, 210, 212, 214, 215, 217, 218, 220, 222, 186, 182, 209, 210, 212, 214,
    217, 218, 219, 202, 165, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 209, 165, 210, 211, 214, 215, 217, 219, 217, 159, 200, 207, 209, 211, 212, 214,
    216, 217, 218, 220, 220, 218, 167, 204, 208, 214, 216, 215, 216, 219, 180, 184, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 224, 188, 184, 210, 212, 213,
    209, 208, 196, 164, 204, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 210, 166, 203, 205, 206, 208, 208, 158, 198, 206, 207, 209, 211, 212, 214,
    215, 216, 217, 219, 219, 224, 220, 163, 200, 201, 202, 205, 208, 177, 182, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 224, 226, 189, 182, 204, 205,
    94,  88,  110, 203, 204, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 226, 188, 84,  87,  87,  87,  74,  189, 204, 206, 207, 209, 211, 212, 214,
    215, 215, 219, 219, 217, 222, 225, 217, 91,  88,  87,  87,  88,  150, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 224, 226, 227, 144, 87,  86,
    109, 102, 118, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 227, 191, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    215, 215, 221, 221, 223, 221, 225, 224, 97,  101, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 224, 225, 226, 151, 102, 100,
    109, 102, 118, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 227, 191, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    215, 214, 219, 218, 223, 226, 226, 220, 95,  101, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 225, 226, 151, 102, 100,
    109, 102, 118, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 226, 191, 97,  102, 102, 102, 87,  191, 204, 206, 207, 209, 211, 212, 214,
    215, 216, 216, 223, 222, 219, 223, 221, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 225, 226, 151, 102, 100,
    105, 98,  118, 203, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 226, 191, 94,  99,  99,  99,  83,  191, 204, 206, 207, 209, 211, 212, 214,
    216, 216, 216, 221, 221, 221, 224, 222, 94,  98,  99,  99,  98,  154, 203, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 225, 226, 151, 99,  97,
    177, 177, 165, 182, 205, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 225, 223, 162, 173, 174, 175, 177, 176, 160, 203, 206, 207, 209, 211, 212, 214,
    216, 216, 218, 220, 221, 222, 225, 184, 167, 174, 175, 176, 178, 155, 196, 205, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 224, 225, 210, 159, 173, 174,
    217, 217, 219, 181, 183, 206, 208, 210, 211, 213, 215, 216, 218, 220, 222, 223, 221, 162, 205, 212, 213, 215, 216, 218, 204, 162, 205, 207, 209, 211, 212, 214,
    216, 217, 218, 220, 221, 224, 183, 187, 211, 213, 214, 216, 218, 217, 161, 198, 206, 208, 210, 212, 214, 215, 217, 218, 220, 222, 223, 209, 166, 210, 212, 213,
    217, 218, 219, 221, 182, 184, 207, 209, 211, 213, 215, 216, 218, 220, 222, 220, 161, 203, 210, 212, 214, 215, 217, 219, 220, 206, 164, 207, 209, 211, 212, 214,
    216, 217, 219, 220, 222, 182, 186, 209, 211, 213, 214, 216, 218, 219, 219, 162, 200, 209, 210, 212, 214, 215, 217, 218, 220, 222, 207, 165, 209, 210, 212, 214,
    217, 218, 219, 221, 222, 184, 186, 210, 211, 213, 215, 216, 218, 220, 218, 160, 201, 208, 210, 212, 214, 215, 217, 219, 220, 222, 208, 165, 209, 211, 212, 214,
    216, 217, 219, 221, 181, 184, 208, 209, 211, 213, 214, 216, 218, 219, 221, 220, 163, 201, 210, 212, 214, 215, 217, 218, 220, 206, 164, 207, 209, 211, 212, 214,
    217, 218, 219, 221, 223, 224, 185, 188, 211, 213, 215, 216, 218, 216, 159, 200, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 223, 209, 166, 210, 212, 214,
    216, 217, 219, 180, 183, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 222, 164, 203, 212, 213, 215, 217, 218, 204, 162, 205, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 186, 163, 170, 171, 173, 174, 154, 198, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 211, 157, 169, 171,
    172, 173, 162, 181, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 224, 164, 169, 170, 172, 173, 173, 160, 204, 205, 207, 209, 210, 212, 214,
    217, 218, 219, 221, 223, 224, 226, 225, 85,  101, 101, 101, 101, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 102, 101,
    101, 101, 112, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 96,  101, 101, 101, 89,  188, 204, 206, 207, 209, 210, 213, 214,
    217, 218, 219, 221, 223, 224, 226, 225, 86,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 212, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  188, 204, 206, 207, 209, 210, 212, 213,
    217, 218, 219, 221, 223, 224, 226, 225, 85,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 211, 214, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 211, 212, 213,
    217, 218, 219, 221, 223, 224, 226, 225, 85,  102, 102, 102, 102, 157, 203, 205, 207, 208, 210, 211, 213, 215, 217, 219, 220, 222, 224, 225, 228, 147, 103, 102,
    102, 102, 113, 204, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 192, 97,  102, 102, 102, 89,  189, 204, 206, 207, 209, 210, 211, 211,
    217, 218, 219, 221, 223, 224, 226, 222, 72,  84,  84,  84,  84,  153, 203, 205, 206, 207, 209, 210, 213, 214, 216, 219, 220, 222, 224, 225, 228, 139, 85,  84,
    84,  84,  103, 203, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 226, 189, 81,  84,  84,  84,  74,  186, 204, 206, 207, 208, 209, 211, 210,
    217, 218, 219, 221, 223, 224, 223, 163, 202, 208, 210, 211, 213, 179, 182, 204, 206, 207, 207, 210, 213, 213, 216, 218, 220, 222, 224, 225, 185, 186, 207, 209,
    210, 212, 201, 162, 204, 206, 208, 209, 211, 213, 214, 216, 218, 219, 222, 223, 225, 210, 167, 207, 209, 210, 212, 211, 159, 197, 205, 206, 207, 207, 214, 215,
    217, 218, 219, 221, 222, 221, 162, 204, 211, 213, 215, 216, 218, 220, 181, 183, 205, 210, 210, 209, 213, 212, 215, 217, 220, 222, 223, 184, 187, 210, 212, 214,
    216, 217, 219, 205, 163, 206, 208, 210, 211, 213, 214, 216, 218, 219, 221, 223, 209, 167, 210, 212, 214, 215, 217, 218, 217, 160, 198, 205, 210, 210, 211, 215,
    217, 218, 219, 221, 219, 161, 202, 209, 211, 213, 215, 216, 218, 220, 221, 181, 183, 205, 212, 212, 215, 215, 216, 217, 219, 222, 182, 185, 208, 211, 212, 214,
    216, 217, 219, 220, 206, 164, 207, 209, 211, 213, 214, 216, 218, 219, 221, 208, 165, 208, 210, 212, 214, 215, 217, 218, 220, 219, 160, 200, 210, 205, 208, 209,
    217, 218, 219, 218, 159, 201, 208, 210, 211, 213, 215, 216, 218, 220, 221, 221, 182, 188, 206, 213, 214, 213, 215, 217, 220, 181, 184, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 208, 166, 209, 211, 213, 214, 216, 218, 219, 206, 164, 206, 208, 210, 212, 214, 215, 217, 218, 220, 221, 219, 163, 204, 213, 214, 215,
    217, 217, 216, 159, 199, 206, 208, 210, 211, 213, 215, 216, 218, 219, 220, 220, 224, 184, 183, 207, 214, 212, 214, 218, 180, 182, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 209, 166, 211, 213, 215, 216, 218, 204, 161, 204, 207, 209, 210, 212, 214, 215, 217, 218, 219, 221, 222, 219, 164, 201, 208, 215,
    136, 134, 127, 197, 205, 206, 208, 210, 211, 213, 215, 216, 217, 218, 219, 220, 223, 227, 172, 132, 130, 131, 133, 127, 176, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 209, 122, 131, 132, 134, 135, 146, 203, 205, 206, 208, 210, 212, 214, 215, 217, 217, 218, 220, 221, 222, 220, 140, 134, 133,
    109, 102, 119, 203, 205, 206, 208, 210, 211, 213, 214, 215, 216, 217, 223, 224, 225, 225, 192, 99,  101, 102, 102, 86,  191, 204, 206, 207, 209, 211, 212, 214,
    216, 217, 219, 221, 222, 224, 226, 224, 96,  102, 102, 102, 102, 154, 203, 205, 206, 208, 210, 212, 213, 215, 216, 217, 217, 223, 224, 225, 223, 150, 103, 99,
    110, 103, 120, 203, 205, 207, 208, 210, 211, 212, 213, 215, 214, 218, 220, 216, 225, 223, 188, 98,  103, 104, 103, 88,  192, 204, 206, 208, 209, 211, 213, 215,
    216, 218, 219, 221, 223, 225, 226, 224, 97,  103, 104, 104, 103, 154, 203, 206, 207, 209, 210, 212, 213, 214, 215, 215, 217, 222, 224, 222, 224, 150, 103, 102,
};
