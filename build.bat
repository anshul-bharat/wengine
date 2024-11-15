REM NOTE: changing this requires changing the same values in the `web/index.html`.
set INITIAL_MEMORY_PAGES=2000
set MAX_MEMORY_PAGES=65536

set ODIN_DIR="D:\Programs\gitapps\Odin"

set PAGE_SIZE=65536
set /a INITIAL_MEMORY_BYTES=%INITIAL_MEMORY_PAGES% * %PAGE_SIZE%
set /a MAX_MEMORY_BYTES=%MAX_MEMORY_PAGES% * %PAGE_SIZE%

call odin.exe build . -target:js_wasm32 -out:web/wengine.wasm -o:size -extra-linker-flags:"--export-table --import-memory --initial-memory=%INITIAL_MEMORY_BYTES% --max-memory=%MAX_MEMORY_BYTES%"

copy "%ODIN_DIR%\vendor\wgpu\wgpu.js" "web\wgpu.js"
REM copy "%ODIN_DIR%\vendor\wasm\js\runtime.js" "web\runtime.js"
