package wengine

import "core:bytes"
import "core:image/png"

import "vendor:wgpu"

Texture :: struct {
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
}

texture_create :: proc(state: ^State) -> Texture {

	device := state.device
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

