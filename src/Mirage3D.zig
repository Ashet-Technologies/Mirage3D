//!
const std = @import("std");

const Mirage3D = @This();

// Handles

pub const BufferHandle = enum(u32) { none = 0, _ };
pub const TextureHandle = enum(u32) { none = 0, _ };
pub const ColorTargetHandle = enum(u32) { none = 0, _ };
pub const DepthTargetHandle = enum(u32) { none = 0, _ };
pub const VertexFormatHandle = enum(u32) { none = 0, _ };
pub const CommandQueueHandle = enum(u32) { none = 0, _ };
pub const PipelineConfigurationHandle = enum(u32) { none = 0, _ };

// Types

pub const ColorFormat = enum {
    indexed8,
    rgba8,
};

pub const Matrix4 = [4][4]f32;

pub const identity_matrix: Matrix4 = .{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

pub const DepthTargetPrecision = enum { @"16 bit", @"32 bit" };
pub const IndexFormat = enum { none, u8, u16, u32 };
pub const PrimitiveType = enum { triangles, triangle_strip, triangle_fan };
pub const BlendMode = enum { @"opaque", alpha_threshold, alpha_to_coverage }; // alpha_blending, additive
pub const DepthMode = enum {
    normal,
    test_only,
    write_only,
    ignore,

    pub fn requiresTest(dm: DepthMode) bool {
        return switch (dm) {
            .normal => true,
            .test_only => true,
            .write_only => false,
            .ignore => false,
        };
    }
    pub fn requiresWriteBack(dm: DepthMode) bool {
        return switch (dm) {
            .normal => true,
            .test_only => false,
            .write_only => true,
            .ignore => false,
        };
    }
};
pub const TextureWrapMode = enum { wrap, clamp };

/// The current color format used by the library. Can be comptime-configured via a build option
pub const color_format: ColorFormat = .indexed8;

/// A generic color type that is used by the library.
pub const Color = switch (color_format) {
    .indexed8 => packed struct(u8) { index: u8 },
    .rgba8 => packed struct(u32) { r: u8, g: u8, b: u8, a: u8 },
};

const TexturePool = ObjectPool(TextureHandle, Texture);
const BufferPool = ObjectPool(BufferHandle, Buffer);
const ColorTargetPool = ObjectPool(ColorTargetHandle, ColorTarget);
const DepthTargetPool = ObjectPool(DepthTargetHandle, DepthTarget);
const VertexFormatPool = ObjectPool(VertexFormatHandle, VertexFormat);
const CommandQueuePool = ObjectPool(CommandQueueHandle, CommandQueue);
const PipelineConfigurationPool = ObjectPool(PipelineConfigurationHandle, PipelineConfiguration);

allocator: std.mem.Allocator,
texture_pool: TexturePool,
buffer_pool: BufferPool,
color_target_pool: ColorTargetPool,
depth_target_pool: DepthTargetPool,
vertex_format_pool: VertexFormatPool,
command_queue_pool: CommandQueuePool,
pipeline_configuration_pool: PipelineConfigurationPool,

pub fn createContext(allocator: std.mem.Allocator) error{OutOfMemory}!Mirage3D {
    return Mirage3D{
        .allocator = allocator,

        .texture_pool = TexturePool.init(allocator),
        .buffer_pool = BufferPool.init(allocator),
        .color_target_pool = ColorTargetPool.init(allocator),
        .depth_target_pool = DepthTargetPool.init(allocator),
        .vertex_format_pool = VertexFormatPool.init(allocator),
        .command_queue_pool = CommandQueuePool.init(allocator),
        .pipeline_configuration_pool = PipelineConfigurationPool.init(allocator),
    };
}

pub fn destroy(context: *Mirage3D) void {
    context.texture_pool.deinit();
    context.buffer_pool.deinit();
    context.color_target_pool.deinit();
    context.depth_target_pool.deinit();
    context.vertex_format_pool.deinit();
    context.command_queue_pool.deinit();
    context.pipeline_configuration_pool.deinit();
    context.* = undefined;
}

// Texture

pub fn createTexture(context: *Mirage3D, w: u16, h: u16) error{ OutOfMemory, ResourceLimit }!TextureHandle {
    const texture = try context.texture_pool.create();
    errdefer context.texture_pool.destroy(texture.handle);

    const color_buffer = try context.allocator.alloc(Color, @as(u32, w) * @as(u32, h));
    errdefer context.allocator.free(color_buffer);

    texture.object.* = Texture{
        .width = w,
        .height = h,
        .allocator = context.allocator,
        .data = color_buffer,
    };

    @memset(color_buffer, std.mem.zeroes(Color));

    return texture.handle;
}

pub fn destroyTexture(context: *Mirage3D, texture: TextureHandle) void {
    context.texture_pool.destroy(texture);
}

// Generic buffers for vertices or indices

pub fn createBuffer(context: *Mirage3D, size: usize) error{ OutOfMemory, ResourceLimit }!BufferHandle {
    const fmt = try context.buffer_pool.create();
    errdefer context.buffer_pool.destroy(fmt.handle);

    fmt.object.* = Buffer{
        .allocator = context.allocator,
        .data = try context.allocator.allocWithOptions(u8, size, 16, null),
    };

    return fmt.handle;
}

pub fn destroyBuffer(context: *Mirage3D, buffer: BufferHandle) void {
    context.buffer_pool.destroy(buffer);
}

// Render to texture/render targets:

pub fn createColorTarget(context: *Mirage3D, texture: TextureHandle, x: u16, y: u16, w: u16, h: u16) error{ OutOfMemory, ResourceLimit, InvalidHandle, OutOfBounds }!ColorTargetHandle {
    const tex: *Texture = try context.texture_pool.resolve(texture);

    if (x > tex.width or y > tex.height)
        return error.OutOfBounds;
    if (@as(u32, x) + @as(u32, w) > tex.width or @as(u32, y) + @as(u32, h) > tex.height)
        return error.OutOfBounds;

    const target = try context.color_target_pool.create();
    errdefer context.color_target_pool.destroy(target);

    target.object.* = ColorTarget{
        .texture = texture,
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };

    return target.handle;
}

// TODO: Expose ways to create swap chains to actually render to the screen
// pub fn createSwapChain(context: *Mirage3D) error{ OutOfMemory, ResourceLimit }!ColorTargetHandle {
//     _ = context;
//     @panic("not implemented yet!");
// }

pub fn destroyColorTarget(context: *Mirage3D, target: ColorTargetHandle) void {
    context.color_target_pool.destroy(target);
}

// Depth targets

pub fn createDepthTarget(context: *Mirage3D, w: u16, h: u16, precision: DepthTargetPrecision) error{ OutOfMemory, ResourceLimit }!DepthTargetHandle {
    const target = try context.depth_target_pool.create();
    errdefer context.depth_target_pool.destroy(target.handle);

    target.object.* = DepthTarget{
        .width = w,
        .height = h,
        .allocator = context.allocator,
        .buffer = switch (precision) {
            .@"16 bit" => blk: {
                const buffer = try context.allocator.alignedAlloc(u16, 16, @as(u32, w) * @as(u32, h));
                @memset(buffer, std.math.maxInt(u16));
                break :blk .{ .@"16 bit" = buffer };
            },
            .@"32 bit" => blk: {
                const buffer = try context.allocator.alignedAlloc(u32, 16, @as(u32, w) * @as(u32, h));
                @memset(buffer, std.math.maxInt(u32));
                break :blk .{ .@"32 bit" = buffer };
            },
        },
    };

    return target.handle;
}

pub fn destroyDepthTarget(context: *Mirage3D, target: DepthTargetHandle) void {
    context.depth_target_pool.destroy(target);
}

// Vertex formats

pub const VertexFormatDescription = struct {
    element_stride: usize, // How much advance per vertex in the buffer
    position_offset: usize, // where is the position component located? `struct{x:f32, y:f32, z:32}`
    texture_coord_offset: ?usize, // where is the UV component located? `struct {u:f16, y:f16}`
    alpha_offset: ?usize, // where is the vertex transparency component located? `struct{ a:u8 }`

    // color_offset: usize, // where is the vertex Color component located? struct { r:u8, g:u8, b:u8 }
};

pub fn createVertexFormat(context: *Mirage3D, desc: VertexFormatDescription) error{ OutOfMemory, ResourceLimit }!VertexFormatHandle {
    const fmt = try context.vertex_format_pool.create();

    fmt.object.* = VertexFormat{
        .element_stride = desc.element_stride,
        .feature_mask = .{
            .alpha = (desc.alpha_offset != null),
            .texcoord = (desc.texture_coord_offset != null),
        },
        .position_offset = desc.position_offset,
        .texture_coord_offset = desc.texture_coord_offset orelse undefined,
        .alpha_offset = desc.alpha_offset orelse undefined,
    };

    return fmt.handle;
}

pub fn destroyVertexFormat(context: *Mirage3D, format: VertexFormatHandle) void {
    context.vertex_format_pool.destroy(format);
}

// pipeline configs

pub const PipelineDescription = struct {
    blend_mode: BlendMode, // determines how the vertices are blended over the destination
    depth_mode: DepthMode, // determines how to handle depth. will be ignored if no depth target is present.
    vertex_format: VertexFormatHandle, // defines how to interpret `vertex_buffer`
    index_format: IndexFormat, // size of the indices
    texture_wrap: TextureWrapMode, //
};

pub fn createPipelineConfiguration(context: *Mirage3D, desc: PipelineDescription) error{ OutOfMemory, ResourceLimit }!PipelineConfigurationHandle {
    const cfg = try context.pipeline_configuration_pool.create();
    errdefer context.pipeline_configuration_pool.destroy(cfg.handle);

    cfg.object.* = PipelineConfiguration{
        .blend_mode = desc.blend_mode,
        .depth_mode = desc.depth_mode,
        .vertex_format = desc.vertex_format,
        .index_format = desc.index_format,
        .texture_wrap = desc.texture_wrap,
    };

    return cfg.handle;
}

pub fn destroyPipelineConfiguration(context: *Mirage3D, pipeline: PipelineConfigurationHandle) void {
    context.pipeline_configuration_pool.destroy(pipeline);
}

// Render queues
pub fn createRenderQueue(context: *Mirage3D) error{ OutOfMemory, ResourceLimit }!CommandQueueHandle {
    const queue = try context.command_queue_pool.create();
    errdefer context.command_queue_pool.destroy(queue.handle);

    queue.object.* = CommandQueue{
        .active = false,
    };

    return queue.handle;
}

pub fn destroyRenderQueue(context: *Mirage3D, queue: CommandQueueHandle) void {
    context.command_queue_pool.destroy(queue);
}

pub fn begin(context: *Mirage3D, queue: CommandQueueHandle) error{ InvalidHandle, AlreadyActive }!void {
    const q = try context.command_queue_pool.resolve(queue);

    if (q.active) return error.AlreadyActive;
    q.active = true;
}

pub fn end(context: *Mirage3D, queue: CommandQueueHandle) error{ InvalidHandle, NotActive }!void {
    const q = try context.command_queue_pool.resolve(queue);

    if (!q.active) return error.NotActive;
    q.active = false;
}

pub fn clearColorTarget(context: *Mirage3D, queue: CommandQueueHandle, target: ColorTargetHandle, color: Color) error{ OutOfMemory, InactiveQueue, InvalidHandle, TextureKilled }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    const view = context.colorTargetToView(target) catch |err| switch (err) {
        error.TextureKilled, error.InvalidHandle => |e| return e,
    };

    var row = view.base;
    var y: usize = 0;
    while (y < view.height) : (y += 1) {
        @memset(row[0..view.width], color);
        row += view.stride;
    }
}

