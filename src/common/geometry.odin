package common

import "core:log"
import "core:math"
import "core:math/linalg"


Point2 :: distinct [2]f32
Vector2 :: distinct [2]f32

epsilon :: 0.000001

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

Triangle2 :: distinct [3]Point2

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
        
        rect_max := max(rect_projections[0], rect_projections[1], rect_projections[2], rect_projections[3])
        rect_min := min(rect_projections[0], rect_projections[1], rect_projections[2], rect_projections[3])

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