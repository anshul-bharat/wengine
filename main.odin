package wengine

import "base:runtime"

import "core:bytes"
import "core:image/png"
import "core:log"
import "core:math/linalg"

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
	// instances:       [dynamic]Instance,
	// instance_buffer: wgpu.Buffer,
	depth_texture:   DepthTexture,
	models:          [dynamic]Model,
}


ShaderBindGroup :: struct {
	// code:              string,
	// module:            wgpu.ShaderModule,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	// buffers:           []wgpu.Buffer,
	buffer:            wgpu.Buffer,
	type_size:         uint,
	data_type:         typeid,
	data:              rawptr,
}

ColorAngle :: struct {
	color: f32,
	angle: f32,
}

uniforms := ColorAngle {
	color = 0.7,
	angle = 0.01,
}

camera_controller := CameraController {
	speed = 0.2,
}

@(private = "file")
state: State

get_state :: proc() -> ^State {
	return &state
}

// MESHES: [dynamic]Mesh
// MODELS: [dynamic]Model
TEXTURES: [dynamic]DiffuseTexture
SHADER_BIND_GROUPS: [dynamic]ShaderBindGroup

VERTICES := [dynamic]Vertex {
	Vertex {
		position = {-0.0868241, 0.49240386, 0.0},
		tex_coords = {0.4131759, 0.00759614},
		normal = {0.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.5},
	}, // A
	Vertex {
		position = {-0.49513406, 0.06958647, 0.0},
		tex_coords = {0.0048659444, 0.43041354},
		normal = {0.0, 0.0, 0.0},
		color = {0.5, 0.0, 0.5},
	}, // B
	Vertex {
		position = {-0.21918549, -0.44939706, 0.0},
		tex_coords = {0.28081453, 0.949397},
		normal = {0.0, 0.0, 0.0},
		color = {0.5, 0.0, 0.5},
	}, // C
	Vertex {
		position = {.35966998, -0.3473291, 0.0},
		tex_coords = {0.85967, 0.84732914},
		normal = {0.0, 0.0, 0.0},
		color = {0.5, 0.0, 0.5},
	}, // D
	Vertex {
		position = {.44147372, 0.2347359, 0.0},
		tex_coords = {0.9414737, 0.2652641},
		normal = {0.0, 0.0, 0.0},
		color = {0.5, 0.0, 0.5},
	}, // E
}

INDICES := [dynamic]u16{0, 1, 4, 1, 2, 4, 2, 3, 4, 0}

OPENGL_TO_WGPU_MATRIX :: matrix[4, 4]f32{
	1.0, 0.0, 0.0, 0.0, 
	0.0, 1.0, 0.0, 0.0, 
	0.0, 0.0, 0.5, 0.5, 
	0.0, 0.0, 0.0, 1.0, 
}

NUM_INSTANCES_PER_ROW := 10
SPACE_BETWEEN: f32 = 3.0
INSTANCE_DISPLACEMENT := [3]f32 {
	cast(f32)NUM_INSTANCES_PER_ROW * 0.5,
	0.0,
	cast(f32)NUM_INSTANCES_PER_ROW * 0.5,
}

instance_to_raw :: proc(instance: ^Instance) -> InstanceRaw {
	return InstanceRaw {
		model = linalg.matrix4_translate(instance.position) *
		linalg.matrix4_from_quaternion(instance.rotation),
	}
}

shader_bind_group_update :: proc(shader_bind_group: ^ShaderBindGroup) {
	data := camera_build_view_projection_matrix(&state.camera)

	shader_bind_group.data = raw_data([]CameraUniform{data})
}

vertices_get_translated :: proc(vertices: [dynamic]Vertex, point: [3]f32) -> [dynamic]Vertex {
	translated := [dynamic]Vertex{}

	for _, i in vertices {
		v := vertices[i]
		v.position += point
		append(&translated, v) // [?]f32{0.0, 0.0, 0.0}
	}

	return translated
}


