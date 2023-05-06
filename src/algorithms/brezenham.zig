const std = @import("std");
const pixi = @import("root");

pub fn process(start: [2]f32, end: [2]f32) ![][2]f32 {
    var output = std.ArrayList([2]f32).init(pixi.state.allocator);

    var x1 = start[0];
    var y1 = start[1];
    var x2 = end[0];
    var y2 = end[1];

    const steep = @fabs(y2 - y1) > @fabs(x2 - x1);
    if (steep) {
        std.mem.swap(f32, &x1, &y1);
        std.mem.swap(f32, &x2, &y2);
    }

    if (x1 > x2) {
        std.mem.swap(f32, &x1, &x2);
        std.mem.swap(f32, &y1, &y2);
    }

    const dx: f32 = x2 - x1;
    const dy: f32 = @fabs(y2 - y1);

    var err: f32 = dx / 2.0;
    var ystep: i32 = if (y1 < y2) 1 else -1;
    var y: i32 = @floatToInt(i32, y1);

    const maxX: i32 = @floatToInt(i32, x2);

    var x: i32 = @floatToInt(i32, x1);
    while (x <= maxX) : (x += 1) {
        if (steep) {
            try output.append(.{ @intToFloat(f32, y), @intToFloat(f32, x) });
        } else {
            try output.append(.{ @intToFloat(f32, x), @intToFloat(f32, y) });
        }

        err -= dy;
        if (err < 0) {
            y += ystep;
            err += dx;
        }
    }

    return output.toOwnedSlice();
}