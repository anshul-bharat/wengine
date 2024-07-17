package wengine

import "core:log"

import "vendor:wasm/js"
import "vendor:wgpu"

OS :: struct {
	initialized: bool,
}

@(private = "file")
g_os: ^OS

os_init :: proc(os: ^OS) {
	g_os = os
	assert(js.add_window_event_listener(.Resize, nil, size_callback))
	assert(js.add_window_event_listener(.Key_Down, nil, key_down_callback))
	assert(js.add_window_event_listener(.Key_Up, nil, key_up_callback))
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