pub fn clearDepthTarget(context: *Mirage3D, queue: CommandQueueHandle, target: DepthTargetHandle, depth: f32) error{ OutOfMemory, InvalidHandle, InactiveQueue }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    const db = try context.depth_target_pool.resolve(target);
    switch (db.buffer) {
        .@"16 bit" => |slice| @memset(slice, mapUniFloatToIntRange(depth, u16)),
        .@"32 bit" => |slice| @memset(slice, mapUniFloatToIntRange(depth, u32)),
    }
}

pub fn updateBuffer(context: *Mirage3D, queue: CommandQueueHandle, buffer: BufferHandle, offset: usize, data: []const u8) error{ InvalidHandle, InactiveQueue, OutOfRange, Overflow }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    const buf = try context.buffer_pool.resolve(buffer);

    const storage = buf.data;

    if (offset > storage.len)
        return error.OutOfRange;
    if (offset + data.len > storage.len)
        return error.Overflow;

    @memcpy(storage[offset .. offset + data.len], data);
}

pub fn updateTexture(context: *Mirage3D, queue: CommandQueueHandle, texture: TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []const Color) error{ InvalidHandle, InactiveQueue, OutOfBounds }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    const tex: *Texture = try context.texture_pool.resolve(texture);

    const view = try TextureView.create(tex, x, y, w, h);

    var dst_row = view.base;
    var src_row = data.ptr;

    for (0..view.height) |_| {
        @memcpy(dst_row[0..view.width], src_row[0..view.width]);
        dst_row += view.stride;
        src_row += stride;
    }
}

pub fn fetchTexture(context: *Mirage3D, queue: CommandQueueHandle, texture: TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []Color) error{ InvalidHandle, InactiveQueue, OutOfBounds }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    const tex: *Texture = try context.texture_pool.resolve(texture);

    const view = try TextureView.create(tex, x, y, w, h);

    var src_row = view.base;
    var dst_row = data.ptr;

    var py: usize = 0;
    while (py < view.height) : (py += 1) {
        @memcpy(dst_row[0..view.width], src_row[0..view.width]);
        src_row += view.stride;
        dst_row += stride;
    }
}

