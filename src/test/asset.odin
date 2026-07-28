package test

import "core:testing"
import "../common"

@(test)
test_asset_loading_glb :: proc(T: ^testing.T) {
    asset: common.game_asset
    result := common.load_glb_asset("D:/TestAssets/glTF-Sample-Assets-main/Models/Box/glTF-Binary/Box.glb", &asset)
    testing.expect(T, result)
}