const std = @import("std");
const za = @import("zalgebra");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_syswm.h");
    @cInclude("webgpu/webgpu.h");
});

const Vertex = extern struct {
    position: [4]f32,
    color: [4]f32,
};

const UniformBuffer = extern struct {
    mvp: [4][4]f32,
};

const vertices = [_]Vertex{
    .{ .position = .{ 1.0, -1.0, 0.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0, 0.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
    .{ .position = .{ 0.0, 1.0, 0.0, 1.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
};

const indices = [_]u32{ 0, 1, 2 };

const shader_source =
    \\struct Uniform {
    \\    mvp: mat4x4<f32>,
    \\};
    \\
    \\@group(0) @binding(0)
    \\var<uniform> ubo: Uniform;
    \\
    \\struct VertexInput {
    \\    @location(0) position: vec4<f32>,
    \\    @location(1) color: vec4<f32>,
    \\};
    \\
    \\struct VertexOutput {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) color: vec4<f32>,
    \\};
    \\
    \\@vertex
    \\fn vertex_main(vert: VertexInput) -> VertexOutput {
    \\    var out: VertexOutput;
    \\    out.color = vert.color;
    \\    out.position = ubo.mvp * vert.position;
    \\    return out;
    \\}
    \\
    \\@fragment
    \\fn fragment_main(in: VertexOutput) -> @location(0) vec4<f32> {
    \\    return vec4<f32>(in.color);
    \\}
;

const depth_format = c.WGPUTextureFormat_Depth32Float;

const State = struct {
    instance: c.WGPUInstance = null,
    surface: c.WGPUSurface = null,
    adapter: c.WGPUAdapter = null,
    device: c.WGPUDevice = null,
    queue: c.WGPUQueue = null,
    surface_config: c.WGPUSurfaceConfiguration = undefined,
    depth_texture: c.WGPUTexture = null,
    depth_view: c.WGPUTextureView = null,
    pipeline: c.WGPURenderPipeline = null,
    vertex_buffer: c.WGPUBuffer = null,
    index_buffer: c.WGPUBuffer = null,
    uniform_buffer: c.WGPUBuffer = null,
    bind_group: c.WGPUBindGroup = null,
    bind_group_layout: c.WGPUBindGroupLayout = null,
    model: za.Mat4 = za.Mat4.identity(),
    width: u32 = 800,
    height: u32 = 600,
    initialized: bool = false,
};

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("Failed to initialize SDL2: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Zig/WGPU Triangle",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        800,
        600,
        c.SDL_WINDOW_RESIZABLE,
    );
    if (window == null) {
        std.debug.print("Failed to create window: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyWindow(window);

    var state = State{};
    initWgpu(&state, window.?);
    defer cleanup(&state);

    var last_time = c.SDL_GetPerformanceCounter();
    const frequency = c.SDL_GetPerformanceFrequency();
    var running = true;

    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    running = false;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                        running = false;
                    }
                },
                c.SDL_WINDOWEVENT => {
                    if (event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                        const new_width: u32 = @intCast(event.window.data1);
                        const new_height: u32 = @intCast(event.window.data2);
                        if (new_width > 0 and new_height > 0) {
                            resize(&state, new_width, new_height);
                        }
                    }
                },
                else => {},
            }
        }

        if (!state.initialized) {
            continue;
        }

        const now = c.SDL_GetPerformanceCounter();
        const delta_time: f32 = @as(f32, @floatFromInt(now - last_time)) / @as(f32, @floatFromInt(frequency));
        last_time = now;

        update(&state, delta_time);
        render(&state);
    }
}