pub const FillMode = union(enum) {
    none,
    wireframe: Color,
    uniform: Color,
    textured: TextureHandle,
    colored: BufferHandle,
};

pub const DrawInfo = struct {
    queue: CommandQueueHandle, //

    configuration: PipelineConfigurationHandle,

    color_target: ColorTargetHandle, // if != none, will paint triangles into this color target
    depth_target: DepthTargetHandle, // if != none, we can use depth testing with potential writeback

    vertex_buffer: BufferHandle, // the source of vertex data
    index_buffer: BufferHandle, // if index_format is not none, this buffer will be used to fetch data for indices

    front_fill: FillMode, // how is the front side of the triangles filled?
    back_fill: FillMode, // how is the back side of the triangles filled?
    transform: Matrix4, // transforms the vertices before rendering
    primitive_type: PrimitiveType, // determines how primitives are assembled from indices
};

pub fn drawTriangles(context: *Mirage3D, drawInfo: DrawInfo) error{ OutOfMemory, InactiveQueue, InvalidHandle, InvalidConfiguration, VertexFormatKilled, TextureKilled, TargetDimensionMismatch }!void {
    const q = try context.command_queue_pool.resolve(drawInfo.queue);
    if (!q.active) return error.InactiveQueue;

    const cfg: *PipelineConfiguration = try context.pipeline_configuration_pool.resolve(drawInfo.configuration);

    const vertex_format: *VertexFormat = context.vertex_format_pool.resolve(cfg.vertex_format) catch return error.VertexFormatKilled;

    const color_target: ?TextureView = if (drawInfo.color_target != .none)
        try context.colorTargetToView(drawInfo.color_target)
    else
        null;

    const depth_target: ?*DepthTarget = if (drawInfo.depth_target != .none)
        try context.depth_target_pool.resolve(drawInfo.depth_target)
    else
        null;

    const vertex_buffer: *Buffer = try context.buffer_pool.resolve(drawInfo.vertex_buffer);

    const index_buffer: ?*Buffer = if (cfg.index_format == .none)
        if (drawInfo.index_buffer != .none)
            return error.InvalidConfiguration
        else
            null
    else
        try context.buffer_pool.resolve(drawInfo.index_buffer);

    const front_fill_mode: FillModeUnwrapped = switch (drawInfo.front_fill) {
        .none => .none,
        .wireframe => |val| .{ .wireframe = val },
        .uniform => |val| .{ .uniform = val },
        .textured => |val| .{ .textured = try context.texture_pool.resolve(val) },
        .colored => |val| .{ .colored = try context.buffer_pool.resolve(val) },
    };

    const back_fill_mode: FillModeUnwrapped = switch (drawInfo.back_fill) {
        .none => .none,
        .wireframe => |val| .{ .wireframe = val },
        .uniform => |val| .{ .uniform = val },
        .textured => |val| .{ .textured = try context.texture_pool.resolve(val) },
        .colored => |val| .{ .colored = try context.buffer_pool.resolve(val) },
    };

    // this is a pretty efficient rasterization:
    if (color_target == null and depth_target == null)
        return;

    if (color_target != null and depth_target != null) {
        if (color_target.?.width != depth_target.?.width or color_target.?.height != depth_target.?.height)
            return error.TargetDimensionMismatch;
    }

    const target_size = if (color_target != null) Size{
        .width = color_target.?.width,
        .height = color_target.?.height,
    } else Size{
        .width = depth_target.?.width,
        .height = depth_target.?.height,
    };

    var vertex_fetcher = VertexFetcher.init(vertex_format, vertex_buffer);
    var index_fetcher = IndexFetcher.init(vertex_format, cfg.index_format, vertex_buffer, index_buffer);

    var vertex_transform = VertexTransform.init(&vertex_fetcher, drawInfo.transform);

    var primitive_assembly = PrimitiveAssembly.init(&vertex_transform, &index_fetcher, drawInfo.primitive_type);

    // inline both depth_mode and blend_mode into the
    // render loop so we don't have any runtime branching
    // on those while looping.
    //
    // fill_mode must be switched at runtime inside the loop as it is decided *per*
    // triangle.
    switch (cfg.depth_mode) {
        inline else => |depth_mode| switch (cfg.blend_mode) {
            inline else => |blend_mode| {
                var face_index: usize = 0;
                while (primitive_assembly.assemble()) |face_raw| {
                    var face = face_raw;

                    const p0 = linearizePos(face[0].position);
                    const p1 = linearizePos(face[1].position);
                    const p2 = linearizePos(face[2].position);

                    const v0 = mapToScreen(p0, target_size.width, target_size.height);
                    const v1 = mapToScreen(p1, target_size.width, target_size.height);
                    const v2 = mapToScreen(p2, target_size.width, target_size.height);

                    const barycentric_area = orient2d(f32, v0, v1, v2);

                    var params = GenericParams{
                        .target_size = target_size,
                        .view = color_target,
                        .depth_buffer = depth_target,
                        .screen_pos = .{ v0, v1, v2 },
                        .barycentric_area = @fabs(barycentric_area),
                        .vertices = &face,
                    };

                    if (barycentric_area > 0.0) {
                        // flip polygon so the rasterizer can properly rasterize
                        std.mem.swap(Point(f32), &params.screen_pos[1], &params.screen_pos[2]);
                        std.mem.swap(Vertex, &face[1], &face[2]);
                    }

                    const fill_mode = if (barycentric_area <= 0.0)
                        front_fill_mode
                    else
                        back_fill_mode;

                    switch (fill_mode) {
                        .none => {},
                        .wireframe => |color| renderWireframeGeneric(params, alphaWrapper(blend_mode, depthWrapper(depth_mode, SolidColorFill{ .color = color }))),
                        .uniform => |color| renderTriangleGeneric(params, alphaWrapper(blend_mode, depthWrapper(depth_mode, SolidColorFill{ .color = color }))),
                        .colored => |buffer| renderTriangleGeneric(params, alphaWrapper(blend_mode, depthWrapper(depth_mode, SolidColorFill{ .color = std.mem.bytesAsSlice(Color, buffer.data)[face_index] }))),
                        .textured => |tex| renderTriangleGeneric(params, alphaWrapper(blend_mode, depthWrapper(depth_mode, TextureFill{ .texture = tex }))),
                    }
                    face_index += 1;
                }
                // end render loop
            },
        },
    }
}

fn alphaWrapper(comptime mode: BlendMode, filler: anytype) AlphaWrapper(@TypeOf(filler), mode) {
    return AlphaWrapper(@TypeOf(filler), mode).init(filler);
}

