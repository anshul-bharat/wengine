package wengine

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:strconv"
import "core:strings"

import "vendor:wgpu"

Vertex :: struct {
	position:   [3]f32,
	tex_coords: [2]f32,
	normal:     [3]f32,
	color:      [3]f32,
}

Instance :: struct {
	position: [3]f32,
	rotation: linalg.Quaternionf32,
}

InstanceRaw :: struct {
	model: matrix[4, 4]f32,
}

Mesh :: struct {
	vertices:        [dynamic]Vertex,
	indices:         [dynamic]u16,
	vertex_buffer:   wgpu.Buffer,
	index_buffer:    wgpu.Buffer,
	instance_buffer: wgpu.Buffer,
	instance_count:  int,
	instance_data:   [dynamic]InstanceRaw,
	instances:       [dynamic]Instance,
	num_elements:    uint,
	material:        int,
}

mesh_create :: proc() -> ^Mesh {
	mesh := new(Mesh)
	mesh.vertices = make([dynamic]Vertex)
	mesh.indices = make([dynamic]u16)
	mesh.instance_data = make([dynamic]InstanceRaw)
	mesh.instances = make([dynamic]Instance)

	return mesh
}

Material :: struct {
	name:                   string,
	diffuse_texture:        DiffuseTexture,
	bind_group:             wgpu.BindGroup,

	/* ***************************** */
	ambient:                [3]f32,
	diffuse:                [3]f32,
	specular:               [3]f32,
	shininess:              [3]f32,
	emissive:               [3]f32,
	dissolve:               f32,
	optical_density:        f32,
	ambient_texture_name:   string,
	diffuse_texture_name:   string,
	specular_texture_name:  string,
	normal_texture_name:    string,
	shininess_texture_name: string,
	dissolve_texture_name:  string,
	illumination_model:     u8,
	unknown_param:          map[string]string,
}

Model :: struct {
	meshes:    [dynamic]^Mesh,
	materials: [dynamic]Material,
	is_loaded: bool,
}

model_delete :: proc(model: Model) {
	for mesh in model.meshes {
		mesh_delete(mesh^)
	}

	delete(model.meshes)
}

mesh_initialize_buffers :: proc(device: wgpu.Device, mesh: ^Mesh) {
	mesh^.vertex_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "Vertex buffer data", usage = {.Vertex, .CopyDst}},
		mesh^.vertices[:],
	)

	mesh^.index_buffer = wgpu.DeviceCreateBufferWithDataSlice(
		device,
		&wgpu.BufferWithDataDescriptor{label = "Index buffer data", usage = {.Index}},
		mesh^.indices[:],
	)

	if mesh^.instance_data != nil {
		mesh^.instance_buffer = wgpu.DeviceCreateBufferWithDataSlice(
			device,
			&wgpu.BufferWithDataDescriptor{label = "Instance buffer", usage = {.Vertex}},
			mesh^.instance_data[:],
		)
	}
}

mesh_delete :: proc(mesh: Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
	delete(mesh.instance_data)
	delete(mesh.instances)
}

mesh_render :: proc(mesh: ^Mesh, render_pass_encoder: wgpu.RenderPassEncoder) {

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass_encoder,
		0,
		mesh.vertex_buffer,
		0,
		wgpu.BufferGetSize(mesh.vertex_buffer),
	)

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass_encoder,
		1,
		mesh.instance_buffer,
		0,
		wgpu.BufferGetSize(mesh.instance_buffer),
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
		cast(u32)len(mesh.instance_data),
		0,
		0,
		0,
	)
}

model_render :: proc(model: ^Model, render_pass_encoder: wgpu.RenderPassEncoder) {
	if model.is_loaded == false {
		return
	}

	for &mesh in model.meshes {
		mesh_render(mesh, render_pass_encoder)
	}
}

VertexIndices :: struct {
	v:        int,
	vt:       int,
	vn:       int,
	raw_text: string,
}

PointFace :: struct {
	vi_1: VertexIndices,
}

LineFace :: struct {
	vi_1: VertexIndices,
	vi_2: VertexIndices,
}

TriangleFace :: struct {
	vi_1: VertexIndices,
	vi_2: VertexIndices,
	vi_3: VertexIndices,
}

QuadFace :: struct {
	vi_1: VertexIndices,
	vi_2: VertexIndices,
	vi_3: VertexIndices,
	vi_4: VertexIndices,
}

