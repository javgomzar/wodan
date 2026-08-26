package common

import "core:fmt"
import "core:log"
import "core:container/pool"
import "base:runtime"
import "core:reflect"
import "../asset"


UI_Alignment :: enum {
    Free,
    Min,
    Center,
    Max,
}

UI_Size_Type :: enum {
    Zero,
    Pixels,
    Text,
    Max_Children,
    Sum_Children,
    Fraction_Parent,
}

UI_Size :: struct {
    type: UI_Size_Type,
    value: f32,
}

UI_Flag :: enum {
    Drag,
    Draw_Rect,
    Draw_Text,
}

UI_Flags :: bit_set[UI_Flag]

UI_Element :: struct {
    name:       string,
    flags:      UI_Flags,
    sizes:      [2]UI_Size,
    alignments: [2]UI_Alignment,
    last_frame: u64,

    relative_position: [2]f32,
    position:          [2]f32,
    
    parent:      ^UI_Element,
    first_child: ^UI_Element,
    brother:     ^UI_Element,
    previous:    ^UI_Element,
    next:        ^UI_Element,
    link:        ^UI_Element,
    
    text:      string,
    font:      ^asset.Font,
    points:    f32,
    
    pad:         [2]f32,
    min_value:   f32,
    value:       f32,
    max_value:   f32,
    t:           f32,
    color:       [4]f32,
    drag_offset: [2]f32,

    active:  bool,
    hovered: bool,
    clicked: bool,
    dragged: bool,
}

UI_Context :: struct {
    frame:   u64,
    input:   ^Input_Context,
    catalog: asset.Catalog,
    pool:    pool.Pool(UI_Element),
    
    root:    ^UI_Element,
    last:    ^UI_Element,

    elements: map[string]^UI_Element,
}

@(private="file")
ui_context: UI_Context

initialize_ui_context :: proc(memory: ^Game_Memory) {
    error := pool.init(&ui_context.pool, "link")
    if error != nil do log.fatal("Failed to initialize UI element pool")

    ui_context.input = &memory.input
    ui_context.catalog = memory.asset_manager.catalog
}

create_ui_element :: proc(
    name:       string,
    sizes:      [2]UI_Size,
    children:   ..^UI_Element,
    alignments: [2]UI_Alignment = {.Center, .Center},
    pad:        [2]f32 = {10, 10},
    text:       string = "",
    font:       ^asset.Font = ui_context.catalog.debug_font,
    points:     f32 = 16.0,
    color:      [4]f32 = {1, 1, 1, 1},
    flags:      UI_Flags = {},
) -> ^UI_Element {
    element, ok := ui_context.elements[name]
    if !ok {
        element = pool.get(&ui_context.pool)
        ui_context.elements[name] = element
    }
    element.name = name
    element.last_frame = ui_context.frame
    element.sizes = sizes
    element.alignments = alignments
    element.pad = pad
    element.parent = ui_context.root
    element.color = color
    element.flags = flags
    element.previous = ui_context.last
    if ui_context.last != nil do ui_context.last.next = element
    ui_context.last = element

    if len(text) > 0 {
        element.font = font
        element.text = text
        element.points = points

        if sizes.x.type == .Text || sizes.y.type == .Text {
            text_rect := asset.get_text_rect(font, text, 0, 0, points)

            if sizes.x.type == .Text {
                element.sizes.x.value = text_rect.width
            }

            if sizes.y.type == .Text {
                element.sizes.y.value = text_rect.height
            }
        }
    }

    if len(children) > 0 {
        element.first_child = children[0]
        dependent_children: bool

        previous_child: ^UI_Element
        for child in children {
            child.parent = element
            if previous_child != nil do previous_child.brother = child
            previous_child = child

            for &size, axis in element.sizes {
                child_size := child.sizes[axis]
                if child_size.type == .Fraction_Parent do dependent_children = true
                else if size.type == .Max_Children {
                    size.value = max(size.value, child_size.value + 2*pad[axis])
                }
                else if size.type == .Sum_Children {
                    size.value += pad[axis]
                    child.relative_position[axis] = size.value
                    size.value += child_size.value
                }
            }
        }

        for &size, axis in element.sizes {
            if size.type == .Sum_Children {
                size.value += pad[axis]
            }
        }

        if dependent_children {
            for child in children {
                for size, axis in element.sizes {
                    child_size := child.sizes[axis]
                    if child_size.type == .Fraction_Parent {
                        child.sizes[axis].value *= size.value
                    }
                }
            }
        }
    }

    if ok {
        input := ui_context.input
        element.hovered = cursor_is_in_rect(
            input.mouse.cursor,
            element.position.x, element.position.y,
            element.sizes.x.value, element.sizes.y.value,
        )

        if element.clicked && input.mouse.left_click.is_down {
            element.dragged = true
            element.drag_offset = element.relative_position - input.mouse.last_cursor
        }
        if element.dragged {
            if input.mouse.left_click.is_down {
                if .Drag in flags {
                    element.relative_position = input.mouse.cursor + element.drag_offset
                }
            }
            else {
                element.dragged = false
            }
        }
        element.clicked = element.hovered && ui_context.input.mouse.left_click.just_pressed
    }

    return element
}

