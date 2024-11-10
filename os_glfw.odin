//+build !js
package wengine

import "core:log"
import o_os "core:os"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

OS :: struct {
	window: glfw.WindowHandle,
}

os_init :: proc(os: ^OS) {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	os.window = glfw.CreateWindow(960, 540, "WGPU Native Triangle", nil, nil)

	glfw.SetFramebufferSizeCallback(os.window, size_callback)
	glfw.SetKeyCallback(os.window, key_callback)
}

os_run :: proc(os: ^OS) {
	dt: f32

	for !glfw.WindowShouldClose(os.window) {
		start := time.tick_now()

		glfw.PollEvents()
		frame(dt)

		dt = f32(time.duration_seconds(time.tick_since(start)))
	}

	finish()

	glfw.DestroyWindow(os.window)
	glfw.Terminate()
}

os_get_render_bounds :: proc(os: ^OS) -> (width, height: u32) {
	iw, ih := glfw.GetWindowSize(os.window)
	return u32(iw), u32(ih)
}

os_get_surface :: proc(os: ^OS, instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, os.window)
}

@(private = "file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	resize()
}

@(private = "file")
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	key_event: KeyEvent

	if action == glfw.PRESS {
		key_event.key_action = KeyAction.PRESS
	}
	if action == glfw.RELEASE {
		key_event.key_action = KeyAction.RELEASE
	}
	if action == glfw.REPEAT {
		key_event.key_action = KeyAction.REPEAT
	}

	key_event.key_code = get_key_code(key)

	process_key_event(key_event)
}


get_key_code :: proc "c" (key: i32) -> KeyCode {

	if key == glfw.KEY_DOWN {
		return KeyCode.ARROW_DOWN
	}
	if key == glfw.KEY_UP {
		return KeyCode.ARROW_UP
	}
	if key == glfw.KEY_LEFT {
		return KeyCode.ARROW_LEFT
	}
	if key == glfw.KEY_RIGHT {
		return KeyCode.ARROW_RIGHT
	}

	if key == glfw.KEY_ESCAPE {
		return KeyCode.ESCAPE
	}

	return KeyCode.UNKNOWN
}

load_bytes :: proc(
	filepath: string,
	callback: proc(_: []u8, _: rawptr = nil),
	userdata: rawptr = nil,
) {
	data, success := o_os.read_entire_file(filepath)
	// log.info("in load_bytes", data, success)
	callback(data, userdata)
}