fn AlphaWrapper(comptime Filler: type, comptime mode: BlendMode) type {
    return struct {
        wrapped: Filler,

        pub fn init(f: Filler) @This() {
            return .{ .wrapped = f };
        }

        inline fn perform(ff: @This(), params: GenericParams, color: *Color, depth_sample: []u8, x: usize, y: usize, w: [3]f32) bool {
            if (mode == .@"opaque") {
                return ff.wrapped.perform(params, color, depth_sample, x, y, w);
            }

            const a0 = params.vertices[0].alpha;
            const a1 = params.vertices[1].alpha;
            const a2 = params.vertices[2].alpha;

            const alpha = barycentricInterpolation(f32, u8, params.barycentric_area, w, .{ a0, a1, a2 });

            switch (mode) {
                .alpha_threshold => if (alpha < 0x80)
                    return false,
                .alpha_to_coverage => if (alpha == 0 or alpha < bayer16x16[x % 16][y % 16])
                    return false,
                else => @compileError("unsupported mode: " ++ @tagName(mode)),
            }

            return ff.wrapped.perform(params, color, depth_sample, x, y, w);
        }
    };
}

fn depthWrapper(comptime mode: DepthMode, filler: anytype) DepthWrapper(@TypeOf(filler), mode) {
    return DepthWrapper(@TypeOf(filler), mode).init(filler);
}

fn DepthWrapper(comptime Filler: type, comptime depth_mode: DepthMode) type {
    return struct {
        wrapped: Filler,

        pub fn init(f: Filler) @This() {
            return .{ .wrapped = f };
        }

        fn readDepth(sample: []const u8) f32 {
            return switch (sample.len) {
                2 => @as(f32, @floatFromInt(@as(*const u16, @ptrCast(@alignCast(sample.ptr))).*)) / std.math.maxInt(u16),
                4 => @as(f32, @floatFromInt(@as(*const u32, @ptrCast(@alignCast(sample.ptr))).*)) / std.math.maxInt(u32),
                else => unreachable,
            };
        }

        fn writeDepth(sample: []u8, depth: f32) void {
            switch (sample.len) {
                2 => @as(*u16, @ptrCast(@alignCast(sample.ptr))).* = @as(u16, @intFromFloat(std.math.clamp(std.math.maxInt(u16) * depth, 0.0, std.math.maxInt(u16)))),
                4 => @as(*u32, @ptrCast(@alignCast(sample.ptr))).* = @as(u32, @intFromFloat(std.math.clamp(std.math.maxInt(u32) * depth, 0.0, std.math.maxInt(u32)))),
                else => unreachable,
            }
        }

        inline fn perform(ff: @This(), params: GenericParams, color: *Color, depth_sample: []u8, x: usize, y: usize, w: [3]f32) bool {
            if (depth_mode == .ignore) {
                return ff.wrapped.perform(params, color, depth_sample, x, y, w);
            }

            const z0 = params.screen_pos[0].z;
            const z1 = params.screen_pos[1].z;
            const z2 = params.screen_pos[2].z;

            const src_z = barycentricInterpolation(f32, f32, params.barycentric_area, w, .{ z0, z1, z2 });

            const dst_z = readDepth(depth_sample);

            if (comptime depth_mode.requiresTest()) {
                if (dst_z < src_z) // LEQUAL
                    return false;
            }

            if (!ff.wrapped.perform(params, color, depth_sample, x, y, w))
                return false;

            if (comptime depth_mode.requiresWriteBack()) {
                writeDepth(depth_sample, src_z);
            }

            return true;
        }
    };
}

const SolidColorFill = struct {
    color: Color,
    inline fn perform(ff: @This(), params: GenericParams, color: *Color, depth_sample: []u8, x: usize, y: usize, w: [3]f32) bool {
        _ = w;
        _ = x;
        _ = y;
        _ = params;
        _ = depth_sample;
        color.* = ff.color;
        return true;
    }
};

const TextureFill = struct {
    texture: *Texture,

    inline fn perform(ff: @This(), params: GenericParams, color: *Color, depth_sample: []u8, x: usize, y: usize, w: [3]f32) bool {
        _ = x;
        _ = y;
        _ = depth_sample;

        const uv0 = params.vertices[0].uv;
        const uv1 = params.vertices[1].uv;
        const uv2 = params.vertices[2].uv;

        const u_flt = @mod(barycentricInterpolation(f32, f16, params.barycentric_area, w, .{ uv0[0], uv1[0], uv2[0] }), 1.0);
        const v_flt = @mod(barycentricInterpolation(f32, f16, params.barycentric_area, w, .{ uv0[1], uv1[1], uv2[1] }), 1.0);

        const u_limit = @as(f32, @floatFromInt(ff.texture.width -| 1));
        const v_limit = @as(f32, @floatFromInt(ff.texture.height -| 1));

        const u_int = @as(usize, @intFromFloat(std.math.clamp(u_limit * u_flt, 0, u_limit)));
        const v_int = @as(usize, @intFromFloat(std.math.clamp(v_limit * v_flt, 0, v_limit)));

        color.* = ff.texture.data[
            ff.texture.width * v_int + u_int
        ];
        return true;
    }
};

fn barycentricInterpolation(
    comptime T: type,
    comptime V: type,
    total: T,
    w: [3]T, // coordinates
    v: [3]V, // values
) V {
    const TConf = struct {
        fn toFloat(t: T) f32 {
            return @as(f32, @floatCast(t));
        }
    };
    const VConf = switch (@typeInfo(V)) {
        .Int => struct {
            fn toFloat(val: V) f32 {
                return @as(f32, @floatFromInt(val));
            }
            fn fromFloat(f: f32) V {
                return @as(V, @intFromFloat(std.math.clamp(f, std.math.minInt(V), std.math.maxInt(V))));
            }
        },
        .Float => struct {
            fn toFloat(val: V) f32 {
                return @as(f32, @floatCast(val));
            }
            fn fromFloat(f: f32) V {
                return @as(V, @floatCast(f));
            }
        },
        else => @compileError(@typeName(V) ++ " is not a supported value type!"),
    };

    var result: f32 = 0;
    inline for (w, v) |wx, vx| {
        result += VConf.toFloat(vx) * (TConf.toFloat(wx) / TConf.toFloat(total));
    }
    return VConf.fromFloat(result);
}

fn linearizePos(p: [4]f32) [3]f32 {
    return .{
        p[0] / p[3],
        p[1] / p[3],
        p[2] / p[3],
    };
}

// var z_min: f32 = 100000;
// var z_max: f32 = -100000;
fn mapToScreen(xyz: [3]f32, width: usize, height: usize) Point(f32) {
    // z_min = @min(z_min, xyz[2]);
    // z_max = @max(z_max, xyz[2]);
    // std.log.info("z={d:.5} min={d:.5} max={d:.5}", .{ xyz[2], z_min, z_max });
    return Point(f32){
        .x = @as(f32, @floatFromInt(width -| 1)) * (0.5 + 0.5 * xyz[0]),
        .y = @as(f32, @floatFromInt(height -| 1)) * (0.5 - 0.5 * xyz[1]),
        .z = xyz[2],
    };
}

