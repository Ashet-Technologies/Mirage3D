//!

// Handles

const BufferHandle = enum(u32) { none, _ };
const TextureHandle = enum(u32) { none, _ };
const ColorTargetHandle = enum { none, screen, _ };
const DepthTargetHandle = enum(u32) { none, _ };
const VertexFormatHandle = enum(u32) { none, _ };

// Types

const TextureFormat = enum { rgb, rgba };
const Color = packed struct { r: u8, g: u8, b: u8, a: u8 }; // 0xABGR
const DepthTargetPrecision = enum { @"16 bit", @"32 bit", float };
const IndexFormat = enum { u8, u16, u32 };
const PrimitiveType = enum { triangles, triangle_strip, triangle_loop };
const BlendMode = enum { @"opaque", alpha_threshold, alpha_to_coverage, alpha_blending, additive };

const FeatureSet = packed struct(u32) { color: bool, texture_coords: bool, padding: u30 = 0 };

// Texture

fn createTexture(w: u16, h: u16, fmt: TextureFormat) TextureHandle;
fn destroyTexture(TextureHandle) void;

fn clearTexture(TextureHandle, color: Color) void;
fn updateTexture(TextureHandle, x: u16, y: u16, w: u16, h: u16, stride: usize, data: []const u8) void;

// Generic buffers for vertices or indices

fn createBuffer(size: usize) BufferHandle;
fn destroyBuffer(BufferHandle) void;

fn updateBuffer(BufferHandle, offset: usize, data: []const u8) void;

// Render to texture/render targets:

fn createColorTarget(TextureHandle, x: u16, y: u16, w: u16, h: u16) ColorTargetHandle;
fn destroyColorTarget(ColorTargetHandle) void;

fn clearColorTarget(ColorTargetHandle, color: Color) void;

// Depth targets

fn createDepthTarget(w: u16, h: u16, precision: DepthTargetPrecision) DepthTargetHandle;
fn destroyDepthTarget(DepthTargetHandle) void;

fn clearDepthTarget(DepthTargetHandle, depth: f32) void;

// Vertex formats

fn createVertexFormat(
    element_size: usize, // Size of a vertex
    feature_mask: FeatureSet, // What vertex features are available
    position_offset: usize, // where is the position component located? `struct{x:f32,y:f32,z:32}`
    texture_coord_offset: usize, // where is the UV component located? struct {u:f16,y:f16}
    color_offset: usize, // where is the Color component located?
) VertexFormatHandle;
fn destroyVertexFormat(VertexFormatHandle) void;

// Render functions

fn drawTriangles(
    primitive_type: PrimitiveType, //
    blend_mode: BlendMode, //

    ColorTargetHandle, // if != none, will paint triangles into this color target
    DepthTargetHandle, // if != none, will paint triangles into this color target

    vertex_format: VertexFormatHandle, //
    vertex_buffer: BufferHandle, //

    index_format: IndexFormat, //
    index_buffer: BufferHandle, // can be none, will use "linear" indices then
) void;
