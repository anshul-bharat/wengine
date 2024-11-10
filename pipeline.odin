package wengine

import "vendor:wgpu"

pipeline_create :: proc(state: ^State) {

	attrs := []wgpu.VertexAttribute {
		wgpu.VertexAttribute{offset = 0, shaderLocation = 0, format = wgpu.VertexFormat.Float32x3},
		wgpu.VertexAttribute {
			offset = 3 * size_of(f32),
			shaderLocation = 1,
			format = wgpu.VertexFormat.Float32x2,
		},
		wgpu.VertexAttribute {
			offset = 5 * size_of(f32),
			shaderLocation = 2,
			format = wgpu.VertexFormat.Float32x3,
		},
		wgpu.VertexAttribute {
			offset = 8 * size_of(f32),
			shaderLocation = 3,
			format = wgpu.VertexFormat.Float32x3,
		},
	}
	iattrs := []wgpu.VertexAttribute {
		wgpu.VertexAttribute{offset = 0, shaderLocation = 5, format = wgpu.VertexFormat.Float32x4},
		wgpu.VertexAttribute {
			offset = 4 * size_of(f32),
			shaderLocation = 6,
			format = wgpu.VertexFormat.Float32x4,
		},
		wgpu.VertexAttribute {
			offset = 8 * size_of(f32),
			shaderLocation = 7,
			format = wgpu.VertexFormat.Float32x4,
		},
		wgpu.VertexAttribute {
			offset = 12 * size_of(f32),
			shaderLocation = 8,
			format = wgpu.VertexFormat.Float32x4,
		},
	}


	state.pipeline = wgpu.DeviceCreateRenderPipeline(
		state.device,
		&wgpu.RenderPipelineDescriptor {
			layout = state.pipeline_layout,
			vertex = wgpu.VertexState {
				module = state.module,
				entryPoint = "vs_main",
				buffers = raw_data(
					[]wgpu.VertexBufferLayout {
						{
							arrayStride = size_of(Vertex),
							stepMode = wgpu.VertexStepMode.Vertex,
							attributes = raw_data(attrs),
							attributeCount = len(attrs),
						},
						{
							arrayStride = size_of(InstanceRaw),
							stepMode = wgpu.VertexStepMode.Instance,
							attributes = raw_data(iattrs),
							attributeCount = len(iattrs),
						},
					},
				),
				bufferCount = 2,
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
			depthStencil = &wgpu.DepthStencilState {
				format = DEPTH_FORMAT,
				depthWriteEnabled = true,
				depthCompare = wgpu.CompareFunction.Less,
				stencilFront = wgpu.StencilFaceState {
					compare = wgpu.CompareFunction.Always,
					failOp = wgpu.StencilOperation.Keep,
					depthFailOp = wgpu.StencilOperation.Keep,
					passOp = wgpu.StencilOperation.Keep,
				},
				stencilBack = wgpu.StencilFaceState {
					compare = wgpu.CompareFunction.Always,
					failOp = wgpu.StencilOperation.Keep,
					depthFailOp = wgpu.StencilOperation.Keep,
					passOp = wgpu.StencilOperation.Keep,
				},
				stencilReadMask = 0,
				stencilWriteMask = 0,
				depthBias = 0,
				depthBiasSlopeScale = 0,
				depthBiasClamp = 0,
			},
		},
	)
}

