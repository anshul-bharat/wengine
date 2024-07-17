package wengine

import "base:runtime"

import "core:bytes"
import "core:image/png"
import "core:log"
import "core:math/linalg"
import "core:os"

import "vendor:wgpu"

State :: struct {
	ctx:             runtime.Context,
	os:              OS,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,
	camera:          Camera,
}

Texture :: struct {
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
}

Mesh :: struct {
	vertices:      []Vertex,
	indices:       []u16,
	vertex_buffer: wgpu.Buffer,
	index_buffer:  wgpu.Buffer,
}

ShaderBindGroup :: struct {
	// code:              string,
	// module:            wgpu.ShaderModule,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	// buffers:           []wgpu.Buffer,
	buffer:            wgpu.Buffer,
}

Vertex :: struct {
	position:   [3]f32,
	color:      [3]f32,
	tex_coords: [2]f32,
}

ColorAngle :: struct {
	color: f32,
	angle: f32,
}

Camera :: struct {
	eye:    [3]f32,
	target: [3]f32,
	up:     [3]f32,
	aspect: f32,
	fovy:   f32,
	znear:  f32,
	zfar:   f32,
}

MESHES: [dynamic]Mesh
TEXTURES: [dynamic]Texture
SHADER_BIND_GROUPS: [dynamic]ShaderBindGroup

uniforms := ColorAngle {
	color = 0.7,
	angle = 0.01,
}

@(private = "file")
state: State

VERTICES :: []Vertex {
	Vertex {
		position = {-0.0868241, 0.49240386, 0.0},
		color = {0.0, 0.0, 0.5},
		tex_coords = {0.4131759, 0.00759614},
	}, // A
	Vertex {
		position = {-0.49513406, 0.06958647, 0.0},
		color = {0.5, 0.0, 0.5},
		tex_coords = {0.0048659444, 0.43041354},
	}, // B
	Vertex {
		position = {-0.21918549, -0.44939706, 0.0},
		color = {0.5, 0.0, 0.5},
		tex_coords = {0.28081453, 0.949397},
	}, // C
	Vertex {
		position = {.35966998, -0.3473291, 0.0},
		color = {0.5, 0.0, 0.5},
		tex_coords = {0.85967, 0.84732914},
	}, // D
	Vertex {
		position = {.44147372, 0.2347359, 0.0},
		color = {0.5, 0.0, 0.5},
		tex_coords = {0.9414737, 0.2652641},
	}, // E
}

INDICES := []u16{0, 1, 4, 1, 2, 4, 2, 3, 4, 0}

OPENGL_TO_WGPU_MATRIX :: matrix[4, 4]f32{
	1.0, 0.0, 0.0, 0.0, 
	0.0, 1.0, 0.0, 0.0, 
	0.0, 0.0, 0.5, 0.5, 
	0.0, 0.0, 0.0, 1.0, 
}

camera_build_view_projection_matrix :: proc(camera: ^Camera) -> matrix[4, 4]f32 {
	view := linalg.matrix4_look_at(camera.eye, camera.target, camera.up)

	proj := linalg.matrix4_perspective(
		linalg.to_degrees(camera.fovy),
		camera.aspect,
		camera.znear,
		camera.zfar,
	)

	return OPENGL_TO_WGPU_MATRIX * proj * view
}

vertices_get_translated :: proc(vertices: []Vertex, point: [3]f32) -> []Vertex {
	translated := vertices

	for _, i in translated {
		translated[i].position += point // [?]f32{0.0, 0.0, 0.0}
	}

	return translated
}

mesh_create :: proc(device: wgpu.Device, vertices: []Vertex, indices: []u16) -> Mesh {
	mesh: Mesh
	mesh.vertices = vertices
	mesh.indices = indices

	mesh.vertex_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "Vertex buffer data", usage = {.Vertex, .CopyDst}},
		vertices,
	)

	mesh.index_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "Index buffer data", usage = {.Index}},
		indices,
	)

	return mesh
}

