package asset

import "core:os"
import "core:log"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import vmem "core:mem/virtual"


Glyph_Contour_Point :: struct {
    x, y: f32,
    on_curve: bool,
}

Glyph_Contour :: struct {
    points: []Glyph_Contour_Point,
}

Glyph_Composite_Record :: struct {
    transform: matrix[2, 2]f32,
    x, y:      f32,
    child_id:  int,
}

Glyph :: struct {
    id:                        i32,
    code:                      i32,
    min_x, max_x:              f32,
    min_y, max_y:              f32,
    advance:                   f32,
    left_side_bearing:         f32,
    composite:                 bool,
    contours:                  []Glyph_Contour,
    children:                  []Glyph_Composite_Record,
    n_positions:               int,
    positions_offset:          int,
    n_triangle_fan_indices:    int,
    triangle_fan_offset:       int,
    n_interior_bezier_indices: int,
    interior_bezier_offset:    int,
    n_exterior_bezier_indices: int,
    exterior_bezier_offset:    int,
    instances_offset:          int,
    instances:                 [dynamic]u32,
}

Font :: struct {
    name:                 string,
    space_advance:        f32,
    line_jump:            f32,
    min_x, max_x:         f32,
    min_y, max_y:         f32,
    units_per_em:         f32,
    glyphs:               []Glyph,
    code_to_index:        map[i32]i32,
    glyph_id_to_index:    map[i32]i32,
}

fonts_path :: "file/asset/font"

add_font :: proc(manager: ^Manager, name: string) {
    if name in manager.fonts {
        log.warn("Font `", name, "` already exists in asset manager. Skipping load.", sep="")
        return
    }

    font: Font
    ttf_file := fmt.tprintf("%s/%s.ttf", fonts_path, name)
    if os.exists(ttf_file) {
        data, ok := os.read_entire_file(ttf_file, context.allocator)
        defer delete(data)

        font = import_ttf(ttf_file, manager.language)
    }
    else {
        log.error("Font `", name, "` wasn't found. Skipping load.", sep="")
        return
    }

    for &glyph, index in font.glyphs {
        font.code_to_index[glyph.code] = i32(index)
        font.glyph_id_to_index[glyph.id] = i32(index)
    }

    manager.fonts[name] = font
}

release_font :: proc(manager: ^Manager, name: string) {
    if name not_in manager.fonts {
        log.error("Bad font release. Font", name, "doesn't exist.")
        return
    }
    font := &manager.fonts[name]
    delete(font.name)
    for glyph in font.glyphs {
        for contour in glyph.contours {
            delete(contour.points)
        }
        delete(glyph.contours)
    }
    delete(font.glyphs)
    delete(font.code_to_index)
    delete(font.glyph_id_to_index)
}

get_glyph :: proc(font: ^Font, code: i32) -> ^Glyph {
    index, ok := font.code_to_index[code]
    if !ok do index = 0
    return &font.glyphs[index]
}

FWORD :: distinct i16be
UFWORD :: distinct u16be
F2DOT14 :: distinct i16be

get_F2DOT14 :: proc(value: F2DOT14) -> f32 {
    return f32(value) / 16384.0
}

TTF_Header :: struct {
    SFNT_version:   u32be,
    num_tables:     u16be,
    search_range:   u16be,
    entry_selector: u16be,
    range_shift:    u16be,
}

TTF_Table_Record :: struct {
    tag:       [4]u8,
    check_sum: u32be,
    offset:    u32be,
    length:    u32be,
}

TTF_Head_Table :: struct #packed {
    version:             u32be,
    font_revision:       u32be,
    checksum_adjustment: u32be,
    magic_number:        u32be,
    flags:               u16be,
    units_per_em:        u16be,
    created, modified:   i64be,
    min_x, min_y:        i16be,
    max_x, max_y:        i16be,
    mac_style:           u16be,
    lowest_rect_ppem:    u16be,
    font_direction_hint: i16be,
    index_to_loc_format: i16be,
    glyph_data_format:   i16be,
}