PolygonFace :: struct {
	vis: []VertexIndices,
}

Face :: union {
	PointFace,
	LineFace,
	TriangleFace,
	QuadFace,
	PolygonFace,
}

InstanceDataInfo :: struct {
	instance_data_ptr: ^[dynamic]InstanceRaw,
}

model_load_obj :: proc(
	model_path: string,
	state_ptr: ^State = nil,
	instance_data: [dynamic]InstanceRaw,
) {
	state: ^State

	if state_ptr == nil {
		state = get_state()
	} else {
		state = state_ptr
	}

	obj_text := #load("assets/cube.obj", string)
	// obj_text := load_file_as string(model_path)

	// load_bytes(
	// 	model_path,
	// 	proc(data: []u8, instance_data_ptr: rawptr) {
	// 		state: ^State

	// if state_ptr == nil {
	// state = get_state()
	// } else {
	// state = state_ptr
	// }
	// obj_text, _ := strings.clone_from_bytes(data)
	// instance_data: [dynamic]InstanceRaw = nil
	// instance_data_info := (cast(^InstanceDataInfo)instance_data_ptr)^
	// instance_data := instance_data_info.instance_data_ptr^
	line, ok := strings.split_lines_iterator(&obj_text)

	position_arr := [dynamic][3]f32{}
	texture_arr := [dynamic][2]f32{}
	normal_arr := [dynamic][3]f32{}
	face_arr := [dynamic]Face{}

	materials := [dynamic]Material{}
	mat_map := map[string]int{}
	mat_id := -1

	models := [dynamic]Model{}

	for ok {
		free_all(context.temp_allocator)
		parts := strings.split(line, " ", context.temp_allocator)
		if strings.has_prefix(line, "v ") {
			append(&position_arr, obj_parse_3_values(line))
		} else if strings.has_prefix(line, "vt ") {
			append(&texture_arr, obj_parse_2_values(line))
		} else if strings.has_prefix(line, "vn ") {
			append(&normal_arr, obj_parse_3_values(line))
		} else if strings.has_prefix(line, "f ") {

			faces_length := len(parts)

			if faces_length == 2 {
				append(&face_arr, PointFace{vi_1 = vertex_indices_parse(parts[1])})
			} else if faces_length == 3 {
				append(
					&face_arr,
					LineFace {
						vi_1 = vertex_indices_parse(parts[1]),
						vi_2 = vertex_indices_parse(parts[2]),
					},
				)
			} else if faces_length == 4 {
				append(
					&face_arr,
					TriangleFace {
						vi_1 = vertex_indices_parse(parts[1]),
						vi_2 = vertex_indices_parse(parts[2]),
						vi_3 = vertex_indices_parse(parts[3]),
					},
				)
			} else if faces_length == 5 {
				append(
					&face_arr,
					QuadFace {
						vi_1 = vertex_indices_parse(parts[1]),
						vi_2 = vertex_indices_parse(parts[2]),
						vi_3 = vertex_indices_parse(parts[3]),
						vi_4 = vertex_indices_parse(parts[4]),
					},
				)
			} else {
				face := PolygonFace{}
				f_arr := [dynamic]VertexIndices{}

				for part, i in parts {
					if i == 0 {
						continue
					}
					append(&f_arr, vertex_indices_parse(part))
				}
				face.vis = f_arr[:]
				delete(f_arr)
			}
		} else if strings.has_prefix(line, "o") == true || strings.has_prefix(line, "g") == true {
			if len(face_arr) > 0 {
				mesh := obj_export_faces(
					&position_arr,
					&position_arr,
					&texture_arr,
					&normal_arr,
					&face_arr,
					mat_id,
				)
				clear(&face_arr)
				model := Model{}
				append(&model.meshes, mesh)
				append(&models, model)
			}
		} else if strings.has_prefix(line, "mtllib ") == true {
			// matlib := parts[1]
			matlib := "cube.mtl"

			material_load("")
			// log.info(model_load_result)
			// mat_offset := len(materials)
			// for m in model_load_result.materials {
			// 	append(&materials, m)
			// }

			// for k, v in model_load_result.materials_map {
			// 	mat_map[k] = v + mat_offset
			// }
		} else if strings.has_prefix(line, "usemtl") == true {
			mat_name := parts[1]
			log.info(mat_map)
			if len(mat_name) > 0 {
				new_mat: int = mat_map[mat_name]
				// log.info(new_mat, mat_id)
				if mat_id != new_mat && len(face_arr) > 0 {

					mesh := obj_export_faces(
						&position_arr,
						&position_arr,
						&texture_arr,
						&normal_arr,
						&face_arr,
						mat_id,
					)
					clear(&face_arr)
					model := Model{}
					append(&model.meshes, mesh)
					append(&models, model)
				}

				mat_id = new_mat
			}
		}
		line, ok = strings.split_lines_iterator(&obj_text)
	}

	mesh := obj_export_faces(
		&position_arr,
		&position_arr,
		&texture_arr,
		&normal_arr,
		&face_arr,
		mat_id,
	)
	model := Model{}
	append(&model.meshes, mesh)
	append(&models, model)

	for &model in models {
		for &m, i in model.meshes {
			if instance_data != nil {
				m.instance_data = instance_data
			}
			mesh_initialize_buffers(state.device, m)
		}
		model.is_loaded = true
		model.materials = materials

		append(&state.models, model)
		// log.info(model)
	}

	delete(position_arr)
	delete(texture_arr)
	delete(normal_arr)
	delete(face_arr)
	// },
	// rawptr(instance_data_info),
	// )
}