shader_bind_group_create :: proc(device: wgpu.Device, data: []$T) -> ShaderBindGroup {
	shader: ShaderBindGroup

	count: uint = len(data)
	buffer := wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "shader buffer", usage = {.Uniform, .CopyDst}},
		data,
	)

	bind_group_layout_entries := [dynamic]wgpu.BindGroupLayoutEntry{}

	bind_group_entries := [dynamic]wgpu.BindGroupEntry{}

	for i in 0 ..< count {
		layout_entry := wgpu.BindGroupLayoutEntry {
			binding = cast(u32)i,
			visibility = {wgpu.ShaderStage.Vertex},
			buffer = wgpu.BufferBindingLayout {
				type = wgpu.BufferBindingType.Uniform,
				hasDynamicOffset = false,
				minBindingSize = 0,
			},
			// sampler = SamplerBindingLayout,
			// texture = TextureBindingLayout,
			// storageTexture = StorageTextureBindingLayout,
		}

		group_entry := wgpu.BindGroupEntry {
			binding     = cast(u32)i,
			/* NULLABLE */
			buffer      = buffer,
			offset      = cast(u64)(i * size_of(T)),
			size        = size_of(T),
			/* NULLABLE */
			sampler     = nil,
			/* NULLABLE */
			textureView = nil,
		}

		append(&bind_group_layout_entries, layout_entry)
		append(&bind_group_entries, group_entry)
	}

	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "camera bind group layout",
			entryCount = count,
			entries = raw_data(bind_group_layout_entries),
		},
	)

	bind_group := wgpu.DeviceCreateBindGroup(
		device,
		&wgpu.BindGroupDescriptor {
			layout = bind_group_layout,
			entryCount = count,
			entries = raw_data(bind_group_entries),
		},
	)

	shader.bind_group_layout = bind_group_layout
	shader.bind_group = bind_group
	shader.buffer = buffer
	return shader
}

texture_create :: proc(device: wgpu.Device) -> Texture {

	diffuse_bytes := #load("assets/happy-tree.png")
	diffuse_image, err := png.load_from_bytes(diffuse_bytes)
	diffuse_rgba := bytes.buffer_to_bytes(&diffuse_image.pixels)

	texture_size := wgpu.Extent3D {
		width              = cast(u32)diffuse_image.width,
		height             = cast(u32)diffuse_image.height,
		depthOrArrayLayers = 1,
	}

	diffuse_texture := wgpu.DeviceCreateTexture(
		device,
		&wgpu.TextureDescriptor {
			label         = "diffuse_texture",
			size          = texture_size,
			mipLevelCount = 1,
			sampleCount   = 1,
			dimension     = wgpu.TextureDimension._2D,
			format        = wgpu.TextureFormat.RGBA8UnormSrgb,
			usage         = {.TextureBinding, .CopyDst},
			// view_formats = 
		},
	)

	wgpu.QueueWriteTexture(
		state.queue,
		&wgpu.ImageCopyTexture {
			texture = diffuse_texture,
			mipLevel = 0,
			origin = wgpu.Origin3D{0, 0, 0},
			aspect = wgpu.TextureAspect.All,
		},
		raw_data(diffuse_rgba),
		size_of(u8) * len(diffuse_rgba),
		&wgpu.TextureDataLayout {
			offset = 0,
			bytesPerRow = 4 * cast(u32)diffuse_image.width,
			rowsPerImage = cast(u32)diffuse_image.height,
		},
		&texture_size,
	)

	diffuse_texture_view := wgpu.TextureCreateView(diffuse_texture)
	diffuse_sampler := wgpu.DeviceCreateSampler(
		state.device,
		&wgpu.SamplerDescriptor {
			addressModeU = wgpu.AddressMode.ClampToEdge,
			addressModeV = wgpu.AddressMode.ClampToEdge,
			addressModeW = wgpu.AddressMode.ClampToEdge,
			magFilter = wgpu.FilterMode.Linear,
			minFilter = wgpu.FilterMode.Nearest,
			mipmapFilter = wgpu.MipmapFilterMode.Nearest,
			lodMinClamp = 0,
			lodMaxClamp = 32,
			maxAnisotropy = 1,
		},
	)

	texture_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		state.device,
		&wgpu.BindGroupLayoutDescriptor {
			label      = "texture_bind_group_layout",
			entryCount = 2,
			entries    = raw_data(
				[]wgpu.BindGroupLayoutEntry {
					wgpu.BindGroupLayoutEntry {
						binding = 0,
						visibility = {.Fragment},
						// buffer = BufferBindingLayout,
						// sampler = SamplerBindingLayout,
						texture = wgpu.TextureBindingLayout {
							sampleType = wgpu.TextureSampleType.Float,
							viewDimension = wgpu.TextureViewDimension._2D,
							multisampled = false,
						},
					},
					wgpu.BindGroupLayoutEntry {
						binding = 1,
						visibility = {.Fragment},
						sampler = wgpu.SamplerBindingLayout {
							type = wgpu.SamplerBindingType.Filtering,
						},
					},
				},
			),
		},
	)

	diffuse_bind_group := wgpu.DeviceCreateBindGroup(
		state.device,
		&wgpu.BindGroupDescriptor {
			label = "diffuse_bind_group",
			layout = texture_bind_group_layout,
			entryCount = 2,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					wgpu.BindGroupEntry {
						binding = 0,
						offset = 0,
						size = 0,
						textureView = diffuse_texture_view,
					},
					wgpu.BindGroupEntry {
						binding = 1,
						offset = 0,
						size = 0,
						sampler = diffuse_sampler,
					},
				},
			),
		},
	)

	return Texture{bind_group_layout = texture_bind_group_layout, bind_group = diffuse_bind_group}
}

