package wengine

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

