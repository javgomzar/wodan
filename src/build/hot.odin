package build

import "core:os"
import "core:fmt"


main :: proc() {
    path: string
    exists: bool = true
    i: i32 = 0
    for exists {
        path = fmt.tprintf("bin/game%d.pdb", i)
        exists = os.exists(path)
        i += 1
    }

    pdb_name := fmt.tprintf("-pdb-name:%s", path)
    process, error := os.process_start({
        command = {"odin", "build", "src/game", "-out:bin/game.dll", "-debug", "-build-mode:dll", pdb_name}
    })

    end_state, _ := os.process_wait(process)
    os.exit(end_state.exit_code)
}