package asset

import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"


epsilon :: 0.000001

Point2 :: distinct [2]f32
Vector2 :: distinct [2]f32

perpendicular :: proc(v: Vector2) -> Vector2 {
    return { -v.y, v.x }
}

get_vector :: proc(start: Point2, end: Point2) -> Vector2 {
    return Vector2(end - start)
}

// Line given by implicit equation coefficients. The zero-th component is the independent term:
//    `line[0] + line[1]*x + line[2]*y = 0`
Line2 :: distinct [3]f32

get_line_from_point_and_direction :: proc(point: Point2, direction: Vector2) -> Line2 {
    return { point.x * direction.y - point.y * direction.x, -direction.y, direction.x }
}

get_line_from_points :: proc(start: Point2, end: Point2) -> Line2 {
    if linalg.distance(start, end) < epsilon do log.fatal("Degenerate line: The two points are the same", start)
    return get_line_from_point_and_direction(start, get_vector(start, end))
}

intersect_line_with_point :: proc(line: Line2, point: Point2) -> bool {
    return math.abs(line[0] + line[1] * point.x + line[2] * point.y) < epsilon
}

separate_points :: proc(line: Line2, a: Point2, b: Point2) -> bool {
    return (line[0] + line[1] * a.x + line[2] * a.y) * (line[0] + line[1] * b.x + line[2] * b.y) < 0
}

// If result is > 0, p is strictly left of the line start -> end. If result is < 0, it's strictly right. If 0, point is in the line.
is_left :: proc(start: Point2, end: Point2, p: Point2) -> f32 {
    return (end.x - start.x) * (p.y - start.y) - (p.x - start.x) * (end.y - start.y)
}

Segment2 :: struct {
    start: Point2,
    end: Point2,
}

Rect :: struct {
    left:  f32, top:    f32,
    width: f32, height: f32,
}

get_points_rect :: proc(rect: Rect) -> [4]Point2 {
    return {
        {rect.left, rect.top},
        {rect.left + rect.width, rect.top},
        {rect.left + rect.width, rect.top + rect.height},
        {rect.left, rect.top + rect.height},
    }
}

get_lines_rect :: proc(rect: Rect) -> [4]Line2 {
    points := get_points_rect(rect)
    return {
        get_line_from_points(points[0], points[1]),
        get_line_from_points(points[1], points[2]),
        get_line_from_points(points[2], points[3]),
        get_line_from_points(points[3], points[0]),
    }
}

intersect_rect_with_line :: proc(rect: Rect, line: Line2) -> bool {
    points := get_points_rect(rect)
    for i in 0..<4 {
        for j in 0..<4 {
            if i < j {
                if separate_points(line, points[i], points[j]) {
                    return true
                }
            }
        }
    }
    return false
}

intersect_rect_with_segment :: proc(rect: Rect, segment: Segment2) -> bool {
    min_x := rect.left
    max_x := rect.left + rect.width
    min_y := rect.top
    max_y := rect.top + rect.height

    segment_view := segment
    delta := segment.end - segment.start

    min_tx, max_tx: f32
    if abs(delta.x) < epsilon {
        if min_x <= segment.start.x && segment.start.x <= max_x {
            min_tx = 0
            max_tx = 1
        }
        else do return false
    }
    else {
        tx_1 := (min_x - segment.start.x) / delta.x
        tx_2 := (max_x - segment.start.x) / delta.x
    
        min_tx = min(tx_1, tx_2)
        max_tx = max(tx_1, tx_2)
    }
    
    min_ty, max_ty: f32
    if abs(delta.y) < epsilon {
        if min_y <= segment.start.y && segment.start.y <= max_y {
            min_ty = 0
            max_ty = 1
        }
        else do return false
    }
    else {
        ty_1 := (min_y - segment.start.y) / delta.y
        ty_2 := (max_y - segment.start.y) / delta.y
    
        min_ty = min(ty_1, ty_2)
        max_ty = max(ty_1, ty_2)
    }

    return max(0, min_tx, min_ty) <= min(1, max_tx, max_ty)
}

Triangle2 :: distinct [3]Point2

get_area :: proc(triangle: Triangle2) -> f32 {
    u := get_vector(triangle[0], triangle[1])
    v := get_vector(triangle[1], triangle[2])
    return 0.5 * (u.x * v.y - u.y * v.x)
}

// The lines are ordered so that the point with the same index is the opposite vertex.
get_lines_triangle :: proc(triangle: Triangle2) -> [3]Line2 {
    return {
        get_line_from_points(triangle[1], triangle[2]),
        get_line_from_points(triangle[2], triangle[0]),
        get_line_from_points(triangle[0], triangle[1]),
    }
}

intersect_triangle_with_line :: proc(triangle: Triangle2, line: Line2) -> bool {
    return separate_points(line, triangle[0], triangle[1]) ||
           separate_points(line, triangle[1], triangle[2]) ||
           separate_points(line, triangle[2], triangle[0])
}

intersect_rect_with_triangle :: proc(rect: Rect, triangle: Triangle2) -> bool {
    triangle_min_x := min(triangle[0].x, triangle[1].x, triangle[2].x)
    triangle_max_x := max(triangle[0].x, triangle[1].x, triangle[2].x)
    triangle_min_y := min(triangle[0].y, triangle[1].y, triangle[2].y)
    triangle_max_y := max(triangle[0].y, triangle[1].y, triangle[2].y)

    if triangle_min_x > rect.left + rect.width || triangle_max_x < rect.left ||
       triangle_min_y > rect.top + rect.height || triangle_max_y < rect.top {
        return false
    }

    triangle_directions := [3]Vector2{
        perpendicular(get_vector(triangle[0], triangle[1])),
        perpendicular(get_vector(triangle[1], triangle[2])),
        perpendicular(get_vector(triangle[2], triangle[0])),
    }

    rect_points := get_points_rect(rect)

    for direction in triangle_directions {
        rect_projections := [4]f32{
            direction.x * rect_points[0].x + direction.y * rect_points[0].y,
            direction.x * rect_points[1].x + direction.y * rect_points[1].y,
            direction.x * rect_points[2].x + direction.y * rect_points[2].y,
            direction.x * rect_points[3].x + direction.y * rect_points[3].y,
        }
        
        rect_max := slice.max(rect_projections[:])
        rect_min := slice.min(rect_projections[:])

        triangle_projections := [3]f32{
            direction.x * triangle[0].x + direction.y * triangle[0].y,
            direction.x * triangle[1].x + direction.y * triangle[1].y,
            direction.x * triangle[2].x + direction.y * triangle[2].y,
        }

        triangle_max := max(triangle_projections[0], triangle_projections[1], triangle_projections[2])
        triangle_min := min(triangle_projections[0], triangle_projections[1], triangle_projections[2])

        if triangle_min > rect_max || triangle_max < rect_min {
            return false
        }
    }

    return true
}