TTF_MaxP_Table :: struct {
    version:    u32be,
    num_glyphs: u16be,
}

TTF_Long_Hor_Metric :: struct {
    advance_width:     UFWORD,
    left_side_bearing: FWORD,
}

TTF_Vertical_Metric :: struct {
    advance_height:   UFWORD,
    top_side_bearing: FWORD,
}

TTF_HHead_Table :: struct {
    major_version:          u16be,
    minor_version:          u16be,
    ascender, descender:    FWORD,
    line_gap:               FWORD,
    advance_width_max:      UFWORD,
    min_left_side_bearing:  FWORD,
    min_right_side_bearing: FWORD,
    x_max_extent:           FWORD,
    caret_slope_rise:       i16be,
    caret_slope_run:        i16be,
    caret_offset:           i16be,
    reserved:               [4]i16be,
    metric_data_format:     i16be,
    number_of_hmetrics:     u16be,
}

TTF_VHead_Table :: struct {
    major_version:           u16be,
    vert_typo_ascender:      FWORD,
    vert_typo_descender:     FWORD,
    vert_typo_line_gap:      FWORD,
    advance_height_max:      UFWORD,
    min_bottom:              FWORD,
    y_max_extent:            FWORD,
    caret_slope_rise:        i16be,
    caret_slope_run:         i16be,
    caret_offset:            i16be,
    reserved:                [4]i16be,
    metric_data_format:      i16be,
    num_of_long_ver_metrics: u16be,
}

TTF_FS_Selection_Flag :: enum u16 {
    Italic,
    Underscore,
    Negative,
    Outlined,
    Strike_Out,
    Bold,
    Regular,
    Use_Typo_Metrics,
    Weight_Width_Slope,
    Oblique,
}

TTF_FS_Selection_Flags :: bit_set[TTF_FS_Selection_Flag]

TTF_OS2_Table :: struct #packed {
    version:                u16be,
    x_avg_char_width:       FWORD,
    us_weight_class:        u16be,
    us_width_class:         u16be,
    fs_type:                u16be,
    y_subscript_x_size:     FWORD,
    y_subscript_y_size:     FWORD,
    y_subscript_x_offset:   FWORD,
    y_subscript_y_offset:   FWORD,
    y_superscript_x_size:   FWORD,
    y_superscript_y_size:   FWORD,
    y_superscript_x_offset: FWORD,
    y_superscript_y_offset: FWORD,
    y_strikeout_size:       FWORD,
    y_strikeout_position:   FWORD,
    sfamily_class:          i16be,
    panose:                 [10]u8,
    ul_unicoderange1:       u32be,
    ul_unicoderange2:       u32be,
    ul_unicoderange3:       u32be,
    ul_unicoderange4:       u32be,
    ach_vend_id:            u32be,
    fs_selection:           u16be,
    us_first_char_index:    u16be,
    us_last_char_index:     u16be,
    s_typo_ascender:        FWORD,
    s_typo_descender:       FWORD,
    s_typo_line_gap:        FWORD,
    us_win_ascent:          UFWORD,
    us_win_descent:         UFWORD,
};

TTF_CMap_Header :: struct {
    version:    u16be,
    num_tables: u16be,
}

TTF_Encoding_Record :: struct {
    platform_id: u16be,
    encoding_id: u16be,
    offset:      u32be,
}

TTF_CMap_Subtable :: struct {
    format:         u16be,
    length:         u16be,
    language:       u16be,
    seg_count_x2:   u16be,
    search_range:   u16be,
    entry_selector: u16be,
    range_shift:    u16be,
}