UI_Text :: proc(
    name: string,
    text: string,
    fmt_vars: ..any,
    alignments: [2]UI_Alignment = {.Center, .Center},
    font: ^asset.Font = ui_context.catalog.debug_font,
    points: f32 = 16.0, 
    color: [4]f32 = {1, 1, 1, 1},
    flags: UI_Flags = {.Draw_Text},
) -> ^UI_Element
{
    element := create_ui_element(
        name, 
        {{.Text, 0}, {.Text, 0}},
        alignments = alignments,
        font = font,
        text = fmt.tprintf(text, ..fmt_vars),
        points = points,
        color = color,
        flags = flags,
    )
    return element
}

UI_Row :: proc(
    name: string,
    elements: ..^UI_Element,
    pad: [2]f32 = {10, 10},
    alignments: [2]UI_Alignment = {.Center, .Center},
    flags: UI_Flags = {.Draw_Rect},
) -> ^UI_Element {
    element := create_ui_element(
        name, 
        {{.Sum_Children, 0}, {.Max_Children, 0}},
        pad = pad,
        alignments = alignments,
        children = elements,
        color = {0.2, 0.2, 0.2, 0.5},
        flags = flags,
    )
    return element
}

UI_Column :: proc(
    name: string,
    elements: ..^UI_Element,
    pad: [2]f32 = {10, 10},
    alignments: [2]UI_Alignment = {.Center, .Center},
    flags: UI_Flags = {.Draw_Rect},
) -> ^UI_Element {
    element := create_ui_element(
        name, 
        {{.Max_Children, 0}, {.Sum_Children, 0}},
        pad = pad,
        alignments = alignments,
        children = elements,
        color = {0.2, 0.2, 0.2, 0.5},
        flags = flags,
    )
    return element
}

UI_Table :: proc {
    UI_Table_enumerated_array,
    UI_Table_elements,
}

UI_Table_elements :: proc(
    name: string,
    rows: int,
    cols: int,
    elements: ..^UI_Element,
    alignments: [2]UI_Alignment = {.Center, .Center},
    pad: [2]f32 = {10, 10},
    flags: UI_Flags = {.Draw_Rect}
) -> ^UI_Element {
    assert(len(elements) == rows * cols)

    col_widths := make([]f32, cols, context.temp_allocator)
    row_heights := make([]f32, rows, context.temp_allocator)
    for i in 0..<rows {
        for j in 0..<cols {
            element := elements[cols*i + j]
            col_widths[j] = max(col_widths[j], element.sizes.x.value)
            row_heights[i] = max(row_heights[i], element.sizes.y.value)
        }
    }

    table_width, table_height := pad.x, pad.y
    pointer := pad
    for i in 0..<rows {
        for j in 0..<cols {
            element := elements[cols*i + j]
            for &alignment, axis in element.alignments {
                advance := axis == 0 ? col_widths[j] : row_heights[i]
                #partial switch alignment {
                    case .Min:
                        element.relative_position[axis] = pointer[axis]
                    case .Center:
                        element.relative_position[axis] = pointer[axis] + 0.5 * (advance - element.sizes[axis].value)
                    case .Max:
                        element.relative_position[axis] = pointer[axis] + advance - element.sizes[axis].value
                }
                alignment = .Free
            }
            pointer.x += col_widths[j] + pad.x
            if i == 0 do table_width += col_widths[j] + pad.x
        }
        table_height += row_heights[i] + pad.y
        pointer.x = pad.x
        pointer.y += row_heights[i] + pad.y
    }

    table := create_ui_element(
        name,
        {{.Pixels, table_width}, {.Pixels, table_height}},
        ..elements,
        alignments = alignments,
        pad = pad,
        color = {0.2, 0.2, 0.2, 0.5},
        flags = flags,
    )

    return table
}

