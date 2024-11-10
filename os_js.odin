package wengine

import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:mem"
import "core:net"
import os_lib "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "vendor:wasm/js"
import "vendor:wgpu"

foreign import "env"

load_bytes :: proc(
	path: string,
	callback: proc "odin" (_: []u8, _: rawptr),
	userdata: rawptr = nil,
) {

	@(default_calling_convention = "contextless")
	foreign env {
		@(link_name = "load_bytes")
		_load_bytes :: proc(path: string, callback: proc "odin" (_: []u8, _: rawptr), userdata: rawptr) ---
	}

	_load_bytes(path, callback, userdata)
}

@(export, link_name = "odin_do_load_callback")
do_load_callback :: proc(
	data_ptr: rawptr,
	data_len: u32,
	callback: proc(_: []u8, _: rawptr),
	userdata: rawptr = nil,
) {
	if callback != nil {
		rawdata := slice.bytes_from_ptr(data_ptr, int(data_len))
		callback(rawdata, userdata)
	}
}

OS :: struct {
	initialized: bool,
}

@(private = "file")
g_os: ^OS

Temp :: struct {
	size: int,
}

g_temp := Temp {
	size = 0,
}

os_init :: proc(os: ^OS) {
	g_os = os
	assert(js.add_window_event_listener(.Resize, nil, size_callback))
	assert(js.add_window_event_listener(.Key_Down, nil, key_down_callback))
	assert(js.add_window_event_listener(.Key_Up, nil, key_up_callback))

	g_temp.size = 100

	// load_bytes("assets/happy-tree.jpg", proc(data: []u8, userdata: rawptr) {
	// 		t := cast(^Temp)userdata
	// 		fmt.println(t.size)
	// 		t^.size = 200
	// 	}, rawptr(&g_temp))

	// load_bytes("assets/cube.obj", proc(data: []u8, userdata: rawptr) {
	// 		text := strings.clone_from_bytes(data)
	// 		fmt.println(text)
	// 	}, nil)

}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
os_run :: proc(os: ^OS) {
	os.initialized = true
}

os_get_render_bounds :: proc(os: ^OS) -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	return u32(rect.width), u32(rect.height)
}

os_get_surface :: proc(os: ^OS, instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceDescriptorFromCanvasHTMLSelector {
				sType = .SurfaceDescriptorFromCanvasHTMLSelector,
				selector = "#wgpu-canvas",
			},
		},
	)
}

@(private = "file", export)
step :: proc(dt: f32) -> bool {
	if !g_os.initialized {
		return true
	}
	frame(dt)
	return true
}

@(private = "file", fini)
os_fini :: proc() {
	js.remove_window_event_listener(.Resize, nil, size_callback)

	finish()
}

@(private = "file")
size_callback :: proc(e: js.Event) {
	resize()
}

@(private = "file")
key_down_callback :: proc(e: js.Event) {
	action := KeyAction.PRESS
	if e.key.repeat {
		action = KeyAction.REPEAT
	}

	process_key_event(KeyEvent{key_code = get_key_code(e.key.key), key_action = action})
}

@(private = "file")
key_up_callback :: proc(e: js.Event) {
	process_key_event(KeyEvent{key_code = get_key_code(e.key.key), key_action = KeyAction.RELEASE})
}

get_key_code :: proc(key: string) -> KeyCode {
	if key == "ArrowDown" {
		return KeyCode.ARROW_DOWN
	}
	if key == "ArrowLeft" {
		return KeyCode.ARROW_LEFT
	}
	if key == "ArrowRight" {
		return KeyCode.ARROW_RIGHT
	}
	if key == "ArrowUp" {
		return KeyCode.ARROW_UP
	}

	return KeyCode.UNKNOWN
}