shader_bind_group_create :: proc(device: wgpu.Device, data: []$T) -> ShaderBindGroup {
	shader: ShaderBindGroup

	count: uint = len(data)
	buffer := wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "shader buffer", usage = {.Uniform, .CopyDst}},
		data,
	)

	// bind_group_layout_entries := [dynamic]wgpu.BindGroupLayoutEntry{}
	// bind_group_entries := [dynamic]wgpu.BindGroupEntry{}
	// defer {
	// 	clear(&bind_group_layout_entries)
	// 	clear(&bind_group_entries)
	// 	free(&bind_group_layout_entries)
	// 	free(&bind_group_entries)
	// }

	bind_group_layout_entry: wgpu.BindGroupLayoutEntry
	bind_group_entry: wgpu.BindGroupEntry
	assert(count == 1, "bind group data count should be 1")
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

		bind_group_entry = group_entry
		bind_group_layout_entry = layout_entry

		// append(&bind_group_layout_entries, layout_entry)
		// append(&bind_group_entries, group_entry)
	}

	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		device,
		&wgpu.BindGroupLayoutDescriptor {
			label      = "camera bind group layout",
			entryCount = count,
			// entries = raw_data(bind_group_layout_entries),
			entries    = &bind_group_layout_entry,
		},
	)

	bind_group := wgpu.DeviceCreateBindGroup(
		device,
		&wgpu.BindGroupDescriptor {
			layout     = bind_group_layout,
			entryCount = count,
			// entries = raw_data(bind_group_entries),
			entries    = &bind_group_entry,
		},
	)


	shader.bind_group_layout = bind_group_layout
	shader.bind_group = bind_group
	shader.buffer = buffer
	shader.type_size = size_of(T)
	shader.data_type = T

	return shader
}

_main :: proc() {

	context.logger = log.create_console_logger()
	// data_ptr := raw_data(&[3]u8{1, 2, 3})
	// data_slice := cast([^]u8)data_ptr
	// log.info(data_slice[1])

	state.ctx = context
	// model_load_obj(&state)
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

		state.depth_texture = texture_create_depth(&state.device, &state.config, "depth_texture")

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

		instance_data := make([dynamic]InstanceRaw)
		instances := [dynamic]Instance{}
		for z in 0 ..< NUM_INSTANCES_PER_ROW {
			for x in 0 ..< NUM_INSTANCES_PER_ROW {
				// position := [3]f32 {
				// 	cast(f32)x - (cast(f32)NUM_INSTANCES_PER_ROW * 0.5),
				// 	0.0,
				// 	cast(f32)z - (cast(f32)NUM_INSTANCES_PER_ROW * 0.5),
				// } // - INSTANCE_DISPLACEMENT

				_x := SPACE_BETWEEN * (f32(x) - INSTANCE_DISPLACEMENT.x)
				_z := SPACE_BETWEEN * (f32(z) - INSTANCE_DISPLACEMENT.z)

				position := [3]f32{_x, 0.0, _z}
				rotation: linalg.Quaternionf32
				if cast(i32)linalg.length(position) == 0 {
					rotation = linalg.quaternion_angle_axis_f32(0.0, [3]f32{0.0, 0.0, 1.0})
				} else {
					rotation = linalg.quaternion_angle_axis_f32(
						cast(f32)linalg.to_radians(45.0),
						linalg.normalize(position),
					)
				}
				instance := Instance {
					position = position,
					rotation = rotation,
				}
				append(&instance_data, instance_to_raw(&instance))
				append(&instances, instance)
			}
		}
		delete(instances)
		shader_bind_group_1 := shader_bind_group_create(device, []ColorAngle{uniforms})
		shader_bind_group_2 := shader_bind_group_create(
			device,
			[]CameraUniform{camera_build_view_projection_matrix(&state.camera)},
		)
		append(&SHADER_BIND_GROUPS, shader_bind_group_1)
		append(&SHADER_BIND_GROUPS, shader_bind_group_2)

		texture_1 := texture_create()
		append(&TEXTURES, texture_1)

		// model_load_obj("", nil, instance_data)
		instace_data_info := new(InstanceDataInfo)
		instace_data_info.instance_data_ptr = &instance_data
		model_load_obj_async("assets/cube.obj", nil, instace_data_info)
		// model_load_obj("", nil, &InstanceDataInfo{&instance_data})
		// model.meshes[0].instance_data = instance_data
		// model.meshes[0].instances = instances

		// mesh_1_vertices := vertices_get_translated(&VERTICES, [?]f32{0.5, 0.0, 0.0})
		// meshes_1 := mesh_create(device, &mesh_1_vertices, &INDICES, &instance_data)
		// log.info(model)
		// mesh_1_vertices := vertices_get_translated(model.meshes[0].vertices, [?]f32{0.5, 0.0, 0.0})
		// meshes_1 := mesh_create(device, mesh_1_vertices, model.meshes[0].indices, instance_data)
		// mesh_1 := model.meshes[0]

		// append(&state.models, model)
		// append(&MESHES, mesh_1)

		// meshes_2 := mesh_create(
		// 	device,
		// 	vertices_get_translated(VERTICES, [?]f32{-0.5, 0.0, 0.0}),
		// 	INDICES,
		// 	instance_data[:],
		// )
		// append(&MESHES, meshes_2)

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
		delete(bind_group_layouts)

		pipeline_create(&state)
		os_run(&state.os)
	}
}