get_glyph_id :: proc(code: i32, start_codes: []u16be, end_codes: []u16be, id_range_offsets: [^]u16be, id_deltas: []i16be) -> i32 {
    assert(len(start_codes) == len(end_codes))
    
    code_range_index, start_code, end_code: i32
    for ;code_range_index < i32(len(start_codes)); code_range_index += 1 {
        start_code = i32(start_codes[code_range_index])
        end_code = i32(end_codes[code_range_index])
        if end_code == 0xffff && start_code == 0xffff {
            log.warn("Failed to find glyph ID for code", code)
            return 0
        }
        if start_code <= code && code <= end_code {
            break
        }
    }

    id_offset := i32(id_range_offsets[code_range_index]) / 2
    if id_offset == 0 {
        return code + i32(id_deltas[code_range_index])
    }
    else {
        glyph_id := i32(id_range_offsets[code_range_index + (code - start_code) + id_offset])
        if glyph_id == 0 {
            log.warn("Failed to find glyph ID for code", code)
            return 0
        }
        return glyph_id + i32(id_deltas[code_range_index])
    }
}

TTF_Glyph_Header :: struct {
    n_contours:   i16be,
    min_x, min_y: i16be,
    max_x, max_y: i16be,
}

TTF_Simple_Glyph_Flag :: enum u8 {
    On_Curve,
    X_Short_Vector,
    Y_Short_Vector,
    Repeat,
    X_Is_Same_Or_Positive_X_Short_Vector,
    Y_Is_Same_Or_Positive_Y_Short_Vector,
    Overlap_Simple,
}

TTF_Simple_Glyph_Flags :: bit_set[TTF_Simple_Glyph_Flag]

TTF_Composite_Glyph_Flag :: enum u16be {
    Arg_1_And_2_Are_Words,
    Args_Are_XY_Values,
    Round_XY_To_Grid,
    We_Have_A_Scale,
    More_Components,
    We_Have_An_X_And_Y_Scale,
    We_Have_A_Two_By_Two,
    We_Have_Instructions,
    Use_My_Metrics,
    Overlap_Compound,
    Scaled_Component_Offset,
    Unscaled_Component_Offset,
}

TTF_Composite_Glyph_Flags :: bit_set[TTF_Composite_Glyph_Flag]

get_ttf_coordinate :: proc(is_short: bool, repeat_or_positive: bool, last: i16, memory: []byte) -> (coord: i16, advance_bytes: int) {
    coord = last
    if is_short {
        delta := extract_from_memory(memory, u8)
        advance_bytes = 1
        if repeat_or_positive do coord += i16(delta)
        else do                  coord -= i16(delta)
    }
    else if !repeat_or_positive {
        coord += i16(extract_from_memory(memory, i16be))
        advance_bytes = 2
    }
    return
}