UI_Table_enumerated_array :: proc(
    name: string,
    elements: $T/[$U]$V,
    alignments: [2]UI_Alignment = {.Center, .Center},
    pad: [2]f32 = {10, 10},
    flags: UI_Flags = {.Draw_Rect}
) -> ^UI_Element {
    V_typeid := reflect.typeid_elem(typeid_of(type_of(elements))) // Issue https://github.com/odin-lang/Odin/issues/7464, typeid(V) should work
    fields := reflect.struct_fields_zipped(V_typeid)

    cols := len(fields) + 1
    rows := len(U) + 1
    ui_elements := make([]^UI_Element, rows * cols, context.temp_allocator)
    col_header := fmt.tprintf("%s.id.header", name)
    ui_elements[0] = UI_Text(col_header, "id")
    for id, id_index in U {
        id_col_name := fmt.tprintf("%s.id.%v", name, id)
        ui_elements[(id_index + 1)*cols] = UI_Text(id_col_name, "%v", id, alignments = {.Min, .Center})
    }
    for field, field_index in fields {
        col_header = fmt.tprintf("%s.%s.header", name, field.name)
        ui_elements[field_index + 1] = UI_Text(col_header, field.name)
        
        for id, id_index in U {
            format := "%v"
            if float, ok := field.type.variant.(runtime.Type_Info_Float); ok {
                format = "%.3f"
            }
            col_value := reflect.struct_field_value(elements[id], field)
            id_col_name := fmt.tprintf("%s.%s.%d", name, field.name, id_index)
            ui_elements[(id_index + 1)*cols + field_index + 1] = UI_Text(id_col_name, format, col_value, alignments = {.Min, .Center})
        }
    }
    
    table := UI_Table_elements(name, rows, cols, ..ui_elements, alignments = alignments, pad = pad, flags = flags)

    return table
}

compute_layout :: proc() {
    element := ui_context.root.next
    for element != nil {
        for alignment, axis in element.alignments {
            if element.parent.sizes[axis].type != .Sum_Children && alignment != .Free {
                #partial switch alignment {
                    case .Min:
                        element.relative_position[axis] = element.parent.pad[axis]
                    case .Max:
                        element.relative_position[axis] = element.parent.sizes[axis].value - element.sizes[axis].value - element.parent.pad[axis]
                    case .Center:
                        element.relative_position[axis] = 0.5 * (element.parent.sizes[axis].value - element.sizes[axis].value)
                }
            }
        }

        element = element.next
    }
}

update_ui :: proc(memory: ^Game_Memory) {
    render_group := &memory.render_group
    ui_context.frame = memory.renderer.frame

    ui_context.root = create_ui_element("root", {{.Pixels, f32(render_group.width)}, {.Pixels, f32(render_group.height)}})

    if ui_context.input.keyboard.key[.F1].just_pressed {
        memory.debug = !memory.debug
        if memory.debug do log.debug("Debug mode on")
    }
    if memory.debug {
        UI_Column("debug_info",
            UI_Text("debug_fps", "FPS: %d", int(1.0 / f32(memory.delta_time)), alignments = {.Min, .Center}),
            UI_Text("debug_time", "Time: %.3f", memory.time, alignments = {.Min, .Center}),
            alignments = { .Min, .Min },
        )

        UI_Table("timing_table", memory.time_records, alignments = [2]UI_Alignment{.Max, .Max})
        clear_time_records()
    }

    compute_layout()

    // Prune stale elements
    for name, element in ui_context.elements {
        if element.last_frame < ui_context.frame {
            pool.put(&ui_context.pool, element)
            delete_key(&ui_context.elements, name)
        }
    }

    // Render elements
    element := ui_context.root
    for element != nil {
        position: [2]f32 = element.relative_position
        parent := element.parent
        for parent != nil {
            position += parent.relative_position
            parent = parent.parent
        }
        element.position = position

        if .Draw_Rect in element.flags {
            push_rect(render_group, position.x, position.y, element.sizes.x.value, element.sizes.y.value, color = element.color)
        }

        if .Draw_Text in element.flags {
            rect := asset.get_text_rect(element.font, element.text, 0, 0, element.points)
            pen := position - {0, rect.top}
            push_text(render_group, element.text, pen.x, pen.y, element.points, element.font, element.color)
        }
        element, element.next = element.next, nil
    }

    ui_context.root, ui_context.last = nil, nil
}