model_load_obj_async :: proc(
	model_path: string,
	state_ptr: ^State = nil,
	// instance_data: [dynamic]InstanceRaw,
	instance_data_info_ptr: ^InstanceDataInfo,
) {
	state: ^State

	if state_ptr == nil {
		state = get_state()
	} else {
		state = state_ptr
	}

	// obj_text := #load("assets/cube.obj", string)
	// obj_text := load_file_as string(model_path)

	load_bytes(
		model_path,
		proc(data: []u8, instance_data_ptr: rawptr) {
			state: ^State


			// if state_ptr == nil {
			state = get_state()
			// } else {
			// state = state_ptr
			// }
			obj_text, _ := strings.clone_from_bytes(data)
			log.info("OBJ TEXT:", obj_text)
			log.info("DATA:", data)
			// instance_data: [dynamic]InstanceRaw = nil
			instance_data_info := (cast(^InstanceDataInfo)instance_data_ptr)^
			instance_data := instance_data_info.instance_data_ptr^
			line, ok := strings.split_lines_iterator(&obj_text)

			position_arr := [dynamic][3]f32{}
			texture_arr := [dynamic][2]f32{}
			normal_arr := [dynamic][3]f32{}
			face_arr := [dynamic]Face{}

			materials := [dynamic]Material{}
			mat_map := map[string]int{}
			mat_id := -1

			models := [dynamic]Model{}

			for ok {
				free_all(context.temp_allocator)
				parts := strings.split(line, " ", context.temp_allocator)
				if strings.has_prefix(line, "v ") {
					append(&position_arr, obj_parse_3_values(line))
				} else if strings.has_prefix(line, "vt ") {
					append(&texture_arr, obj_parse_2_values(line))
				} else if strings.has_prefix(line, "vn ") {
					append(&normal_arr, obj_parse_3_values(line))
				} else if strings.has_prefix(line, "f ") {

					faces_length := len(parts)

					if faces_length == 2 {
						append(&face_arr, PointFace{vi_1 = vertex_indices_parse(parts[1])})
					} else if faces_length == 3 {
						append(
							&face_arr,
							LineFace {
								vi_1 = vertex_indices_parse(parts[1]),
								vi_2 = vertex_indices_parse(parts[2]),
							},
						)
					} else if faces_length == 4 {
						append(
							&face_arr,
							TriangleFace {
								vi_1 = vertex_indices_parse(parts[1]),
								vi_2 = vertex_indices_parse(parts[2]),
								vi_3 = vertex_indices_parse(parts[3]),
							},
						)
					} else if faces_length == 5 {
						append(
							&face_arr,
							QuadFace {
								vi_1 = vertex_indices_parse(parts[1]),
								vi_2 = vertex_indices_parse(parts[2]),
								vi_3 = vertex_indices_parse(parts[3]),
								vi_4 = vertex_indices_parse(parts[4]),
							},
						)
					} else {
						face := PolygonFace{}
						f_arr := [dynamic]VertexIndices{}

						for part, i in parts {
							if i == 0 {
								continue
							}
							append(&f_arr, vertex_indices_parse(part))
						}
						face.vis = f_arr[:]
						delete(f_arr)
					}
				} else if strings.has_prefix(line, "o") == true ||
				   strings.has_prefix(line, "g") == true {
					if len(face_arr) > 0 {
						mesh := obj_export_faces(
							&position_arr,
							&position_arr,
							&texture_arr,
							&normal_arr,
							&face_arr,
							mat_id,
						)
						clear(&face_arr)
						model := Model{}
						append(&model.meshes, mesh)
						append(&models, model)
					}
				} else if strings.has_prefix(line, "mtllib ") == true {
					// matlib := parts[1]
					// matlib := "cube.mtl"

					// material_load("assets/cube.mtl")
					// mat_offset := len(materials)
					// for m in model_load_result.materials {
					// 	append(&materials, m)
					// }

					// for k, v in model_load_result.materials_map {
					// 	mat_map[k] = v + mat_offset
					// }
				} else if strings.has_prefix(line, "usemtl ") == true {
					// mat_name := parts[1]
					// log.info(mat_map)
					// if len(mat_name) > 0 {
					// 	new_mat: int = mat_map[mat_name]
					// 	// log.info(new_mat, mat_id)
					// 	if mat_id != new_mat && len(face_arr) > 0 {

					// 		mesh := obj_export_faces(
					// 			&position_arr,
					// 			&position_arr,
					// 			&texture_arr,
					// 			&normal_arr,
					// 			&face_arr,
					// 			mat_id,
					// 		)
					// 		clear(&face_arr)
					// 		model := Model{}
					// 		append(&model.meshes, mesh)
					// 		append(&models, model)
					// 	}

					// 	mat_id = new_mat
					// }
				}
				line, ok = strings.split_lines_iterator(&obj_text)
			}

			mesh := obj_export_faces(
				&position_arr,
				&position_arr,
				&texture_arr,
				&normal_arr,
				&face_arr,
				mat_id,
			)
			model := Model{}
			append(&model.meshes, mesh)
			append(&models, model)

			for &model in models {
				for &m, i in model.meshes {
					if instance_data != nil {
						m.instance_data = instance_data
					}
					mesh_initialize_buffers(state.device, m)
				}
				model.is_loaded = true
				model.materials = materials

				append(&state.models, model)
				// log.info(model)
			}

			delete(position_arr)
			delete(texture_arr)
			delete(normal_arr)
			delete(face_arr)
		},
		rawptr(instance_data_info_ptr),
	)
}