fn renderWireframeGeneric(params: GenericParams, render_access: anytype) void {
    renderWire(params, 0, 1, render_access);
    renderWire(params, 1, 2, render_access);
    renderWire(params, 2, 0, render_access);
}

fn renderWire(params: GenericParams, index0: usize, index1: usize, render_access: anytype) void {
    const v0 = params.screen_pos[index0];
    const v1 = params.screen_pos[index1];

    const x0 = @as(i32, @intFromFloat(v0.x + 0.5));
    const x1 = @as(i32, @intFromFloat(v1.x + 0.5));

    const y0 = @as(i32, @intFromFloat(v0.y + 0.5));
    const y1 = @as(i32, @intFromFloat(v1.y + 0.5));

    const dx = @as(i32, @intCast(if (x1 > x0) x1 - x0 else x0 - x1));
    const dy = -@as(i32, @intCast(if (y1 > y0) y1 - y0 else y0 - y1));

    const sx = if (x0 < x1) @as(i32, 1) else @as(i32, -1);
    const sy = if (y0 < y1) @as(i32, 1) else @as(i32, -1);

    var err = dx + dy;

    const v_dist = blk: {
        const dxf = @as(f32, @floatFromInt(dx));
        const dyf = @as(f32, @floatFromInt(dy));
        break :blk @sqrt(dxf * dxf + dyf * dyf);
    };

    var x = x0;
    var y = y0;

    while (true) {
        if (x >= 0 and x < params.target_size.width and y >= 0 and y < params.target_size.height) {
            const ux = @as(usize, @intCast(x));
            const uy = @as(usize, @intCast(y));

            const pos_dx = @as(f32, @floatFromInt(x - x0));
            const pos_dy = @as(f32, @floatFromInt(y - y0));
            const pos_dist = @sqrt(pos_dx * pos_dx + pos_dy * pos_dy);

            const linear = params.barycentric_area * pos_dist / v_dist;

            var w = [3]f32{ 0, 0, 0 };
            w[index0] = linear;
            w[index1] = params.barycentric_area - linear;

            var dummy_color: Color = undefined;
            var dummy_depth: u16 = std.math.maxInt(u16);

            _ = render_access.perform(
                params,
                if (params.view) |view|
                    &view.base[uy * view.stride + ux]
                else
                    &dummy_color,
                if (params.depth_buffer) |db| switch (db.buffer) {
                    inline else => |buf| std.mem.asBytes(&buf[db.width * uy + ux]),
                } else std.mem.asBytes(&dummy_depth),
                ux,
                uy,
                w,
            );
        }

        // std.log.info("({} {}) => {} delta=({} {}) dir=({} {})", .{ x, y, err, dx, dy, sx, sy });

        if (x == x1 and y == y1) {
            break;
        }

        const e2 = 2 * err;
        if (e2 > dy) { // e_xy+e_x > 0
            err += dy;
            x += sx;
        }
        if (e2 < dx) { // e_xy+e_y < 0
            err += dx;
            y += sy;
        }
    }
}

const Size = struct {
    width: usize,
    height: usize,
};

const GenericParams = struct {
    target_size: Size,
    view: ?TextureView,
    depth_buffer: ?*DepthTarget,
    screen_pos: [3]Point(f32),
    barycentric_area: f32,
    vertices: *const [3]Vertex,
};

fn renderTriangleGeneric(params: GenericParams, render_access: anytype) void {

    // Compute triangle bounding box
    const minX = @floor(@max(@as(f32, 0), @min(@min(params.screen_pos[0].x, params.screen_pos[1].x), params.screen_pos[2].x)));
    const minY = @floor(@max(@as(f32, 0), @min(@min(params.screen_pos[0].y, params.screen_pos[1].y), params.screen_pos[2].y)));
    const maxX = @ceil(@min(@as(f32, @floatFromInt(params.target_size.width - 1)), @max(@max(params.screen_pos[0].x, params.screen_pos[1].x), params.screen_pos[2].x)));
    const maxY = @ceil(@min(@as(f32, @floatFromInt(params.target_size.height - 1)), @max(@max(params.screen_pos[0].y, params.screen_pos[1].y), params.screen_pos[2].y)));

    // std.log.info("bounding box: {d:.2} => {d:.2}; {d:.2} => {d:.2}", .{
    //     minX, maxX,
    //     minY, maxY,
    // });

    if (minX > maxX) return;
    if (minY > maxY) return;

    var x0: usize = @as(usize, @intFromFloat(minX));
    var x1: usize = @as(usize, @intFromFloat(maxX));

    var y0: usize = @as(usize, @intFromFloat(minY));
    var y1: usize = @as(usize, @intFromFloat(maxY));

    const depth_size = if (params.depth_buffer) |db| db.buffer.byteSize() else 0;

    var color_row = if (params.view) |view| view.base + view.stride * y0 else null;
    var depth_row = if (params.depth_buffer) |db| db.buffer.byteAccess() + depth_size * db.width * y0 else null;

    for (y0..y1 + 1) |y| {
        for (x0..x1 + 1) |x| {
            const p = Point(f32){
                .x = @as(f32, @floatFromInt(x)),
                .y = @as(f32, @floatFromInt(y)),
                .z = undefined,
            };

            // Determine barycentric coordinates
            const w0 = orient2d(f32, params.screen_pos[1], params.screen_pos[2], p);
            const w1 = orient2d(f32, params.screen_pos[2], params.screen_pos[0], p);
            const w2 = orient2d(f32, params.screen_pos[0], params.screen_pos[1], p);

            // std.log.info("{} {} => {d:.2} {d:.2} {d:.2}", .{ x, y, w0, w1, w2 });

            var dummy_color: Color = undefined;
            var dummy_depth: u16 = std.math.maxInt(u16);

            // std.log.info("{d:.1} {d:.1} {d:.1}", .{ w0, w1, w2 });

            // If p is on or inside all edges, render pixel.
            if (w0 <= 0 and w1 <= 0 and w2 <= 0) {
                _ = render_access.perform(
                    params,
                    if (color_row) |crow| &crow[x] else &dummy_color,
                    if (depth_row) |drow| drow[depth_size * x .. depth_size * (x + 1)] else std.mem.asBytes(&dummy_depth),
                    x,
                    y,
                    .{ @fabs(w0), @fabs(w1), @fabs(w2) },
                );
            }
        }

        if (color_row) |*crow| crow.* += params.view.?.stride;
        if (depth_row) |*dr| dr.* += depth_size * params.depth_buffer.?.width;
    }
}

fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        z: T,
    };
}