import_ttf :: proc(path: string, language: Language) -> (result: Font) {
    _, filename := os.split_path(path)
    font_name, _ := os.split_filename(filename)
    result.name = strings.clone(font_name)

    arena: vmem.Arena
    vmem_error := vmem.arena_init_growing(&arena)
    if vmem_error != nil do log.fatal("Failed to initialize memory arena for GLB asset", path)
    defer vmem.arena_destroy(&arena)
    allocator := vmem.arena_allocator(&arena)

    data, os_error := os.read_entire_file(path, allocator)
    if os_error != nil do log.fatal("Failed to read font file", path)
    header := extract_from_memory(data, TTF_Header)
    assert(header.SFNT_version == 0x00010000)
    block := data[size_of(TTF_Header):]

    head_table: TTF_Head_Table
    hhead_table: TTF_HHead_Table
    n_hmetrics: i32
    n_glyphs: u16
    location_table: [^]u32be
    glyph_table: []byte
    horizontal_metrics_table: [^]TTF_Long_Hor_Metric
    vertical_metrics_table: [^]TTF_Vertical_Metric
    seg_count: u16
    start_codes: []u16be
    end_codes: []u16be
    id_deltas: []i16be
    id_range_offsets: [^]u16be
    
    // Parse tables
    tables := (cast([^]TTF_Table_Record)raw_data(block))[:header.num_tables]
    for table in tables {
        switch table.tag {
            case { 'h', 'e', 'a', 'd' }:
                head_table = extract_from_memory(data[table.offset:], TTF_Head_Table)
                assert(head_table.version == 0x00010000 && head_table.magic_number == 0x5F0F3CF5)
                result.min_x, result.max_x = f32(head_table.min_x), f32(head_table.max_x)
                result.min_y, result.max_y = f32(head_table.min_y), f32(head_table.max_y)
                result.units_per_em = f32(head_table.units_per_em)
            case { 'm', 'a', 'x', 'p' }:
                maxp_table := extract_from_memory(data[table.offset:], TTF_MaxP_Table)
                n_glyphs = u16(maxp_table.num_glyphs)
            case { 'l', 'o', 'c', 'a' }:
                location_table = cast([^]u32be)raw_data(data[table.offset:])
            case { 'g', 'l', 'y', 'f' }:
                glyph_table = data[table.offset:]
            case { 'h', 'h', 'e', 'a' }:
                hhead_table = extract_from_memory(data[table.offset:], TTF_HHead_Table)
                n_hmetrics = i32(hhead_table.number_of_hmetrics)
            case { 'h', 'm', 't', 'x' }:
                horizontal_metrics_table = cast([^]TTF_Long_Hor_Metric)raw_data(data[table.offset:])
            case { 'v', 'm', 't', 'x' }:
                vertical_metrics_table = cast([^]TTF_Vertical_Metric)raw_data(data[table.offset:])
            case { 'O', 'S', '/', '2' }:
                os2_table := extract_from_memory(data[table.offset:], TTF_OS2_Table)
                fs_selection := transmute(TTF_FS_Selection_Flags)u16(os2_table.fs_selection)
                if .Use_Typo_Metrics in fs_selection {
                    result.line_jump = f32(os2_table.s_typo_ascender - os2_table.s_typo_descender + os2_table.s_typo_line_gap)
                }
            case { 'c', 'm', 'a', 'p' }:
                cmap_start := data[table.offset:]
                cmap_header := extract_from_memory(cmap_start, TTF_CMap_Header)
                encodings := (cast([^]TTF_Encoding_Record)raw_data(cmap_start[size_of(TTF_CMap_Header):]))[:cmap_header.num_tables]
                for encoding in encodings {
                    if encoding.platform_id == 3 && encoding.encoding_id == 1 {
                        subtable := extract_from_memory(cmap_start[encoding.offset:], TTF_CMap_Subtable)
                        assert(subtable.format == 4)
                        seg_count = u16(subtable.seg_count_x2 >> 1)

                        pointer := cmap_start[encoding.offset + size_of(TTF_CMap_Subtable):]
                        end_codes = (cast([^]u16be)raw_data(pointer))[:seg_count]
                        assert(end_codes[seg_count - 1] == 0xffff)
                        pointer = pointer[subtable.seg_count_x2:]

                        reserved_pad := extract_from_memory(pointer, u16be)
                        assert(reserved_pad == 0)
                        pointer = pointer[2:]

                        start_codes = (cast([^]u16be)raw_data(pointer))[:seg_count]
                        assert(start_codes[seg_count - 1] == 0xffff)
                        pointer = pointer[subtable.seg_count_x2:]

                        id_deltas = (cast([^]i16be)raw_data(pointer))[:seg_count]
                        pointer = pointer[subtable.seg_count_x2:]

                        id_range_offsets = (cast([^]u16be)raw_data(pointer))
                        pointer = pointer[subtable.seg_count_x2:]
                        
                        break
                    }
                }
        }
    }

    if result.line_jump == 0 {
        result.line_jump = f32(hhead_table.ascender - hhead_table.descender + hhead_table.line_gap)
    }
    
    other_left_side_bearings := cast([^]FWORD)horizontal_metrics_table[hhead_table.number_of_hmetrics:]

    // Collect glyph data location in memory
    glyph_offsets := make([]u32, n_glyphs + 1, allocator)
    switch head_table.index_to_loc_format {
        case 0:
            short_location_table := cast([^]u16be)location_table
            for i in 0..<n_glyphs {
                glyph_offsets[i] = u32(short_location_table[i]) << 1
            }
        case 1:
            for i in 0..<n_glyphs {
                glyph_offsets[i] = u32(location_table[i])
            }
        case:
            log.fatal("Invalid index to location format in TTF file", path)
    }

    // Space glyph
    space_glyph_id := get_glyph_id(0x20, start_codes, end_codes, id_range_offsets, id_deltas)
    result.space_advance = f32(horizontal_metrics_table[space_glyph_id].advance_width)

    // Parse glyphs
    glyph_ids := make([dynamic]i32, allocator)
    codes := make([dynamic]i32, allocator)
    append(&glyph_ids, 0)
    append(&codes, 0)
    result.code_to_index[0] = 0
    result.glyph_id_to_index[0] = 0
    
    language_ranges := unicode_range_flags[language]
    for range, name in unicode_ranges {
        if name in language_ranges {
            for code in range[0]..=range[1] {
                glyph_id := get_glyph_id(code, start_codes, end_codes, id_range_offsets, id_deltas)
                offset := glyph_offsets[glyph_id]
                glyph_size := glyph_offsets[glyph_id + 1] - offset
                if glyph_size == 0 {
                    log.warn("Glyph", glyph_id, "is empty for font", result.name)
                    continue
                }
                if glyph_id != 0 {
                    result.code_to_index[code] = i32(len(codes))
                    result.glyph_id_to_index[glyph_id] = i32(len(glyph_ids))
                    append(&glyph_ids, glyph_id)
                    append(&codes, code)
                }
            }
        }
    }

    result.glyphs = make([]Glyph, len(glyph_ids))
    for glyph_id, index in glyph_ids {
        glyph := &result.glyphs[index]
        glyph.id = glyph_id
        glyph.code = codes[index]
        offset := glyph_offsets[glyph_id]
        glyph_size := glyph_offsets[glyph_id + 1] - offset

        glyph_data := glyph_table[offset:]
        glyph_header := extract_from_memory(glyph_data, TTF_Glyph_Header)
        glyph_data = glyph_data[size_of(TTF_Glyph_Header):]

        // metrics
        if glyph_id < n_hmetrics {
            glyph.advance = f32(horizontal_metrics_table[glyph_id].advance_width)
            glyph.left_side_bearing = f32(horizontal_metrics_table[glyph_id].left_side_bearing)
        }
        else {
            glyph.advance = f32(horizontal_metrics_table[n_hmetrics-1].advance_width)
            glyph.left_side_bearing = f32(other_left_side_bearings[glyph_id - n_hmetrics])
        }
        glyph.min_x = f32(glyph_header.min_x)
        glyph.max_x = f32(glyph_header.max_x)
        glyph.min_y = f32(glyph_header.min_y)
        glyph.max_y = f32(glyph_header.max_y)

        if glyph_header.n_contours == 0 {
            log.warn("Glyph", glyph_id, "has zero contours for font", result.name)
            continue
        }

        // Simple glyphs
        if glyph_header.n_contours > 0 {
            glyph.contours = make([]Glyph_Contour, glyph_header.n_contours)
            end_pts_of_contours := (cast([^]u16be)raw_data(glyph_data))[:glyph_header.n_contours]
            glyph_data = glyph_data[2*glyph_header.n_contours:]

            // Instructions
            instruction_length := u16(extract_from_memory(glyph_data, u16be))
            glyph_data = glyph_data[2:]
            instructions := glyph_data[:instruction_length]
            glyph_data = glyph_data[instruction_length:]

            flag_bytes, x_bytes, y_bytes: int
            points_data := glyph_data
            flags_pointer := points_data
            point_index: int
            repeat_counter: u8
            // First pass to locate xs and ys
            for end_point, contour_index in end_pts_of_contours {
                previous_on_curve := false

                for ;point_index <= int(end_point); point_index += 1 {
                    current_flags := extract_from_memory(flags_pointer, TTF_Simple_Glyph_Flags)
                    
                    add_bytes: int
                    if .Repeat in current_flags {
                        if repeat_counter == 0 do repeat_counter = transmute(u8)flags_pointer[1]
                        else {
                            repeat_counter -= 1
                            if repeat_counter == 0 do add_bytes = 2
                        }
                    }
                    else do add_bytes = 1
                    flag_bytes += add_bytes
                    flags_pointer = flags_pointer[add_bytes:]
    
                    if      .X_Short_Vector in current_flags                           do x_bytes += 1
                    else if .X_Is_Same_Or_Positive_X_Short_Vector not_in current_flags do x_bytes += 2

                    if      .Y_Short_Vector in current_flags                           do y_bytes += 1
                    else if .Y_Is_Same_Or_Positive_Y_Short_Vector not_in current_flags do y_bytes += 2
                }
            }
            flags := slice.reinterpret([]TTF_Simple_Glyph_Flags, points_data[:flag_bytes])
            points_data = points_data[flag_bytes:]
            xs := points_data[:x_bytes]
            points_data = points_data[x_bytes:]
            ys := points_data[:y_bytes]
            
            point_index = 0
            last_x, last_y: i16
            repeat_counter = 0
            for end_point, contour_index in end_pts_of_contours {
                previous_on_curve := false
                contour := &glyph.contours[contour_index]
                
                points := make([dynamic]Glyph_Contour_Point, allocator)
                defer delete(points)
                for ;point_index <= int(end_point); point_index += 1 {
                    current_flags := flags[0]

                    on_curve := .On_Curve in current_flags
                    defer previous_on_curve = on_curve

                    x, advance_x := get_ttf_coordinate(
                        .X_Short_Vector in current_flags,
                        .X_Is_Same_Or_Positive_X_Short_Vector in current_flags,
                        last_x,
                        xs
                    )
                    xs = xs[advance_x:]
                    defer last_x = x

                    y, advance_y := get_ttf_coordinate(
                        .Y_Short_Vector in current_flags,
                        .Y_Is_Same_Or_Positive_Y_Short_Vector in current_flags,
                        last_y,
                        ys
                    )
                    ys = ys[advance_y:]
                    defer last_y = y

                    if !previous_on_curve && !on_curve {
                        point := Glyph_Contour_Point{
                            on_curve = true,
                            x = 0.5 * (f32(x) + f32(last_x)),
                            y = 0.5 * (f32(y) + f32(last_y)),
                        }
                        append(&points, point)
                    }

                    point := Glyph_Contour_Point{
                        on_curve = on_curve,
                        x = f32(x),
                        y = f32(y),
                    }
                    append(&points, point)

                    if .Repeat in current_flags {
                        if repeat_counter == 0 do repeat_counter = transmute(u8)flags[1]
                        else {
                            repeat_counter -= 1
                            if repeat_counter == 0 do flags = flags[2:]
                        }
                    }
                    else do flags = flags[1:]
                }

                contour.points = make([]Glyph_Contour_Point, len(points), context.allocator)
                copy(contour.points, points[:])
                glyph.n_positions += len(points)
            }

            continue
        }

        // Composite glyphs
        if glyph_header.n_contours < 0 {
            glyph.composite = true
            pointer := cast([^]u16be)raw_data(glyph_data)
            children := make([dynamic]Glyph_Composite_Record, allocator)
            for {
                translation: [2]f32
                transform: matrix[2, 2]f32
                flags := transmute(TTF_Composite_Glyph_Flags)pointer[0]
                child_glyph_id := u16(pointer[1])
                pointer = pointer[2:]
                
                if .Arg_1_And_2_Are_Words in flags {
                    if .Args_Are_XY_Values in flags {
                        xy_pointer := cast([^]i16be)pointer
                        translation.x = f32(xy_pointer[0])
                        translation.y = f32(xy_pointer[1])
                    }
                    else {
                        translation.x = f32(pointer[0])
                        translation.y = f32(pointer[1])
                    }

                    pointer = pointer[2:]
                }
                else {
                    if .Args_Are_XY_Values in flags {
                        xy_pointer := cast([^]i8)pointer
                        translation.x = f32(xy_pointer[0])
                        translation.y = f32(xy_pointer[1])
                    }
                    else {
                        xy_pointer := cast([^]u8)pointer
                        translation.x = f32(xy_pointer[0])
                        translation.y = f32(xy_pointer[1])
                    }
                    pointer = pointer[1:]
                }

                transform_pointer := cast([^]F2DOT14)pointer
                if .We_Have_A_Scale in flags {
                    transform[0, 0] = get_F2DOT14(transform_pointer[0])
                    transform[1, 1] = get_F2DOT14(transform_pointer[0])

                    pointer = pointer[1:]
                }
                else if .We_Have_An_X_And_Y_Scale in flags {
                    transform[0, 0] = get_F2DOT14(transform_pointer[0])
                    transform[1, 1] = get_F2DOT14(transform_pointer[1])

                    pointer = pointer[2:]
                }
                else if .We_Have_A_Two_By_Two in flags {
                    transform[0, 0] = get_F2DOT14(transform_pointer[0])
                    transform[1, 0] = get_F2DOT14(transform_pointer[1])
                    transform[0, 1] = get_F2DOT14(transform_pointer[2])
                    transform[1, 1] = get_F2DOT14(transform_pointer[3])

                    pointer = pointer[4:]
                }

                if .Args_Are_XY_Values in flags {
                    if .Scaled_Component_Offset in flags {
                        translation = transform * translation
                    }
                    if .Round_XY_To_Grid in flags {
                        translation.x = math.round(translation.x)
                        translation.y = math.round(translation.y)
                    }
                }
                else {
                    log.fatal("TTF path for point alignments is not implemented")
                }

                if .Use_My_Metrics in flags {
                    // Maybe not necessary? If set, use the AW and LSB of this component for the glyph
                }

                append(&children, Glyph_Composite_Record{
                    child_id = int(child_glyph_id),
                    transform = transform,
                    x = translation.x,
                    y = translation.y,
                })

                if .More_Components not_in flags do break
            }

            glyph.children = make([]Glyph_Composite_Record, len(children))
            copy(glyph.children, children[:])
        }
    }

    return
}

