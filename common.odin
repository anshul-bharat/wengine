package wengine

import "core:fmt"
import "core:mem"
import "core:os"

KeyCode :: enum u8 {
	UNKNOWN,

	/* ARROW KEYS */
	ARROW_UP,
	ARROW_DOWN,
	ARROW_LEFT,
	ARROW_RIGHT,

	/* UTILITY KEYS */
	ESCAPE,
}

KeyAction :: enum u8 {
	PRESS,
	REPEAT,
	RELEASE,
}

KeyEvent :: struct {
	key_code:   KeyCode,
	key_action: KeyAction,
}

track: mem.Tracking_Allocator
print_memory_errors :: proc() {
	fmt.println("App Exited")
	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	if len(track.bad_free_array) > 0 {
		fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
		for entry in track.bad_free_array {
			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}

main :: proc() {
	fmt.println("App stated")
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			print_memory_errors()
		}
	}
	_main()
}

exit :: proc(code: int) {
	finish()
	print_memory_errors()
	os.exit(code)
}