fn createSurfaceFromSdl(instance: c.WGPUInstance, window: *c.SDL_Window) c.WGPUSurface {
    var info: c.SDL_SysWMinfo = undefined;
    info.version.major = c.SDL_MAJOR_VERSION;
    info.version.minor = c.SDL_MINOR_VERSION;
    info.version.patch = c.SDL_PATCHLEVEL;
    if (c.SDL_GetWindowWMInfo(window, &info) == c.SDL_FALSE) {
        std.debug.print("Failed to get SDL window info: {s}\n", .{c.SDL_GetError()});
        return null;
    }

    const surface_source = c.WGPUSurfaceSourceWindowsHWND{
        .chain = .{
            .next = null,
            .sType = c.WGPUSType_SurfaceSourceWindowsHWND,
        },
        .hwnd = info.info.win.window,
        .hinstance = info.info.win.hinstance,
    };

    const surface_descriptor = c.WGPUSurfaceDescriptor{
        .nextInChain = @ptrCast(&surface_source.chain),
        .label = .{ .data = "SDL Surface", .length = c.WGPU_STRLEN },
    };

    return c.wgpuInstanceCreateSurface(instance, &surface_descriptor);
}

fn adapterCallback(
    status: c.WGPURequestAdapterStatus,
    adapter: c.WGPUAdapter,
    message: c.WGPUStringView,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void {
    _ = userdata2;
    _ = message;
    const state: *State = @ptrCast(@alignCast(userdata1));
    if (status != c.WGPURequestAdapterStatus_Success) {
        std.debug.print("Failed to get adapter\n", .{});
        return;
    }
    state.adapter = adapter;
    onAdapter(state);
}

fn deviceCallback(
    status: c.WGPURequestDeviceStatus,
    device: c.WGPUDevice,
    message: c.WGPUStringView,
    userdata1: ?*anyopaque,
    userdata2: ?*anyopaque,
) callconv(.c) void {
    _ = userdata2;
    _ = message;
    const state: *State = @ptrCast(@alignCast(userdata1));
    if (status != c.WGPURequestDeviceStatus_Success) {
        std.debug.print("Failed to get device\n", .{});
        return;
    }
    state.device = device;
    onDevice(state);
}

fn initWgpu(state: *State, window: *c.SDL_Window) void {
    state.instance = c.wgpuCreateInstance(null);
    if (state.instance == null) {
        std.debug.print("Failed to create wgpu instance\n", .{});
        return;
    }

    state.surface = createSurfaceFromSdl(state.instance, window);
    if (state.surface == null) {
        std.debug.print("Failed to create surface\n", .{});
        return;
    }

    const adapter_options = c.WGPURequestAdapterOptions{
        .compatibleSurface = state.surface,
        .powerPreference = c.WGPUPowerPreference_HighPerformance,
    };

    const callback_info = c.WGPURequestAdapterCallbackInfo{
        .mode = c.WGPUCallbackMode_WaitAnyOnly,
        .callback = adapterCallback,
        .userdata1 = state,
        .userdata2 = null,
    };

    _ = c.wgpuInstanceRequestAdapter(state.instance, &adapter_options, callback_info);
}

fn onAdapter(state: *State) void {
    const callback_info = c.WGPURequestDeviceCallbackInfo{
        .mode = c.WGPUCallbackMode_WaitAnyOnly,
        .callback = deviceCallback,
        .userdata1 = state,
        .userdata2 = null,
    };

    _ = c.wgpuAdapterRequestDevice(state.adapter, null, callback_info);
}

fn onDevice(state: *State) void {
    state.queue = c.wgpuDeviceGetQueue(state.device);

    var caps: c.WGPUSurfaceCapabilities = std.mem.zeroes(c.WGPUSurfaceCapabilities);
    const caps_status = c.wgpuSurfaceGetCapabilities(state.surface, state.adapter, &caps);
    if (caps_status != c.WGPUStatus_Success) {
        std.debug.print("Failed to get surface capabilities\n", .{});
        return;
    }
    const surface_format = caps.formats[0];

    state.surface_config = .{
        .device = state.device,
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .format = surface_format,
        .width = state.width,
        .height = state.height,
        .presentMode = c.WGPUPresentMode_Fifo,
        .alphaMode = caps.alphaModes[0],
    };
    c.wgpuSurfaceConfigure(state.surface, &state.surface_config);

    createDepthTexture(state);
    createBuffers(state);
    createPipeline(state, surface_format);

    state.model = za.Mat4.identity();
    state.initialized = true;

    c.wgpuSurfaceCapabilitiesFreeMembers(caps);
}

fn createDepthTexture(state: *State) void {
    if (state.depth_texture != null) {
        c.wgpuTextureDestroy(state.depth_texture);
        c.wgpuTextureRelease(state.depth_texture);
    }
    if (state.depth_view != null) {
        c.wgpuTextureViewRelease(state.depth_view);
    }

    const depth_texture_desc = c.WGPUTextureDescriptor{
        .size = .{ .width = state.width, .height = state.height, .depthOrArrayLayers = 1 },
        .mipLevelCount = 1,
        .sampleCount = 1,
        .dimension = c.WGPUTextureDimension_2D,
        .format = depth_format,
        .usage = c.WGPUTextureUsage_RenderAttachment,
    };

    state.depth_texture = c.wgpuDeviceCreateTexture(state.device, &depth_texture_desc);
    state.depth_view = c.wgpuTextureCreateView(state.depth_texture, null);
}

fn createBuffers(state: *State) void {
    const vertex_buffer_desc = c.WGPUBufferDescriptor{
        .label = .{ .data = "Vertex Buffer", .length = c.WGPU_STRLEN },
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
        .mappedAtCreation = @intFromBool(true),
    };
    state.vertex_buffer = c.wgpuDeviceCreateBuffer(state.device, &vertex_buffer_desc);
    const vertex_data = c.wgpuBufferGetMappedRange(state.vertex_buffer, 0, @sizeOf(@TypeOf(vertices)));
    @memcpy(@as([*]u8, @ptrCast(vertex_data)), std.mem.asBytes(&vertices));
    c.wgpuBufferUnmap(state.vertex_buffer);

    const index_buffer_desc = c.WGPUBufferDescriptor{
        .label = .{ .data = "Index Buffer", .length = c.WGPU_STRLEN },
        .size = @sizeOf(@TypeOf(indices)),
        .usage = c.WGPUBufferUsage_Index | c.WGPUBufferUsage_CopyDst,
        .mappedAtCreation = @intFromBool(true),
    };
    state.index_buffer = c.wgpuDeviceCreateBuffer(state.device, &index_buffer_desc);
    const index_data = c.wgpuBufferGetMappedRange(state.index_buffer, 0, @sizeOf(@TypeOf(indices)));
    @memcpy(@as([*]u8, @ptrCast(index_data)), std.mem.asBytes(&indices));
    c.wgpuBufferUnmap(state.index_buffer);

    const uniform_buffer_desc = c.WGPUBufferDescriptor{
        .label = .{ .data = "Uniform Buffer", .length = c.WGPU_STRLEN },
        .size = @sizeOf(UniformBuffer),
        .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
    };
    state.uniform_buffer = c.wgpuDeviceCreateBuffer(state.device, &uniform_buffer_desc);

    const bind_group_layout_entry = c.WGPUBindGroupLayoutEntry{
        .binding = 0,
        .visibility = c.WGPUShaderStage_Vertex,
        .buffer = .{ .type = c.WGPUBufferBindingType_Uniform },
    };

    const bind_group_layout_desc = c.WGPUBindGroupLayoutDescriptor{
        .entryCount = 1,
        .entries = &bind_group_layout_entry,
    };
    state.bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(state.device, &bind_group_layout_desc);

    const bind_group_entry = c.WGPUBindGroupEntry{
        .binding = 0,
        .buffer = state.uniform_buffer,
        .size = @sizeOf(UniformBuffer),
    };

    const bind_group_desc = c.WGPUBindGroupDescriptor{
        .layout = state.bind_group_layout,
        .entryCount = 1,
        .entries = &bind_group_entry,
    };
    state.bind_group = c.wgpuDeviceCreateBindGroup(state.device, &bind_group_desc);
}

fn createPipeline(state: *State, surface_format: c.WGPUTextureFormat) void {
    const wgsl_source = c.WGPUShaderSourceWGSL{
        .chain = .{
            .next = null,
            .sType = c.WGPUSType_ShaderSourceWGSL,
        },
        .code = .{ .data = shader_source.ptr, .length = shader_source.len },
    };

    const shader_module_desc = c.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&wgsl_source.chain),
    };
    const shader_module = c.wgpuDeviceCreateShaderModule(state.device, &shader_module_desc);
    defer c.wgpuShaderModuleRelease(shader_module);

    const pipeline_layout_desc = c.WGPUPipelineLayoutDescriptor{
        .bindGroupLayoutCount = 1,
        .bindGroupLayouts = &state.bind_group_layout,
    };
    const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(state.device, &pipeline_layout_desc);
    defer c.wgpuPipelineLayoutRelease(pipeline_layout);

    const vertex_attributes = [_]c.WGPUVertexAttribute{
        .{ .format = c.WGPUVertexFormat_Float32x4, .offset = 0, .shaderLocation = 0 },
        .{ .format = c.WGPUVertexFormat_Float32x4, .offset = @sizeOf([4]f32), .shaderLocation = 1 },
    };

    const blend_state = c.WGPUBlendState{
        .color = .{ .srcFactor = c.WGPUBlendFactor_SrcAlpha, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha, .operation = c.WGPUBlendOperation_Add },
        .alpha = .{ .srcFactor = c.WGPUBlendFactor_One, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha, .operation = c.WGPUBlendOperation_Add },
    };

    const color_target = c.WGPUColorTargetState{
        .format = surface_format,
        .blend = &blend_state,
        .writeMask = c.WGPUColorWriteMask_All,
    };

    const vertex_buffer_layout = c.WGPUVertexBufferLayout{
        .arrayStride = @sizeOf(Vertex),
        .stepMode = c.WGPUVertexStepMode_Vertex,
        .attributeCount = 2,
        .attributes = &vertex_attributes,
    };

    const depth_stencil = c.WGPUDepthStencilState{
        .format = depth_format,
        .depthWriteEnabled = c.WGPUOptionalBool_True,
        .depthCompare = c.WGPUCompareFunction_Less,
    };

    const fragment_state = c.WGPUFragmentState{
        .module = shader_module,
        .entryPoint = .{ .data = "fragment_main", .length = c.WGPU_STRLEN },
        .targetCount = 1,
        .targets = &color_target,
    };

    const pipeline_desc = c.WGPURenderPipelineDescriptor{
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entryPoint = .{ .data = "vertex_main", .length = c.WGPU_STRLEN },
            .bufferCount = 1,
            .buffers = &vertex_buffer_layout,
        },
        .primitive = .{
            .topology = c.WGPUPrimitiveTopology_TriangleList,
            .frontFace = c.WGPUFrontFace_CW,
            .cullMode = c.WGPUCullMode_None,
        },
        .depthStencil = &depth_stencil,
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
        },
        .fragment = &fragment_state,
    };

    state.pipeline = c.wgpuDeviceCreateRenderPipeline(state.device, &pipeline_desc);
}