Material_Load_Result :: struct {
	materials:     [dynamic]Material,
	materials_map: map[string]int,
}

material_load :: proc(file_name: string) {
	// material_file := #load(file_name)
	// material_text := #load("assets/cube.mtl", string)
	load_bytes(
		file_name,
		proc(data: []u8, userdata: rawptr) {

			material_text, _ := strings.clone_from_bytes(data)
			log.info(material_text)
			fmt.println(material_text)
			materials := [dynamic]Material{}
			mat_map := map[string]int{}
			cur_mat := Material{}

			line, ok := strings.split_lines_iterator(&material_text)

			for ok {
				parts := strings.split(line, " ", context.temp_allocator)

				switch (parts[0]) {
				case "#":
					log.info(parts[1])
				case "newmtl":
					if cur_mat.name != "" {
						mat_map[cur_mat.name] = len(materials)
						append(&materials, cur_mat)
					}
					cur_mat = Material{}
					cur_mat.name = parts[1]
					assert(cur_mat.name != "", "Material: Invalid Object Name")
				case "Ka":
					cur_mat.ambient = obj_parse_3_values(line)
				case "Kd":
					cur_mat.diffuse = obj_parse_3_values(line)
				case "Ks":
					cur_mat.specular = obj_parse_3_values(line)
				case "Ke":
					cur_mat.emissive = obj_parse_3_values(line)
				case "Ns":
					cur_mat.shininess = obj_parse_value(line)
				case "Ni":
					cur_mat.optical_density = obj_parse_value(line)
				case "d":
					cur_mat.dissolve = obj_parse_value(line)
				case "map_Ka":
					cur_mat.ambient_texture_name = parts[1]
				case "map_Kd":
					cur_mat.diffuse_texture_name = parts[1]
				case "map_Ks":
					cur_mat.specular_texture_name = parts[1]
				case "map_Bump":
					cur_mat.normal_texture_name = parts[1]
				case "map_Ns":
					cur_mat.shininess_texture_name = parts[1]
				case "bump":
					cur_mat.normal_texture_name = parts[1]
				case "map_d":
					cur_mat.dissolve_texture_name = parts[1]
				case "illum":
					value, _ := strconv.parse_uint(parts[1], 10)
					cur_mat.illumination_model = u8(value)
				case:
					param, _ := strings.replace(line, parts[0], "", 1, context.temp_allocator)
					cur_mat.unknown_param[parts[0]] = param
				}

				free_all(context.temp_allocator)
				line, ok = strings.split_lines_iterator(&material_text)
			}

			if cur_mat.name != "" {
				mat_map[cur_mat.name] = len(materials)
				append(&materials, cur_mat)
			}


			delete(cur_mat.unknown_param)
			delete(materials)
			delete(mat_map)

			// return Material_Load_Result{materials = materials, materials_map = mat_map}
		},
	)
}

