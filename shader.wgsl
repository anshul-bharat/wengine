struct ColorAngle {
	color: f32,
	angle: f32,
};

struct CameraUniform {
	view_proj: mat4x4<f32>,
}

@group(0) @binding(0)
var<uniform> uniforms: ColorAngle;

@group(1) @binding(0)
var<uniform> camera: CameraUniform;

struct VertexInput {
	@location(0) position: vec3<f32>,
	@location(1) tex_coords: vec2<f32>,
	@location(2) normal: vec3<f32>,
	@location(3) color: vec3<f32>,
};

struct InstanceInput {
	@location(5) model_matrix_0: vec4<f32>,
	@location(6) model_matrix_1: vec4<f32>,
	@location(7) model_matrix_2: vec4<f32>,
	@location(8) model_matrix_3: vec4<f32>,
};

struct VertexOutput {
	@builtin(position) clip_position: vec4<f32>,
	@location(0) color: vec3<f32>,
	@location(1) tex_coords: vec2<f32>,
};

@vertex
fn vs_main(model: VertexInput, instance: InstanceInput) -> VertexOutput {

	let model_matrix = mat4x4<f32>(
		instance.model_matrix_0,
		instance.model_matrix_1,
		instance.model_matrix_2,
		instance.model_matrix_3,
	);

    var out: VertexOutput;
    out.clip_position = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    out.clip_position.x += cos(uniforms.angle);
    out.clip_position.y += sin(uniforms.angle);
    out.clip_position += vec4<f32>(model.position, 1.0);

	out.clip_position = camera.view_proj * model_matrix * vec4<f32>(model.position, 1.0);
	
    out.color = vec3<f32>(0,0,0); //model.color * abs(sin(uniforms.color));
	out.tex_coords = model.tex_coords;
    return out;
}


@group(2) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(2) @binding(1)
var s_diffuse: sampler;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // return vec4<f32>(in.color, 1.0);
	return textureSample(t_diffuse, s_diffuse, in.tex_coords) + vec4<f32>(in.color, 1.0);
}