load_font_vertices :: proc(font: ^Font, positions: ^[dynamic]Vertex_Position, indices: ^[dynamic]u32) {
    for &glyph in font.glyphs {
        glyph.positions_offset = len(positions)

        glyph_positions := make([dynamic]Vertex_Position)
        defer delete(glyph_positions)
        defer append(positions, ..glyph_positions[:])

        glyph_triangle_fan_indices := make([dynamic]u32)
        defer delete(glyph_triangle_fan_indices)

        glyph_interior_bezier_indices := make([dynamic]u32)
        defer delete(glyph_interior_bezier_indices)

        glyph_exterior_bezier_indices := make([dynamic]u32)
        defer delete(glyph_exterior_bezier_indices)

        first_found: bool
        first_index: u32

        for contour in glyph.contours {
            if len(contour.points) <= 2 do continue

            triangle_fan_vertices := make([dynamic]u32)
            defer delete(triangle_fan_vertices)

            first_contour_point_index := len(glyph_positions)

            for point, point_index_in_contour in contour.points {
                point_index_in_glyph := first_contour_point_index + point_index_in_contour
                append(&glyph_positions, Vertex_Position{point.x, point.y, 0})
                if point.on_curve {
                    if !first_found {
                        first_index = u32(point_index_in_glyph)
                        first_found = true
                    }
                    append(&triangle_fan_vertices, u32(point_index_in_glyph))
                }
                else {
                    start_index := (point_index_in_contour + len(contour.points) - 1) % len(contour.points)
                    start := contour.points[start_index]
                    end_index := (point_index_in_contour + 1) % len(contour.points)
                    end := contour.points[end_index]
                    area := get_area({{start.x, start.y}, {point.x, point.y}, {end.x, end.y}})
                    if area > 0 {
                        append(&triangle_fan_vertices, u32(point_index_in_glyph))
                        append(&glyph_interior_bezier_indices, u32(first_contour_point_index + start_index))
                        append(&glyph_interior_bezier_indices, u32(point_index_in_glyph))
                        append(&glyph_interior_bezier_indices, u32(first_contour_point_index + end_index))
                    }
                    else if area < 0 {
                        append(&glyph_exterior_bezier_indices, u32(first_contour_point_index + start_index))
                        append(&glyph_exterior_bezier_indices, u32(point_index_in_glyph))
                        append(&glyph_exterior_bezier_indices, u32(first_contour_point_index + end_index))
                    }
                }
            }
            
            for point, index in triangle_fan_vertices {
                next := triangle_fan_vertices[(index + 1) % len(triangle_fan_vertices)]
                append(&glyph_triangle_fan_indices, first_index)
                append(&glyph_triangle_fan_indices, point)
                append(&glyph_triangle_fan_indices, next)
            }
        }

        glyph.n_triangle_fan_indices = len(glyph_triangle_fan_indices)
        glyph.triangle_fan_offset = len(indices)
        append(indices, ..glyph_triangle_fan_indices[:])

        glyph.n_interior_bezier_indices = len(glyph_interior_bezier_indices)
        glyph.interior_bezier_offset = len(indices)
        append(indices, ..glyph_interior_bezier_indices[:])

        glyph.n_exterior_bezier_indices = len(glyph_exterior_bezier_indices)
        glyph.exterior_bezier_offset = len(indices)
        append(indices, ..glyph_exterior_bezier_indices[:])
    }
}

