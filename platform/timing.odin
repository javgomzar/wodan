package main

import "core:fmt"

time_record :: struct {
    start: u64,
    end: u64,
    file: string,
    procedure: string,
    line: i32,
}

time_records : [dynamic; 32]time_record

start_timer :: proc(location := #caller_location) {
    append(&time_records, time_record{
        start = get_wall_clock(),
        end = 0,
        file = location.file_path,
        line = location.line,
        procedure = location.procedure,
    })
}

end_timer :: proc() {
    time_records[len(time_records)-1].end = get_wall_clock()
}

print_timers :: proc() {
    for record in time_records {
        ms := 1000.0 * get_seconds_elapsed(record.start, record.end)
        fmt.printf("%.2f ms - `%s` at %s:%d\n", ms, record.procedure, record.file, record.line)
    }
}