fn orient2d(comptime T: type, a: Point(T), b: Point(T), c: Point(T)) T {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

fn crossProduct(a: [3]f32, b: [3]f32) [3]f32 {
    return [3]f32{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

const Texture = struct {
    width: u16,
    height: u16,
    data: []Color,
    allocator: std.mem.Allocator,

    fn deinit(obj: *Texture) void {
        obj.allocator.free(obj.data);
        obj.* = undefined;
    }
};

const Buffer = struct {
    data: []align(16) u8,
    allocator: std.mem.Allocator,

    fn deinit(obj: *Buffer) void {
        obj.allocator.free(obj.data);
        obj.* = undefined;
    }
};

const ColorTarget = struct {
    texture: TextureHandle,

    x: u16,
    y: u16,
    width: u16,
    height: u16,

    fn deinit(obj: *ColorTarget) void {
        obj.* = undefined;
    }
};

const DepthTarget = struct {
    const DepthBuffer = union(DepthTargetPrecision) {
        @"16 bit": []align(16) u16,
        @"32 bit": []align(16) u32,

        fn byteAccess(db: DepthBuffer) [*]align(16) u8 {
            return switch (db) {
                .@"16 bit" => |buf| @as([*]align(16) u8, @ptrCast(buf.ptr)),
                .@"32 bit" => |buf| @as([*]align(16) u8, @ptrCast(buf.ptr)),
            };
        }

        fn byteSize(db: DepthBuffer) usize {
            return switch (db) {
                .@"16 bit" => 2,
                .@"32 bit" => 4,
            };
        }
    };
    width: usize,
    height: usize,
    buffer: DepthBuffer,
    allocator: std.mem.Allocator,

    fn deinit(obj: *DepthTarget) void {
        switch (obj.buffer) {
            inline else => |slice| obj.allocator.free(slice),
        }
        obj.* = undefined;
    }
};

const VertexFormat = struct {
    const Features = packed struct {
        alpha: bool,
        texcoord: bool,
    };

    element_stride: usize,
    feature_mask: Features,
    position_offset: usize,
    texture_coord_offset: usize,
    // color_offset: usize,
    alpha_offset: usize,

    fn deinit(obj: *VertexFormat) void {
        obj.* = undefined;
    }
};

const CommandQueue = struct {
    active: bool,

    fn deinit(obj: *CommandQueue) void {
        obj.* = undefined;
    }
};

const PipelineConfiguration = struct {
    blend_mode: BlendMode, // determines how the vertices are blended over the destination
    depth_mode: DepthMode, // determines how to handle depth. will be ignored if no depth target is present.
    vertex_format: VertexFormatHandle, // defines how to interpret `vertex_buffer`
    index_format: IndexFormat, // size of the indices
    texture_wrap: TextureWrapMode, //

    fn deinit(obj: *PipelineConfiguration) void {
        obj.* = undefined;
    }
};

const TextureView = struct {
    base: [*]Color,
    stride: usize,
    width: usize,
    height: usize,

    pub fn create(tex: *Texture, x: u16, y: u16, width: u16, height: u16) error{OutOfBounds}!TextureView {
        if (@as(usize, x) +| width > tex.width) return error.OutOfBounds;
        if (@as(usize, y) +| height > tex.height) return error.OutOfBounds;

        const stride = @as(usize, tex.width);
        const base = tex.data.ptr + y * stride + x;

        return TextureView{
            .base = base,
            .stride = stride,
            .width = width,
            .height = height,
        };
    }
};

fn colorTargetToView(context: *Mirage3D, target_handle: ColorTargetHandle) error{ InvalidHandle, TextureKilled }!TextureView {
    const dst: *ColorTarget = try context.color_target_pool.resolve(target_handle);

    const tex: *Texture = context.texture_pool.resolve(dst.texture) catch return error.TextureKilled;

    std.debug.assert(dst.x + dst.width <= tex.width);
    std.debug.assert(dst.y + dst.height <= tex.height);

    const stride = @as(usize, tex.width);
    const base = tex.data.ptr + dst.y * stride + dst.x;

    return TextureView{
        .base = base,
        .stride = stride,
        .width = dst.width,
        .height = dst.height,
    };
}

/// A pool that can allocate objects and connect them to a handle type
fn ObjectPool(comptime Handle: type, comptime Object: type) type {
    return struct {
        const Pool = @This();
        const HandleInt = @typeInfo(Handle).Enum.tag_type;
        const StoragePool = std.heap.MemoryPool(Object);
        const HandleMap = std.ArrayHashMap(Handle, *align(StoragePool.item_alignment) Object, HandleMapContext, false);
        const HandleMapContext = struct {
            pub fn eql(_: @This(), a: Handle, b: Handle, _: usize) bool {
                return (a == b);
            }

            pub fn hash(_: @This(), handle: Handle) u32 {
                return @as(u32, @truncate(@intFromEnum(handle)));
            }
        };

        memory_pool: StoragePool,
        next_handle: HandleInt,
        handle_map: HandleMap,

        pub fn init(allocator: std.mem.Allocator) Pool {
            return Pool{
                .memory_pool = StoragePool.init(allocator),
                .next_handle = lowestFreeEnumValue(Handle),
                .handle_map = HandleMap.init(allocator),
            };
        }

        pub fn deinit(pool: *Pool) void {
            for (pool.handle_map.values()) |obj| {
                destroyObject(obj);
            }
            pool.handle_map.deinit();
            pool.memory_pool.deinit();
        }

        pub fn resolve(pool: *Pool, handle: Handle) error{InvalidHandle}!*Object {
            return pool.handle_map.get(handle) orelse return error.InvalidHandle;
        }

        fn computeNextHandleInt(i: HandleInt) HandleInt {
            return if (i == std.math.maxInt(HandleInt))
                lowestFreeEnumValue(Handle)
            else
                i + 1;
        }

        const HandlePtrPair = struct { handle: Handle, object: *Object };
        pub fn create(pool: *Pool) error{ OutOfMemory, ResourceLimit }!HandlePtrPair {
            var handle_int = pool.next_handle;
            while (pool.handle_map.get(@as(Handle, @enumFromInt(handle_int))) != null) {
                handle_int = computeNextHandleInt(handle_int);
                if (handle_int == pool.next_handle)
                    return error.ResourceLimit; // we have reached a full circle, which is bad.
            }
            const handle = @as(Handle, @enumFromInt(handle_int));

            const obj = try pool.memory_pool.create();
            errdefer pool.memory_pool.destroy(obj);

            try pool.handle_map.putNoClobber(handle, obj);

            pool.next_handle = computeNextHandleInt(handle_int);
            return .{ .handle = handle, .object = obj };
        }

        pub fn destroy(pool: *Pool, handle: Handle) void {
            if (pool.handle_map.fetchSwapRemove(handle)) |kv| {
                destroyObject(kv.value);
                pool.memory_pool.destroy(kv.value);
            }
        }

        fn destroyObject(obj: *Object) void {
            const info = @typeInfo(Object);
            if (info == .Enum or info == .Struct or info == .Union) {
                if (@hasDecl(Object, "deinit")) {
                    obj.deinit();
                }
            }
            obj.* = undefined;
        }
    };
}

/// Computes the lowest enum value that is not already assigned to a handle and where no other named enum
/// value may appear afterwards.
fn lowestFreeEnumValue(comptime Handle: type) @typeInfo(Handle).Enum.tag_type {
    return comptime blk: {
        const enum_info: std.builtin.Type.Enum = @typeInfo(Handle).Enum;
        if (enum_info.is_exhaustive)
            @compileError(@typeName(Handle) ++ " is not a handle compatible enum. Must be non-exhaustive!");

        const Int = enum_info.tag_type;

        var low = std.math.minInt(Int);

        if (enum_info.fields.len == 0)
            break :blk low;

        inline for (enum_info.fields) |key| {
            low = @max(low, key.value);
        }

        break :blk low + 1;
    };
}

test lowestFreeEnumValue {
    try std.testing.expectEqual(@as(u32, 0), lowestFreeEnumValue(enum(u32) { _ }));
    try std.testing.expectEqual(@as(u32, 1), lowestFreeEnumValue(enum(u32) { none, _ }));
    try std.testing.expectEqual(@as(u4, 1), lowestFreeEnumValue(enum(u4) { none, _ }));
    try std.testing.expectEqual(@as(u2, 3), lowestFreeEnumValue(enum(u2) { one, two, three, _ }));
}

test ObjectPool {
    const Handle = enum(u32) { none, _ };
    var pool = ObjectPool(Handle, u32).init(std.testing.allocator);
    defer pool.deinit();

    const handle_obj = try pool.create();

    _ = try pool.resolve(handle_obj.handle);

    pool.destroy(handle_obj.handle);
    pool.destroy(handle_obj.handle); // must not error

    try std.testing.expectError(error.InvalidHandle, pool.resolve(handle_obj.handle));
}

test Mirage3D {
    var mirage = try createContext(std.testing.allocator);
    defer mirage.destroy();

    //
}

fn mapUniFloatToIntRange(f: f32, comptime I: type) I {
    const int_lo = std.math.minInt(I);
    const int_hi = std.math.maxInt(I);

    const clamped = std.math.clamp((int_hi - int_lo) * f - int_lo, int_lo, int_hi);

    return @as(I, @intFromFloat(clamped));
}

test mapUniFloatToIntRange {
    try std.testing.expectEqual(@as(u8, 0), mapUniFloatToIntRange(0.0, u8));
    try std.testing.expectEqual(@as(u8, 127), mapUniFloatToIntRange(0.5, u8));
    try std.testing.expectEqual(@as(u8, 255), mapUniFloatToIntRange(1.0, u8));
    try std.testing.expectEqual(@as(u8, 0), mapUniFloatToIntRange(-1.0, u8));
    try std.testing.expectEqual(@as(u8, 255), mapUniFloatToIntRange(2.0, u8));
}

fn mixIntRanged(comptime I: type, a: I, b: I) I {
    const bitSize = @bitSizeOf(I);

    const TwoI = @Type(.{ .Int = .{ .bits = 2 * bitSize, .signedness = .unsigned } });

    return @as(I, @truncate((@as(TwoI, a) * @as(TwoI, b)) >> bitSize));
}

test mixIntRanged {
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 0, 0));
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 255, 0));
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 0, 255));

    try std.testing.expectEqual(@as(u8, 127), mixIntRanged(u8, 255, 128));
    try std.testing.expectEqual(@as(u8, 127), mixIntRanged(u8, 128, 255));
}

