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
pub const PrimitiveType = enum { triangles, triangle_strip, triangle_loop };
pub const BlendMode = enum { @"opaque", alpha_threshold, alpha_to_coverage }; // alpha_blending, additive
pub const DepthMode = enum { normal, test_only, ignore_depth };
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
        .data = std.ArrayList(u8).init(context.allocator),
    };

    try fmt.object.data.resize(size);

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
    _ = context;
    _ = precision;
    _ = h;
    _ = w;
    @panic("not implemented yet!");
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
    primitive_type: PrimitiveType, //
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
        .primitive_type = desc.primitive_type,
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
        error.OutOfBounds => unreachable, // cannot be reached, sizes are immutable
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

    const storage = buf.data.items;

    if (offset > storage.len)
        return error.OutOfRange;
    if (offset + data.len > storage.len)
        return error.Overflow;

    @memcpy(storage[offset .. offset + data.len], data);
}

pub fn updateTexture(context: *Mirage3D, queue: CommandQueueHandle, texture: TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []const Color) error{ InvalidHandle, InactiveQueue, OutOfBounds }!void {
    const q = try context.command_queue_pool.resolve(queue);
    if (!q.active) return error.InactiveQueue;

    _ = data;
    _ = stride;
    _ = h;
    _ = w;
    _ = y;
    _ = x;
    _ = texture;
    @panic("not implemented yet!");
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
    wireframe: Color,
    uniform: Color,
    textured: TextureHandle,
    colored: BufferHandle,
};

pub const DrawInfo = struct {
    queue: CommandQueueHandle, //

    color_target: ColorTargetHandle, // if != none, will paint triangles into this color target
    depth_target: DepthTargetHandle, // if != none, we can use depth testing with potential writeback

    vertex_buffer: BufferHandle, // the source of vertex data
    index_buffer: BufferHandle, // if index_format is not none, this buffer will be used to fetch data for indices
    fill: FillMode,
    transform: Matrix4, // transform the vertices before rendering
};

pub fn drawTriangles(context: *Mirage3D, drawInfo: DrawInfo) error{ OutOfMemory, InvalidConfiguration }!void {
    _ = context;
    _ = drawInfo;
    @panic("not implemented yet!");
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
    data: std.ArrayList(u8),

    fn deinit(obj: *Buffer) void {
        obj.data.deinit();
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
        @"16 bit": []u16,
        @"32 bit": []u32,
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
    primitive_type: PrimitiveType, //
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

fn colorTargetToView(context: *Mirage3D, target_handle: ColorTargetHandle) error{ InvalidHandle, OutOfBounds, TextureKilled }!TextureView {
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
                return @truncate(u32, @enumToInt(handle));
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
            while (pool.handle_map.get(@intToEnum(Handle, handle_int)) != null) {
                handle_int = computeNextHandleInt(handle_int);
                if (handle_int == pool.next_handle)
                    return error.ResourceLimit; // we have reached a full circle, which is bad.
            }
            const handle = @intToEnum(Handle, handle_int);

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
            low = std.math.max(low, key.value);
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

    return @floatToInt(I, clamped);
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

    return @truncate(I, (@as(TwoI, a) * @as(TwoI, b)) >> bitSize);
}

test mixIntRanged {
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 0, 0));
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 255, 0));
    try std.testing.expectEqual(@as(u8, 0), mixIntRanged(u8, 0, 255));

    try std.testing.expectEqual(@as(u8, 127), mixIntRanged(u8, 255, 128));
    try std.testing.expectEqual(@as(u8, 127), mixIntRanged(u8, 128, 255));
}

/// Contains a 16x16 bayer dithering matrix, having unique values from 0 to 255.
const bayer16x16: [16][16]u8 = @bitCast([16][16]u8, [256]u8{
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
});

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