resize :: proc "c" () {
	context = state.ctx

	state.config.width, state.config.height = os_get_render_bounds(&state.os)
	wgpu.SurfaceConfigure(state.surface, &state.config)

	state.depth_texture = texture_create_depth(&state.device, &state.config, "depth_texture")
}

process_key_event :: proc "c" (key_event: KeyEvent) {
	context = state.ctx

	#partial switch key_event.key_code {
	case KeyCode.ESCAPE:
		exit(0)
	}

	camera_controller_process_events(&camera_controller, key_event)
	camera_controller_update_camera(&camera_controller, &state.camera)
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
		&wgpu.RenderPassDescriptor {
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = frame,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0.5, 0.8, 1, 1},
			},
			depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
				view = state.depth_texture.view,
				depthLoadOp = wgpu.LoadOp.Clear,
				depthClearValue = 1.0,
				depthStoreOp = wgpu.StoreOp.Store,
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

	SHADER_BIND_GROUPS[0].data = raw_data([]ColorAngle{uniforms})
	SHADER_BIND_GROUPS[1].data = raw_data(
		[]CameraUniform{camera_build_view_projection_matrix(&state.camera)},
	)

	for shader_bind_group, i in SHADER_BIND_GROUPS {
		if i == 0 {
			wgpu.QueueWriteBuffer(
				state.queue,
				shader_bind_group.buffer,
				0,
				shader_bind_group.data,
				shader_bind_group.type_size,
			)
		} else if i == 1 {
			wgpu.QueueWriteBuffer(
				state.queue,
				shader_bind_group.buffer,
				0,
				shader_bind_group.data,
				shader_bind_group.type_size,
			)
		}
		wgpu.RenderPassEncoderSetBindGroup(
			render_pass_encoder,
			cast(u32)i,
			shader_bind_group.bind_group,
		)
	}

	// uniforms.color += 0.1
	uniforms.angle += 0.01

	for &model in state.models {
		model_render(&model, render_pass_encoder)
	}

	wgpu.RenderPassEncoderEnd(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

finish :: proc() {
	context = state.ctx
	log.info("Cleaning up")
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)

	// delete(state.instances)

	delete(SHADER_BIND_GROUPS)
	delete(TEXTURES)
	for model in state.models {
		model_delete(model)
		// for mesh in model.meshes {
		// 	mesh_delete(mesh)
		// }
	}
	delete(state.models)
	log.destroy_console_logger(context.logger)
}