const FillModeUnwrapped = union(enum) {
    none,
    wireframe: Color,
    uniform: Color,
    textured: *Texture,
    colored: *Buffer,
};

const Vertex = struct {
    position: [4]f32, // homegeneous coordinate
    uv: [2]f16,
    alpha: u8,
};

/// Decodes the vertex buffer and returns vertices based on an index.
const VertexFetcher = struct {
    stream: []align(16) const u8,
    format: *VertexFormat,

    fn init(format: *VertexFormat, buffer: *Buffer) VertexFetcher {
        return VertexFetcher{
            .stream = buffer.data,
            .format = format,
        };
    }

    fn fetch(fetcher: VertexFetcher, index: usize) Vertex {
        const fmt = fetcher.format;
        const vertex = fetcher.stream[fmt.element_stride * index ..][0..fmt.element_stride];

        const alpha = if (fmt.feature_mask.alpha)
            vertex[fmt.alpha_offset]
        else
            0xFF;

        const uv = if (fmt.feature_mask.texcoord)
            @as([2]f16, @bitCast(vertex[fmt.texture_coord_offset..][0 .. 2 * @sizeOf(f16)].*))
        else
            [2]f16{ 0, 0 };

        const pos = @as([3]f32, @bitCast(vertex[fmt.position_offset..][0 .. 3 * @sizeOf(f32)].*));

        return Vertex{
            .position = pos ++ [1]f32{1},
            .uv = uv,
            .alpha = alpha,
        };
    }
};

/// Fetches indices based on the index format.
const IndexFetcher = struct {
    index_buffer: ?[]align(16) u8,
    vertex_count: usize,
    pos: usize = 0,
    fetch_func: *const fn (*IndexFetcher) ?usize,

    pub fn init(vertex_format: *const VertexFormat, index_format: IndexFormat, vertex_buffer: *Buffer, index_buffer: ?*Buffer) IndexFetcher {
        return IndexFetcher{
            .index_buffer = if (index_buffer) |buf| buf.data else &.{},
            .vertex_count = vertex_buffer.data.len / vertex_format.element_stride,
            .fetch_func = switch (index_format) {
                .none => fetchVertexArray,
                .u8 => fetchVertexIndex8,
                .u16 => fetchVertexIndex16,
                .u32 => fetchVertexIndex32,
            },
        };
    }

    pub fn fetch(idx: *IndexFetcher) ?usize {
        return idx.fetch_func(idx);
    }

    fn fetchVertexArray(idx: *IndexFetcher) ?usize {
        if (idx.pos >= idx.vertex_count)
            return null;
        const i = idx.pos;
        idx.pos += 1;
        return i;
    }

    fn fetchVertexIndexGen(idx: *IndexFetcher, comptime T: type) ?usize {
        const slice = std.mem.bytesAsSlice(T, idx.index_buffer.?);
        if (idx.pos >= slice.len)
            return null;
        const i = slice[idx.pos];
        idx.pos += 1;
        return i;
    }

    fn fetchVertexIndex8(idx: *IndexFetcher) ?usize {
        return idx.fetchVertexIndexGen(u8);
    }
    fn fetchVertexIndex16(idx: *IndexFetcher) ?usize {
        return idx.fetchVertexIndexGen(u16);
    }
    fn fetchVertexIndex32(idx: *IndexFetcher) ?usize {
        return idx.fetchVertexIndexGen(u32);
    }
};

