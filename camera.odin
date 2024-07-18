package wengine

import "core:log"
import "core:math/linalg"
// import "core:runtime"

Camera :: struct {
	eye:    [3]f32,
	target: [3]f32,
	up:     [3]f32,
	aspect: f32,
	fovy:   f32,
	znear:  f32,
	zfar:   f32,
}

CameraUniform :: struct {
	view_proj: matrix[4, 4]f32,
}

camera_build_view_projection_matrix :: proc(camera: ^Camera) -> CameraUniform {
	view := linalg.matrix4_look_at(camera.eye, camera.target, camera.up)
	proj := linalg.matrix4_perspective(
		linalg.to_degrees(camera.fovy),
		camera.aspect,
		camera.znear,
		camera.zfar,
	)

	return CameraUniform{view_proj = OPENGL_TO_WGPU_MATRIX * proj * view}
}

CameraController :: struct {
	speed:               f32,
	is_forward_pressed:  bool,
	is_backward_pressed: bool,
	is_left_pressed:     bool,
	is_right_pressed:    bool,
}

camera_controller_process_events :: proc(
	camera_controller: ^CameraController,
	event: KeyEvent,
) -> bool {

	context.logger = log.create_console_logger()

	pressed := event.key_action == KeyAction.PRESS || event.key_action == KeyAction.REPEAT


	#partial switch event.key_code {
	case KeyCode.ARROW_UP:
		camera_controller^.is_forward_pressed = pressed
		return true
	case KeyCode.ARROW_DOWN:
		camera_controller^.is_backward_pressed = pressed
		return true
	case KeyCode.ARROW_LEFT:
		camera_controller^.is_left_pressed = pressed
		return true
	case KeyCode.ARROW_RIGHT:
		camera_controller^.is_right_pressed = pressed
		return true
	}
	return false
}

camera_controller_update_camera :: proc(camera_controller: ^CameraController, camera: ^Camera) {
	context.logger = log.create_console_logger()

	forward := camera^.target - camera^.eye
	forward_norm := linalg.normalize(forward)
	forward_mag := linalg.length(forward)

	if camera_controller^.is_forward_pressed && forward_mag > camera_controller^.speed {
		camera^.eye += forward_norm * camera_controller^.speed
		// log.info(camera^.eye, camera_controller^)
	}
	if camera_controller^.is_backward_pressed {
		camera^.eye -= forward_norm * camera_controller^.speed
		// log.info(camera^.eye, camera_controller^)
	}

	right := linalg.cross(forward_norm, camera^.up)

	forward = camera^.target - camera^.eye
	forward_mag = linalg.length(forward)

	if camera_controller^.is_right_pressed {
		camera^.eye =
			camera^.target -
			linalg.normalize(forward + (right * camera_controller^.speed)) * forward_mag
	}
	if camera_controller^.is_left_pressed {
		camera^.eye =
			camera^.target -
			linalg.normalize(forward - (right * camera_controller^.speed)) * forward_mag
	}

}

