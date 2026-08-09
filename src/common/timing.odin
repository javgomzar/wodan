package common

import "core:log"

time_record :: struct {
    start: u64,
    end: u64,
    file: string,
    procedure: string,
    line: i32,
}

time_records : [dynamic; 32]time_record

set_up_timing :: proc() {
    when ODIN_OS == .Windows {
        query_performance_frequency()
    }
}

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
        seconds_elapsed := get_seconds_elapsed(record.start, record.end)
        ms := 1000.0 * seconds_elapsed
        log.debug("`", record.procedure, "` at ", record.file,":", record.line, " took ", ms, " ms to complete\n", sep="")
    }
}