const VertexTransform = struct {
    const cache_size = 32; // maybe adjust for platform

    fetcher: *const VertexFetcher,
    matrix: Matrix4,
    cache_key: [cache_size]usize = .{std.math.maxInt(usize)} ** cache_size,
    cache_value: [cache_size]Vertex = undefined,

    pub fn init(fetcher: *const VertexFetcher, matrix: Matrix4) VertexTransform {
        return VertexTransform{
            .fetcher = fetcher,
            .matrix = matrix,
        };
    }

    pub fn getVertex(transform: *VertexTransform, index: usize) Vertex {
        var vertex = transform.fetcher.fetch(index);
        vertex.position = mulMatrixVec(transform.matrix, vertex.position);
        transform.cache_key[cacheIndex(index)] = index;
        transform.cache_value[cacheIndex(index)] = vertex;
        return vertex;
    }

    fn cacheIndex(index: usize) usize {
        return index % cache_size;
    }

    fn mulMatrixVec(mat: Matrix4, vec: [4]f32) [4]f32 {
        var result = comptime std.mem.zeroes([4]f32);
        inline for (0..4) |i| {
            result[0] += vec[i] * mat[i][0];
            result[1] += vec[i] * mat[i][1];
            result[2] += vec[i] * mat[i][2];
            result[3] += vec[i] * mat[i][3];
        }
        return result;
    }
};

const PrimitiveAssembly = struct {
    vertices: *VertexTransform,
    indices: *IndexFetcher,
    fetch_tris: *const fn (as: *PrimitiveAssembly) ?[3]usize,
    index_cache: [2]usize = undefined,
    was_init: bool = false,

    pub fn init(vertices: *VertexTransform, indices: *IndexFetcher, primitive_type: PrimitiveType) PrimitiveAssembly {
        return PrimitiveAssembly{
            .vertices = vertices,
            .indices = indices,
            .fetch_tris = switch (primitive_type) {
                .triangles => assembleTriangles,
                .triangle_strip => assembleTriangleStrip,
                .triangle_fan => assembleTriangleFan,
            },
        };
    }

    pub fn assemble(as: *PrimitiveAssembly) ?[3]Vertex {
        const indices = as.fetch_tris(as) orelse return null;
        return .{
            as.vertices.getVertex(indices[0]),
            as.vertices.getVertex(indices[1]),
            as.vertices.getVertex(indices[2]),
        };
    }

    fn assembleTriangles(as: *PrimitiveAssembly) ?[3]usize {
        const index0 = as.indices.fetch() orelse return null;
        const index1 = as.indices.fetch() orelse return null;
        const index2 = as.indices.fetch() orelse return null;
        return .{ index0, index1, index2 };
    }

    fn assembleTriangleStrip(as: *PrimitiveAssembly) ?[3]usize {
        if (!as.was_init) {
            as.index_cache[0] = as.indices.fetch() orelse return null;
            as.index_cache[1] = as.indices.fetch() orelse return null;
            as.was_init = true;
        }

        const index0 = as.index_cache[0];
        const index1 = as.index_cache[1];
        const index2 = as.indices.fetch() orelse return null;

        as.index_cache = .{ index1, index2 };

        return .{ index0, index1, index2 };
    }

    fn assembleTriangleFan(as: *PrimitiveAssembly) ?[3]usize {
        if (!as.was_init) {
            as.index_cache[0] = as.indices.fetch() orelse return null;
            as.index_cache[1] = as.indices.fetch() orelse return null;
            as.was_init = true;
        }

        const index0 = as.index_cache[0];
        const index1 = as.index_cache[1];
        const index2 = as.indices.fetch() orelse return null;

        as.index_cache[1] = index2;

        return .{ index0, index1, index2 };
    }
};

/// Contains a 16x16 bayer dithering matrix, having unique values from 0 to 255.
const bayer16x16: [16][16]u8 = @as([16][16]u8, @bitCast([256]u8{
    0,   128, 32,  160, 8,   136, 40,  168, 2,   130, 34,  162, 10,  138, 42,  170,
    192, 64,  224, 96,  200, 72,  232, 104, 194, 66,  226, 98,  202, 74,  234, 106,
    48,  176, 16,  144, 56,  184, 24,  152, 50,  178, 18,  146, 58,  186, 26,  154,
    240, 112, 208, 80,  248, 120, 216, 88,  242, 114, 210, 82,  250, 122, 218, 90,
    12,  140, 44,  172, 4,   132, 36,  164, 14,  142, 46,  174, 6,   134, 38,  166,
    204, 76,  236, 108, 196, 68,  228, 100, 206, 78,  238, 110, 198, 70,  230, 102,
    60,  188, 28,  156, 52,  180, 20,  148, 62,  190, 30,  158, 54,  182, 22,  150,
    252, 124, 220, 92,  244, 116, 212, 84,  254, 126, 222, 94,  246, 118, 214, 86,
    3,   131, 35,  163, 11,  139, 43,  171, 1,   129, 33,  161, 9,   137, 41,  169,
    195, 67,  227, 99,  203, 75,  235, 107, 193, 65,  225, 97,  201, 73,  233, 105,
    51,  179, 19,  147, 59,  187, 27,  155, 49,  177, 17,  145, 57,  185, 25,  153,
    243, 115, 211, 83,  251, 123, 219, 91,  241, 113, 209, 81,  249, 121, 217, 89,
    15,  143, 47,  175, 7,   135, 39,  167, 13,  141, 45,  173, 5,   133, 37,  165,
    207, 79,  239, 111, 199, 71,  231, 103, 205, 77,  237, 109, 197, 69,  229, 101,
    63,  191, 31,  159, 55,  183, 23,  151, 61,  189, 29,  157, 53,  181, 21,  149,
    255, 127, 223, 95,  247, 119, 215, 87,  253, 125, 221, 93,  245, 117, 213, 85,
}));

comptime {
    // ref all api calls to ensure they are always analyzed:
    _ = createContext;
    _ = destroy;
    _ = createTexture;
    _ = destroyTexture;
    _ = updateTexture;
    _ = fetchTexture;
    _ = createBuffer;
    _ = destroyBuffer;
    _ = updateBuffer;
    _ = createColorTarget;
    _ = destroyColorTarget;
    _ = createDepthTarget;
    _ = destroyDepthTarget;
    _ = destroyVertexFormat;
    _ = createPipelineConfiguration;
    _ = destroyPipelineConfiguration;
    _ = createRenderQueue;
    _ = destroyRenderQueue;
    _ = begin;
    _ = end;
    _ = clearColorTarget;
    _ = clearDepthTarget;
    _ = drawTriangles;
}