obj_export_faces :: proc(
	position_arr: ^[dynamic][3]f32, // vert: VertexIndices,
	color_arr: ^[dynamic][3]f32,
	texture_arr: ^[dynamic][2]f32,
	normal_arr: ^[dynamic][3]f32,
	face_arr: ^[dynamic]Face,
	material_id: int,
) -> ^Mesh {

	mesh := mesh_create()
	// mesh := Mesh{}
	mesh.material = material_id
	vertices_map := map[string]u16{}
	defer delete(vertices_map)
	// log.info(len(face_arr))
	for f, i in face_arr {
		switch fv in f {
		case PointFace:
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
		case LineFace:
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_2,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_2,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
		case TriangleFace:
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_2,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_3,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
		case QuadFace:
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_2,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_3,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)

			// ************************************

			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_1,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_3,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
			vertex_add(
				mesh,
				&vertices_map,
				fv.vi_4,
				position_arr,
				position_arr,
				texture_arr,
				normal_arr,
			)
		case PolygonFace:
			for v in fv.vis {
				vertex_add(
					mesh,
					&vertices_map,
					v,
					position_arr,
					position_arr,
					texture_arr,
					normal_arr,
				)
			}
		}
	}

	if len(mesh.indices) == 0 {
		append(&mesh.indices, 0)
	}

	// log.info(mesh)

	return mesh
}


obj_parse_3_values :: proc(value_str: string) -> [3]f32 {
	parts := strings.split(value_str, " ", context.temp_allocator)
	x, _ := strconv.parse_f32(parts[1])
	y, _ := strconv.parse_f32(parts[2])
	z, _ := strconv.parse_f32(parts[3])

	return [3]f32{x, y, z}
}

obj_parse_2_values :: proc(value_str: string) -> [2]f32 {
	parts := strings.split(value_str, " ", context.temp_allocator)
	x, _ := strconv.parse_f32(parts[1])
	y, _ := strconv.parse_f32(parts[2])

	return [2]f32{x, y}
}

obj_parse_value :: proc(value_str: string) -> f32 {
	parts := strings.split(value_str, " ", context.temp_allocator)
	x, _ := strconv.parse_f32(parts[1])

	return x
}


vertex_indices_parse :: proc(face_str: string) -> VertexIndices {
	parts := strings.split(face_str, "/", context.temp_allocator)
	v, _ := strconv.parse_int(parts[0])
	vt, _ := strconv.parse_int(parts[1])
	vn, _ := strconv.parse_int(parts[2])

	return VertexIndices{v = v - 1, vt = vt - 1, vn = vn - 1, raw_text = face_str}
}

vertex_add :: proc(
	mesh: ^Mesh,
	index_map: ^map[string]u16,
	vert: VertexIndices,
	pos: ^[dynamic][3]f32,
	v_color: ^[dynamic][3]f32,
	texcoord: ^[dynamic][2]f32,
	normal: ^[dynamic][3]f32,
) {
	if vert.raw_text in index_map {
		append(&mesh.indices, index_map[vert.raw_text])
		return
	}

	vertex := Vertex {
		position   = pos[vert.v],
		tex_coords = texcoord[vert.vt],
		normal     = normal[vert.vn],
		color      = v_color[vert.v],
	}

	next := cast(u16)len(index_map)
	append(&mesh.vertices, vertex)
	append(&mesh.indices, next)
	index_map[vert.raw_text] = next
}

