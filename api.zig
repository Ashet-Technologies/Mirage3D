//!

// Handles

const BufferHandle = enum(u32) { none, _ };
const TextureHandle = enum(u32) { none, _ };
const ColorTargetHandle = enum { none, screen, _ };
const DepthTargetHandle = enum(u32) { none, _ };
const VertexFormatHandle = enum(u32) { none, _ };
const CommandQueueHandle = enum(u32) { none, _ };
const PipelineConfigurationHandle = enum(u32) { none, _ };

// Types

const Matrix4 = [4][4]f32;

const TextureFormat = enum { rgb, rgba };
const Color = packed struct { r: u8, g: u8, b: u8, a: u8 }; // 0xABGR
const DepthTargetPrecision = enum { @"16 bit", @"32 bit", float };
const IndexFormat = enum { none, u8, u16, u32 };
const PrimitiveType = enum { triangles, triangle_strip, triangle_loop };
const BlendMode = enum { @"opaque", alpha_threshold, alpha_to_coverage }; // alpha_blending, additive
const DepthMode = enum { normal, test_only, ignore_depth };
const TextureWrapMode = enum { wrap, clamp };

const VertexFeatureSet = packed struct(u32) { color: bool, alpha: bool, texture_coords: bool };

// Texture

fn createTexture(w: u16, h: u16, fmt: TextureFormat) TextureHandle;
fn destroyTexture(TextureHandle) void;

fn updateTexture(TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []const u8) void;
fn fetchTexture(TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []u8) void;

// Generic buffers for vertices or indices

fn createBuffer(size: usize) BufferHandle;
fn destroyBuffer(BufferHandle) void;

fn updateBuffer(BufferHandle, offset: usize, data: []const u8) void;

// Render to texture/render targets:

fn createColorTarget(TextureHandle, x: u16, y: u16, w: u16, h: u16) ColorTargetHandle;
fn destroyColorTarget(ColorTargetHandle) void;

// Depth targets

fn createDepthTarget(w: u16, h: u16, precision: DepthTargetPrecision) DepthTargetHandle;
fn destroyDepthTarget(DepthTargetHandle) void;

// Vertex formats

fn createVertexFormat(
    element_stride: usize, // How much advance per vertex in the buffer
    feature_mask: VertexFeatureSet, // What vertex features are available
    position_offset: usize, // where is the position component located? `struct{x:f32, y:f32, z:32}`
    texture_coord_offset: usize, // where is the UV component located? struct {u:f16, y:f16}
    color_offset: usize, // where is the vertex Color component located? struct { r:u8, g:u8, b:u8 }
    alpha_offset: usize, // where is the vertex transparency component located? struct{ a:u8 }
) VertexFormatHandle;
fn destroyVertexFormat(VertexFormatHandle) void;

// pipeline configs

fn createPipelineConfiguration(
    primitive_type: PrimitiveType, //
    blend_mode: BlendMode, // determines how the vertices are blended over the destination
    depth_mode: DepthMode, // determines how to handle depth. will be ignored if no depth target is present.
    vertex_format: VertexFormatHandle, // defines how to interpret `vertex_buffer`
    index_format: IndexFormat, // size of the indices
    texture_mode: TextureWrapMode, //
) PipelineConfigurationHandle;

fn destroyPipelineConfiguration(PipelineConfigurationHandle) void;

// Render queues
fn createRenderQueue() CommandQueueHandle;
fn destroyRenderQueue(CommandQueueHandle) void;

fn begin(CommandQueueHandle) void;
fn commit(CommandQueueHandle) void;

fn clearColorTarget(CommandQueueHandle, ColorTargetHandle, color: Color) void;
fn clearDepthTarget(CommandQueueHandle, DepthTargetHandle, depth: f32) void;

fn drawTriangles(
    queue: CommandQueueHandle, //

    ColorTargetHandle, // if != none, will paint triangles into this color target
    DepthTargetHandle, // if != none, we can use depth testing with potential writeback

    vertex_buffer: BufferHandle, // the source of vertex data
    index_buffer: BufferHandle, // if index_format is not none, this buffer will be used to fetch data for indices
    texture: TextureHandle, // can be none for flat rendering (texture color is assumed "white"), otherwise will fetch pixels from the texture
    transform: Matrix4, // transform the vertices before rendering
) void;