main :: proc() {
	context.logger = log.create_console_logger()
	state.ctx = context
	os_init(&state.os)

	state.instance = wgpu.CreateInstance(nil)
	if state.instance == nil {
		panic("WebGPU is not supported")
	}
	state.surface = os_get_surface(&state.os, state.instance)

	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		on_adapter,
		nil,
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: cstring,
		userdata: rawptr,
	) {
		context = state.ctx
		if status != .Success || adapter == nil {
			log.panicf("request adapter failure: [%v] %s", status, message)
		}
		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, on_device)
	}

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: cstring,
		userdata: rawptr,
	) {
		context = state.ctx
		if status != .Success || device == nil {
			log.panicf("request device failure: [%v] %s", status, message)
		}
		state.device = device

		width, height := os_get_render_bounds(&state.os)

		state.config = wgpu.SurfaceConfiguration {
			device      = state.device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			width       = width,
			height      = height,
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}
		wgpu.SurfaceConfigure(state.surface, &state.config)

		state.queue = wgpu.DeviceGetQueue(state.device)

		shader :: #load("shader.wgsl", cstring)

		state.module = wgpu.DeviceCreateShaderModule(
			state.device,
			&{
				nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
					sType = .ShaderModuleWGSLDescriptor,
					code = shader,
				},
			},
		)


		//camera
		state.camera = Camera {
			eye    = [3]f32{0.0, 1.0, 2.0},
			target = [3]f32{0.0, 0.0, 0.0},
			up     = [3]f32{0.0, 1.0, 0.0},
			aspect = cast(f32)state.config.width / cast(f32)state.config.height,
			fovy   = 45.0,
			znear  = 0.1,
			zfar   = 100.0,
		}
		//camera end

		shader_bind_group_1 := shader_bind_group_create(device, []ColorAngle{uniforms})
		shader_bind_group_2 := shader_bind_group_create(
			device,
			[]matrix[4, 4]f32{camera_build_view_projection_matrix(&state.camera)},
		)
		append(&SHADER_BIND_GROUPS, shader_bind_group_1)
		append(&SHADER_BIND_GROUPS, shader_bind_group_2)


		texture_1 := texture_create(device)
		append(&TEXTURES, texture_1)

		meshes_1 := mesh_create(
			device,
			vertices_get_translated(VERTICES, [?]f32{0.5, 0.0, 0.0}),
			INDICES,
		)
		meshes_2 := mesh_create(
			device,
			vertices_get_translated(VERTICES, [?]f32{-0.5, 0.0, 0.0}),
			INDICES,
		)
		append(&MESHES, meshes_1)
		append(&MESHES, meshes_2)

		bind_group_layouts := [dynamic]wgpu.BindGroupLayout{}
		for l in SHADER_BIND_GROUPS {
			append(&bind_group_layouts, l.bind_group_layout)
		}
		for l in TEXTURES {
			append(&bind_group_layouts, l.bind_group_layout)
		}

		state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			state.device,
			&wgpu.PipelineLayoutDescriptor {
				label = "render pipeline layout",
				bindGroupLayoutCount = len(SHADER_BIND_GROUPS) + 1,
				bindGroupLayouts = raw_data(bind_group_layouts),
			},
		)

		attrs := []wgpu.VertexAttribute {
			wgpu.VertexAttribute {
				offset = 0,
				shaderLocation = 0,
				format = wgpu.VertexFormat.Float32x3,
			},
			wgpu.VertexAttribute {
				offset = 3 * size_of(f32),
				shaderLocation = 1,
				format = wgpu.VertexFormat.Float32x3,
			},
			wgpu.VertexAttribute {
				offset = 6 * size_of(f32),
				shaderLocation = 2,
				format = wgpu.VertexFormat.Float32x2,
			},
		}

		state.pipeline = wgpu.DeviceCreateRenderPipeline(
			state.device,
			&wgpu.RenderPipelineDescriptor {
				layout = state.pipeline_layout,
				vertex = wgpu.VertexState {
					module = state.module,
					entryPoint = "vs_main",
					buffers = &wgpu.VertexBufferLayout {
						arrayStride = 8 * size_of(f32),
						stepMode = wgpu.VertexStepMode.Vertex,
						attributes = raw_data(attrs),
						attributeCount = len(attrs),
					},
					bufferCount = 1,
				},
				fragment = &{
					module = state.module,
					entryPoint = "fs_main",
					targetCount = 1,
					targets = &wgpu.ColorTargetState {
						format = .BGRA8Unorm,
						writeMask = wgpu.ColorWriteMaskFlags_All,
					},
				},
				primitive = {topology = .TriangleList},
				multisample = {count = 1, mask = 0xFFFFFFFF},
			},
		)

		os_run(&state.os)
	}
}

