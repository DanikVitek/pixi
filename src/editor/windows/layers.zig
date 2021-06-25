const std = @import("std");
const upaya = @import("upaya");
const imgui = @import("imgui");

const types = @import("../types/types.zig");
const canvas = @import("canvas.zig");

const Layer = types.Layer;

var active_layer_index: usize = 0;

pub fn getActiveLayer() ?*Layer {
    if (canvas.getActiveFile()) |file| {
        return &file.layers.items[active_layer_index];
    } else return null;
}

pub fn draw() void {
    if (imgui.igBegin("Layers", 0, imgui.ImGuiWindowFlags_NoResize)) {
        defer imgui.igEnd();

        var file = canvas.getActiveFile();

        if (file) |f| {
            if (imgui.ogColoredButton(0x00000000, imgui.icons.plus_circle)) {
                var image = upaya.Image.init(@intCast(usize, f.width), @intCast(usize, f.height));
                image.fillRect(.{.x = 0, .y = 0, .width = f.width, .height = f.height}, upaya.math.Color.transparent);
                f.layers.insert(0, .{
                    .name = std.fmt.allocPrint(upaya.mem.allocator, "Layer {d}\u{0}", .{f.layers.items.len}) catch unreachable,
                    .image = image,
                    .texture = image.asTexture(.nearest),
                }) catch unreachable;
                active_layer_index += 1;
            }
            imgui.igSeparator();

            for (f.layers.items) |layer, i| {
                imgui.igPushIDInt(@intCast(i32, i));
                imgui.igBeginGroup();
                imgui.igPushIDInt(@intCast(i32, i));

                var eye = if (!layer.hidden) imgui.icons.eye else imgui.icons.eye_slash;
                if (imgui.ogColoredButton(0x00000000, eye)) {
                    f.layers.items[i].hidden = !layer.hidden;
                }

                imgui.igPopID();
                imgui.igSameLine(0, 5);

                if (imgui.ogSelectableBool(@ptrCast([*c]const u8, layer.name), i == active_layer_index, imgui.ImGuiSelectableFlags_DrawHoveredWhenHeld, .{}))
                    active_layer_index = i;

                imgui.igEndGroup();
                imgui.igPopID();

                if (imgui.igIsItemActive() and !imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_AllowWhenDisabled)) {
                    var i_next = @intCast(i32, i) + if (imgui.ogGetMouseDragDelta(imgui.ImGuiMouseButton_Left, 0).y < 0) @as(i32, -1) else @as(i32, 1);
                    if (i_next >= 0 and i_next < f.layers.items.len) {

                        //var l = f.layers.orderedRemove(i);
                        //f.layers.insert(@intCast(usize, i_next), l) catch unreachable;
                        f.layers.items[i] = f.layers.items[@intCast(usize, i_next)];
                        f.layers.items[@intCast(usize, i_next)] = layer;
                        active_layer_index = @intCast(usize, i_next);
                        imgui.igResetMouseDragDelta(imgui.ImGuiMouseButton_Left);
                    }
                }
            }
        }
    }
}