DPI :: 96.0

get_text_width :: proc(font: ^Font, text: string, points: f32) -> (result: f32) {
    size := points * (DPI / 72.0) / font.units_per_em

    line_width: f32
    for char in text {
        if char == ' ' {
            line_width += size * font.space_advance
            continue
        }

        if char == '\n' {
            if line_width > result do result = line_width
            line_width = 0
            continue
        }

        line_width += size * get_glyph(font, i32(char)).advance
    }

    if line_width > result do result = line_width
    return
}

get_text_rect :: proc(font: ^Font, text: string, pen_x: f32, pen_y: f32, points: f32) -> (result: Rect) {
    size := points * (DPI / 72.0) / font.units_per_em

    result.left = pen_x
    result.top = max(f32)

    line_width: f32
    nth_line: int
    line_min_y: f32
    for char in text {
        if char == ' ' {
            line_width += size * font.space_advance
            continue
        }

        if char == '\n' {
            if line_width > result.width do result.width = line_width
            line_width = 0
            line_min_y = 0
            nth_line += 1

            continue
        }

        glyph := get_glyph(font, i32(char))
        line_width += size * glyph.advance
        line_min_y = min(line_min_y, size * glyph.min_y)
        
        if nth_line == 0 {
            result.top = min(result.top, pen_y - size * glyph.max_y)
        }
    }

    if line_width > result.width do result.width = line_width

    result.height = pen_y + size * (f32(nth_line) * font.line_jump - line_min_y) - result.top

    return
}