resize :: proc "c" () {
	context = state.ctx

	state.config.width, state.config.height = os_get_render_bounds(&state.os)
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

process_key_event :: proc "c" (key_event: KeyEvent) {
	context = runtime.default_context()

	#partial switch key_event.key_code {
	case KeyCode.ARROW_LEFT:
		state.camera.eye.x += 1
	case KeyCode.ARROW_RIGHT:
		state.camera.eye.x -= 1
	case KeyCode.ESCAPE:
		os.exit(0)
	}

	log.info(key_event)
}

frame :: proc "c" (dt: f32) {
	context = state.ctx

	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
	case .Success:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		resize()
		return
	case .OutOfMemory, .DeviceLost:
		// Fatal error
		log.panicf("[triangle] get_current_texture status=%v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	frame := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(frame)

	command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = frame,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {r = 0, g = 0, b = 0, a = 1},
			},
		},
	)
	defer wgpu.RenderPassEncoderRelease(render_pass_encoder)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)

	for texture, i in TEXTURES {
		wgpu.RenderPassEncoderSetBindGroup(
			render_pass_encoder,
			cast(u32)(len(SHADER_BIND_GROUPS) + i),
			texture.bind_group,
			[]u32{},
		)
	}

	for shader_bind_group, i in SHADER_BIND_GROUPS {
		if i == 0 {
			wgpu.QueueWriteBuffer(
				state.queue,
				shader_bind_group.buffer,
				0,
				raw_data([]ColorAngle{uniforms}),
				size_of(ColorAngle),
			)
		} else if i == 1 {
			wgpu.QueueWriteBuffer(
				state.queue,
				shader_bind_group.buffer,
				0,
				raw_data([]matrix[4, 4]f32{camera_build_view_projection_matrix(&state.camera)}),
				size_of(ColorAngle),
			)
		}
		wgpu.RenderPassEncoderSetBindGroup(
			render_pass_encoder,
			cast(u32)i,
			shader_bind_group.bind_group,
		)
	}

	uniforms.color += 0.1
	uniforms.angle += 0.01

	for mesh in MESHES {
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass_encoder,
			0,
			mesh.vertex_buffer,
			0,
			wgpu.BufferGetSize(mesh.vertex_buffer),
		)

		wgpu.RenderPassEncoderSetIndexBuffer(
			render_pass_encoder,
			mesh.index_buffer,
			wgpu.IndexFormat.Uint16,
			0,
			wgpu.BufferGetSize(mesh.index_buffer),
		)

		wgpu.RenderPassEncoderDrawIndexed(
			render_pass_encoder,
			cast(u32)len(mesh.indices),
			1,
			0,
			0,
			0,
		)
	}
	wgpu.RenderPassEncoderEnd(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

finish :: proc() {
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
}

