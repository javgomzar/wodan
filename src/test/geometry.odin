package test

import "core:testing"
import "../common"

@(test)
test_separation :: proc(t: ^testing.T) {
    testing.expect_value(t, common.separate_points({0, 1, 0}, {1, 0}, {-1, 0}), true)
    testing.expect_value(t, common.separate_points({0, 0, 1}, {0, 1}, {0, -1}), true)
    testing.expect_value(t, common.separate_points({0, 1, 1}, {1, 1}, {-1, -1}), true)
    testing.expect_value(t, common.separate_points({0, 1, -1}, {1, -1}, {-1, 1}), true)
    testing.expect_value(t, common.separate_points({0, 1, 0}, {0, 1}, {0, -1}), false)
    testing.expect_value(t, common.separate_points({-2, 0, 1}, {0, 1}, {0, 3}), true)
    testing.expect_value(t, common.separate_points({1, 0, 1}, {0, 1}, {0, 3}), false)
}