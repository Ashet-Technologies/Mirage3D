//!

// Handles

pub const BufferHandle = enum(u32) { none, _ };
pub const TextureHandle = enum(u32) { none, _ };
pub const ColorTargetHandle = enum(u32) { none, screen, _ };
pub const DepthTargetHandle = enum(u32) { none, _ };
pub const VertexFormatHandle = enum(u32) { none, _ };
pub const CommandQueueHandle = enum(u32) { none, _ };
pub const PipelineConfigurationHandle = enum(u32) { none, _ };

// Types

pub const Matrix4 = [4][4]f32;

pub const TextureFormat = enum { rgb, rgba };
pub const Color = packed struct { r: u8, g: u8, b: u8, a: u8 }; // 0xABGR
pub const DepthTargetPrecision = enum { @"16 bit", @"32 bit", float };
pub const IndexFormat = enum { none, u8, u16, u32 };
pub const PrimitiveType = enum { triangles, triangle_strip, triangle_loop };
pub const BlendMode = enum { @"opaque", alpha_threshold, alpha_to_coverage }; // alpha_blending, additive
pub const DepthMode = enum { normal, test_only, ignore_depth };
pub const TextureWrapMode = enum { wrap, clamp };

pub const VertexFeatureSet = packed struct(u32) {
    color: bool,
    alpha: bool,
    texture_coords: bool,
    padding: u29 = 0,
};

// Texture

fn createTexture(w: u16, h: u16, fmt: TextureFormat) TextureHandle {
    _ = fmt;
    _ = h;
    _ = w;
    //
}
fn destroyTexture(texture: TextureHandle) void {
    _ = texture;
    //
}

fn updateTexture(texture: TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []const u8) void {
    _ = data;
    _ = stride;
    _ = h;
    _ = w;
    _ = y;
    _ = x;
    _ = texture;
    //
}
fn fetchTexture(texture: TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []u8) void {
    _ = data;
    _ = stride;
    _ = h;
    _ = w;
    _ = y;
    _ = x;
    _ = texture;
    //
}

// Generic buffers for vertices or indices

fn createBuffer(size: usize) BufferHandle {
    _ = size;
    //
}
fn destroyBuffer(buffer: BufferHandle) void {
    _ = buffer;
    //
}

fn updateBuffer(buffer: BufferHandle, offset: usize, data: []const u8) void {
    _ = data;
    _ = offset;
    _ = buffer;
    //
}

// Render to texture/render targets:

fn createColorTarget(texture: TextureHandle, x: u16, y: u16, w: u16, h: u16) ColorTargetHandle {
    _ = h;
    _ = w;
    _ = y;
    _ = x;
    _ = texture;
    //
}
fn destroyColorTarget(target: ColorTargetHandle) void {
    _ = target;
    //
}

// Depth targets

fn createDepthTarget(w: u16, h: u16, precision: DepthTargetPrecision) DepthTargetHandle {
    _ = precision;
    _ = h;
    _ = w;
    //
}
fn destroyDepthTarget(target: DepthTargetHandle) void {
    _ = target;
    //
}

// Vertex formats

fn createVertexFormat(
    element_stride: usize, // How much advance per vertex in the buffer
    feature_mask: VertexFeatureSet, // What vertex features are available
    position_offset: usize, // where is the position component located? `struct{x:f32, y:f32, z:32}`
    texture_coord_offset: usize, // where is the UV component located? struct {u:f16, y:f16}
    color_offset: usize, // where is the vertex Color component located? struct { r:u8, g:u8, b:u8 }
    alpha_offset: usize, // where is the vertex transparency component located? struct{ a:u8 }
) VertexFormatHandle {
    _ = alpha_offset;
    _ = color_offset;
    _ = texture_coord_offset;
    _ = position_offset;
    _ = feature_mask;
    _ = element_stride;
    //
}
fn destroyVertexFormat(format: VertexFormatHandle) void {
    _ = format;
    //
}

// pipeline configs

fn createPipelineConfiguration(
    primitive_type: PrimitiveType, //
    blend_mode: BlendMode, // determines how the vertices are blended over the destination
    depth_mode: DepthMode, // determines how to handle depth. will be ignored if no depth target is present.
    vertex_format: VertexFormatHandle, // defines how to interpret `vertex_buffer`
    index_format: IndexFormat, // size of the indices
    texture_mode: TextureWrapMode, //
) PipelineConfigurationHandle {
    _ = texture_mode;
    _ = index_format;
    _ = vertex_format;
    _ = depth_mode;
    _ = blend_mode;
    _ = primitive_type;
    //
}

fn destroyPipelineConfiguration(pipeline: PipelineConfigurationHandle) void {
    _ = pipeline;
    //
}

// Render queues
fn createRenderQueue() CommandQueueHandle {
    //
}
fn destroyRenderQueue(queue: CommandQueueHandle) void {
    _ = queue;
    //
}

fn begin(queue: CommandQueueHandle) void {
    _ = queue;
    //
}
fn commit(queue: CommandQueueHandle) void {
    _ = queue;
    //
}

fn clearColorTarget(queue: CommandQueueHandle, target: ColorTargetHandle, color: Color) void {
    _ = color;
    _ = target;
    _ = queue;
    //
}
fn clearDepthTarget(queue: CommandQueueHandle, target: DepthTargetHandle, depth: f32) void {
    _ = depth;
    _ = target;
    _ = queue;
    //
}

fn drawTriangles(
    queue: CommandQueueHandle, //

    color_target: ColorTargetHandle, // if != none, will paint triangles into this color target
    depth_target: DepthTargetHandle, // if != none, we can use depth testing with potential writeback

    vertex_buffer: BufferHandle, // the source of vertex data
    index_buffer: BufferHandle, // if index_format is not none, this buffer will be used to fetch data for indices
    texture: TextureHandle, // can be none for flat rendering (texture color is assumed "white"), otherwise will fetch pixels from the texture
    transform: Matrix4, // transform the vertices before rendering
) void {
    _ = transform;
    _ = texture;
    _ = index_buffer;
    _ = vertex_buffer;
    _ = depth_target;
    _ = color_target;
    _ = queue;
    //
}
