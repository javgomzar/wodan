package common


Time_Record_ID :: enum {
    Rendering,
}

Time_Record :: struct {
    file:      string,
    procedure: string,
    line:      i32,
    count:     i32,
    time_ms:   f32,
}

Timer :: struct {
    record: ^Time_Record,
    start:  u64,
}

@(private="file")
time_records : ^[Time_Record_ID]Time_Record

set_up_timing :: proc(memory_time_records: ^[Time_Record_ID]Time_Record) {
    when ODIN_OS == .Windows {
        query_performance_frequency()
    }

    time_records = memory_time_records
}

start_timer :: proc(id: Time_Record_ID, location := #caller_location) -> Timer {
    record := &time_records[id]

    if record.count == 0 {
        record.file = location.file_path
        record.line = location.line
        record.procedure = location.procedure
    }
    record.count += 1
    
    return {
        record = record,
        start = get_wall_clock(),
    }
}

end_timer :: proc(timer: Timer) {
    end := get_wall_clock()
    timer.record.time_ms += 1000.0 * get_seconds_elapsed(timer.start, end)
}

clear_time_records :: proc() {
    for &record, id in time_records {
        record.time_ms = 0
        record.count = 0
    }
}
