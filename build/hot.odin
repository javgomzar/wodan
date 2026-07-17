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
        command = {"odin", "build", "game", "-out:bin/game.dll", "-debug", "-build-mode:dll", pdb_name}
    })

    _, _ = os.process_wait(process)
    return
}