fn resize(state: *State, width: u32, height: u32) void {
    if (!state.initialized) {
        return;
    }
    state.width = width;
    state.height = height;
    state.surface_config.width = width;
    state.surface_config.height = height;
    c.wgpuSurfaceConfigure(state.surface, &state.surface_config);
    createDepthTexture(state);
}

fn update(state: *State, delta_time: f32) void {
    const aspect = @as(f32, @floatFromInt(state.width)) / @as(f32, @floatFromInt(@max(state.height, 1)));

    const projection = za.perspective(std.math.degreesToRadians(80.0), aspect, 0.1, 1000.0);
    const view = za.lookAt(za.Vec3.new(0.0, 0.0, 3.0), za.Vec3.zero(), za.Vec3.up());
    const rotation = za.Mat4.fromRotation(std.math.degreesToRadians(30.0) * delta_time, za.Vec3.up());
    state.model = rotation.mul(state.model);

    const mvp = projection.mul(view.mul(state.model));
    const uniform = UniformBuffer{ .mvp = mvp.data };

    c.wgpuQueueWriteBuffer(state.queue, state.uniform_buffer, 0, &uniform, @sizeOf(UniformBuffer));
}

fn render(state: *State) void {
    var surface_texture: c.WGPUSurfaceTexture = undefined;
    c.wgpuSurfaceGetCurrentTexture(state.surface, &surface_texture);

    if (surface_texture.status != c.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal and
        surface_texture.status != c.WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal)
    {
        return;
    }

    const surface_view = c.wgpuTextureCreateView(surface_texture.texture, null);
    defer c.wgpuTextureViewRelease(surface_view);

    const encoder = c.wgpuDeviceCreateCommandEncoder(state.device, null);

    const color_attachment = c.WGPURenderPassColorAttachment{
        .view = surface_view,
        .loadOp = c.WGPULoadOp_Clear,
        .storeOp = c.WGPUStoreOp_Store,
        .clearValue = .{ .r = 0.19, .g = 0.24, .b = 0.42, .a = 1.0 },
        .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
    };

    const depth_attachment = c.WGPURenderPassDepthStencilAttachment{
        .view = state.depth_view,
        .depthLoadOp = c.WGPULoadOp_Clear,
        .depthStoreOp = c.WGPUStoreOp_Store,
        .depthClearValue = 1.0,
    };

    const render_pass_desc = c.WGPURenderPassDescriptor{
        .colorAttachmentCount = 1,
        .colorAttachments = &color_attachment,
        .depthStencilAttachment = &depth_attachment,
    };

    const render_pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &render_pass_desc);

    c.wgpuRenderPassEncoderSetPipeline(render_pass, state.pipeline);
    c.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, state.bind_group, 0, null);
    c.wgpuRenderPassEncoderSetVertexBuffer(render_pass, 0, state.vertex_buffer, 0, @sizeOf(@TypeOf(vertices)));
    c.wgpuRenderPassEncoderSetIndexBuffer(render_pass, state.index_buffer, c.WGPUIndexFormat_Uint32, 0, @sizeOf(@TypeOf(indices)));
    c.wgpuRenderPassEncoderDrawIndexed(render_pass, indices.len, 1, 0, 0, 0);

    c.wgpuRenderPassEncoderEnd(render_pass);
    c.wgpuRenderPassEncoderRelease(render_pass);

    const command_buffer = c.wgpuCommandEncoderFinish(encoder, null);
    c.wgpuCommandEncoderRelease(encoder);

    c.wgpuQueueSubmit(state.queue, 1, &command_buffer);
    c.wgpuCommandBufferRelease(command_buffer);

    _ = c.wgpuSurfacePresent(state.surface);
    c.wgpuTextureRelease(surface_texture.texture);
}

fn cleanup(state: *State) void {
    if (state.pipeline != null) c.wgpuRenderPipelineRelease(state.pipeline);
    if (state.bind_group != null) c.wgpuBindGroupRelease(state.bind_group);
    if (state.bind_group_layout != null) c.wgpuBindGroupLayoutRelease(state.bind_group_layout);
    if (state.uniform_buffer != null) c.wgpuBufferRelease(state.uniform_buffer);
    if (state.index_buffer != null) c.wgpuBufferRelease(state.index_buffer);
    if (state.vertex_buffer != null) c.wgpuBufferRelease(state.vertex_buffer);
    if (state.depth_view != null) c.wgpuTextureViewRelease(state.depth_view);
    if (state.depth_texture != null) {
        c.wgpuTextureDestroy(state.depth_texture);
        c.wgpuTextureRelease(state.depth_texture);
    }
    if (state.queue != null) c.wgpuQueueRelease(state.queue);
    if (state.device != null) c.wgpuDeviceRelease(state.device);
    if (state.adapter != null) c.wgpuAdapterRelease(state.adapter);
    if (state.surface != null) c.wgpuSurfaceRelease(state.surface);
    if (state.instance != null) c.wgpuInstanceRelease(state.instance);
}
