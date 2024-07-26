const std = @import("std");
const pixi = @import("../../../pixi.zig");
const mach = @import("mach");
const core = mach.core;
const imgui = @import("zig-imgui");
const zmath = @import("zmath");

pub var selected_frame_id: ?u32 = null;

var frame_node_hovered: ?u32 = null;
var frame_node_dragging: ?u32 = null;
var keyframe_dragging: ?u32 = null;
var time_hovered_ms: ?usize = null;

pub fn draw(file: *pixi.storage.Internal.Pixi) void {
    const window_height = imgui.getWindowHeight();
    const window_width = imgui.getWindowWidth();
    const tile_width = @as(f32, @floatFromInt(file.tile_width));
    const tile_height = @as(f32, @floatFromInt(file.tile_height));
    const canvas_center_offset: [2]f32 = file.canvasCenterOffset(.flipbook);
    const window_position = imgui.getWindowPos();

    const grip_size: f32 = 10.0;
    const half_grip_size = grip_size / 2.0;
    const scaled_grip_size = grip_size / file.flipbook_camera.zoom;

    const frame_node_radius: f32 = 5.0;
    const frame_node_spacing: f32 = 4.0;

    var animation_opt: ?*pixi.storage.Internal.KeyframeAnimation = if (file.keyframe_animations.items.len > 0) &file.keyframe_animations.items[file.selected_keyframe_animation_index] else null;

    const timeline_height = imgui.getWindowHeight() * 0.25;
    const text_area_height: f32 = imgui.getTextLineHeight();

    var latest_time: f32 = 0.0;
    if (animation_opt) |animation| {
        latest_time = animation.length();
    }

    const length: f32 = latest_time + 2.0;
    const animation_ms: usize = @intFromFloat(length * 1000.0);
    const zoom: f32 = 1.0;
    _ = zoom; // autofix

    const scroll_bar_height: f32 = imgui.getStyle().scrollbar_size;

    {
        imgui.pushStyleColorImVec4(imgui.Col_ChildBg, pixi.state.theme.foreground.toImguiVec4());
        defer imgui.popStyleColor();

        imgui.pushStyleVarImVec2(imgui.StyleVar_WindowPadding, .{ .x = 0.0, .y = 0.0 });
        defer imgui.popStyleVar();

        if (imgui.beginChild("FlipbookTimeline", .{ .x = 0.0, .y = timeline_height + (scroll_bar_height / 2.0) }, imgui.ChildFlags_None, imgui.WindowFlags_ChildWindow | imgui.WindowFlags_AlwaysHorizontalScrollbar)) {
            defer imgui.endChild();

            const work_area_offset: f32 = 12.0;
            const work_area_width: f32 = length * 1000.0 + work_area_offset;

            const scroll_x: f32 = imgui.getScrollX();
            const scroll_y: f32 = imgui.getScrollY();

            const window_hovered: bool = imgui.isWindowHovered(imgui.HoveredFlags_ChildWindows);

            var rel_mouse_x: ?f32 = null;
            var rel_mouse_y: ?f32 = null;

            if (window_hovered) {
                const mouse_position = pixi.state.mouse.position;
                rel_mouse_x = mouse_position[0] - window_position.x + scroll_x;
                rel_mouse_y = mouse_position[1] - window_position.y + scroll_y;
            }

            if (imgui.beginChild("FlipbookTimelineWorkArea", .{ .x = work_area_width, .y = timeline_height - text_area_height - scroll_bar_height }, imgui.ChildFlags_None, imgui.WindowFlags_ChildWindow)) {
                defer imgui.endChild();

                const max_nodes: f32 = if (animation_opt) |animation| @floatFromInt(animation.maxNodes()) else 0.0;
                const node_area_height = @max(max_nodes * (frame_node_radius * 2.0 + frame_node_spacing) + work_area_offset, imgui.getWindowHeight());

                if (imgui.getWindowDrawList()) |draw_list| {
                    for (0..animation_ms) |ms| {
                        const ms_float: f32 = @floatFromInt(ms);
                        const x: f32 = ms_float + work_area_offset - scroll_x + window_position.x;
                        const y: f32 = imgui.getWindowPos().y;

                        if (@mod(ms, 10) == 0) {
                            const thickness: f32 = if (@mod(ms, 1000) == 0) 3.0 else if (@mod(ms, 100) == 0) 2.0 else 1.0;

                            const line_hovered: bool = if (rel_mouse_x) |mouse_x| @abs(mouse_x - (ms_float + work_area_offset)) < frame_node_radius else false;
                            const color: u32 = if (line_hovered) pixi.state.theme.highlight_primary.toU32() else pixi.state.theme.text_background.toU32();
                            draw_list.addLineEx(.{ .x = x, .y = y }, .{ .x = x, .y = y + imgui.getWindowHeight() }, color, thickness);

                            if (line_hovered) {
                                time_hovered_ms = ms;

                                const current_time = ms_float / 1000.0;
                                if (pixi.state.mouse.button(.primary)) |bt| {
                                    if (bt.pressed()) {
                                        const primary_hotkey_down: bool = if (pixi.state.hotkeys.hotkey(.{ .proc = .primary })) |hk| hk.down() else false;

                                        if (primary_hotkey_down) {
                                            if (animation_opt == null) {
                                                const new_animation: pixi.storage.Internal.KeyframeAnimation = .{
                                                    .name = "New Keyframe Animation",
                                                    .keyframes = std.ArrayList(pixi.storage.Internal.Keyframe).init(pixi.state.allocator),
                                                    .active_keyframe_id = 0,
                                                    .id = file.newId(),
                                                };

                                                file.keyframe_animations.append(new_animation) catch unreachable;
                                                animation_opt = &file.keyframe_animations.items[file.keyframe_animations.items.len - 1];
                                            }

                                            if (animation_opt) |animation| {

                                                // add node to map, either create a new keyframe or add to existing keyframe
                                                for (file.selected_sprites.items) |sprite_index| {
                                                    const sprite = file.sprites.items[sprite_index];
                                                    const origin = zmath.loadArr2(.{ sprite.origin_x, sprite.origin_y });

                                                    const new_frame: pixi.storage.Internal.Frame = .{
                                                        .id = file.newFrameId(),
                                                        .layer_id = file.layers.items[file.selected_layer_index].id,
                                                        .sprite_index = sprite_index,
                                                        .pivot = .{ .position = zmath.f32x4s(0.0) },
                                                        .vertices = .{
                                                            .{ .position = -origin }, // TL
                                                            .{ .position = zmath.loadArr2(.{ tile_width, 0.0 }) - origin }, // TR
                                                            .{ .position = zmath.loadArr2(.{ tile_width, tile_height }) - origin }, //BR
                                                            .{ .position = zmath.loadArr2(.{ 0.0, tile_height }) - origin }, // BL
                                                        },
                                                    };

                                                    if (animation.getKeyframeMilliseconds(ms)) |kf| {
                                                        kf.frames.append(new_frame) catch unreachable;
                                                        animation.active_keyframe_id = kf.id;
                                                    } else {
                                                        var new_keyframe: pixi.storage.Internal.Keyframe = .{
                                                            .id = file.newKeyframeId(),
                                                            .time = current_time,
                                                            .frames = std.ArrayList(pixi.storage.Internal.Frame).init(pixi.state.allocator),
                                                            .active_frame_id = new_frame.id,
                                                        };

                                                        new_keyframe.frames.append(new_frame) catch unreachable;
                                                        animation.keyframes.append(new_keyframe) catch unreachable;
                                                        animation.active_keyframe_id = new_keyframe.id;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                {
                    imgui.pushStyleColor(imgui.Col_ChildBg, 0x00000000);
                    defer imgui.popStyleColor();

                    if (imgui.beginChild("FlipbookTimelineNodeArea", .{ .x = work_area_width, .y = node_area_height }, imgui.ChildFlags_None, imgui.WindowFlags_ChildWindow | imgui.WindowFlags_NoScrollWithMouse)) {
                        defer imgui.endChild();
                        if (animation_opt) |animation| {
                            if (imgui.getWindowDrawList()) |draw_list| {
                                for (0..animation_ms) |ms| {
                                    const ms_float: f32 = @floatFromInt(ms);

                                    const line_hovered: bool = if (rel_mouse_x) |mouse_x| @abs(mouse_x - (ms_float + work_area_offset)) < frame_node_radius else false;

                                    var x: f32 = @floatFromInt(ms);
                                    x += work_area_offset - scroll_x + window_position.x;

                                    if (animation.getKeyframeMilliseconds(ms)) |kf| {
                                        for (kf.frames.items, 0..) |fr, fr_index| {
                                            if (fr.id == frame_node_dragging and !line_hovered)
                                                continue;

                                            const color_index: usize = @mod(fr.id * 2, 35);

                                            const color = if (pixi.state.colors.keyframe_palette) |palette| pixi.math.Color.initBytes(
                                                palette.colors[color_index][0],
                                                palette.colors[color_index][1],
                                                palette.colors[color_index][2],
                                                palette.colors[color_index][3],
                                            ).toU32() else pixi.state.theme.text.toU32();

                                            const index_float: f32 = @floatFromInt(fr_index);
                                            const y: f32 = imgui.getWindowPos().y + (index_float * ((frame_node_radius * 2.0) + frame_node_spacing)) + work_area_offset;

                                            var frame_node_scale: f32 = 1.0;
                                            if (rel_mouse_x) |mouse_x| {
                                                if (rel_mouse_y) |mouse_y| {
                                                    if (@abs(mouse_x - (ms_float + work_area_offset)) < frame_node_radius) {
                                                        const diff_y = @abs(mouse_y + window_position.y - y);
                                                        const diff_radius = diff_y - frame_node_radius;

                                                        if (diff_y < frame_node_radius)
                                                            frame_node_hovered = fr.id;

                                                        frame_node_scale = std.math.clamp(2.0 - diff_radius / 4.0, 1.0, 2.0);
                                                    }
                                                }
                                            }

                                            if (pixi.state.mouse.button(.primary)) |bt| {
                                                if (bt.pressed() and window_hovered and line_hovered) {
                                                    if (frame_node_hovered) |frame_hovered| {
                                                        frame_node_dragging = frame_hovered;
                                                    } else {
                                                        keyframe_dragging = kf.id;
                                                    }
                                                }
                                            }

                                            draw_list.addCircleFilled(.{ .x = x, .y = y }, frame_node_radius * frame_node_scale, color, 20);
                                            draw_list.addCircle(.{ .x = x, .y = y }, frame_node_radius * frame_node_scale + 1.0, pixi.state.theme.text_background.toU32());
                                        }
                                    }

                                    if (@mod(ms, 10) == 0 and line_hovered and window_hovered) {
                                        if (frame_node_dragging) |frame_id| {
                                            if (pixi.state.mouse.button(.primary)) |bt| {
                                                if (bt.released()) {
                                                    defer frame_node_dragging = null;
                                                    if (animation.getKeyframeFromFrame(frame_id)) |frame_keyframe| {
                                                        if (animation.getKeyframeMilliseconds(ms)) |new_keyframe| {
                                                            if (new_keyframe.id != frame_keyframe.id) {
                                                                if (frame_keyframe.frameIndex(frame_id)) |frame_index| {
                                                                    const drag_frame = frame_keyframe.frames.orderedRemove(frame_index);

                                                                    new_keyframe.frames.append(drag_frame) catch unreachable;

                                                                    if (frame_keyframe.frames.items.len == 0) {
                                                                        if (animation.keyframeIndex(frame_keyframe.id)) |empty_kf_index| {
                                                                            var empty_kf = animation.keyframes.orderedRemove(empty_kf_index);
                                                                            empty_kf.frames.clearAndFree();
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        } else {
                                                            var new_keyframe: pixi.storage.Internal.Keyframe = .{
                                                                .active_frame_id = frame_id,
                                                                .id = file.newKeyframeId(),
                                                                .frames = std.ArrayList(pixi.storage.Internal.Frame).init(pixi.state.allocator),
                                                                .time = ms_float / 1000.0,
                                                            };

                                                            if (frame_keyframe.frameIndex(frame_id)) |frame_index| {
                                                                const drag_frame = frame_keyframe.frames.orderedRemove(frame_index);

                                                                if (frame_keyframe.frames.items.len == 0) {
                                                                    if (animation.keyframeIndex(frame_keyframe.id)) |empty_kf_index| {
                                                                        var empty_kf = animation.keyframes.orderedRemove(empty_kf_index);
                                                                        empty_kf.frames.clearAndFree();
                                                                    }
                                                                }

                                                                new_keyframe.frames.append(drag_frame) catch unreachable;
                                                            }

                                                            animation.keyframes.append(new_keyframe) catch unreachable;
                                                        }
                                                    }
                                                } else {
                                                    var draw_temp_node: bool = true;

                                                    if (animation.getKeyframeFromFrame(frame_id)) |frame_kf| {
                                                        if (animation.getKeyframeMilliseconds(ms)) |ms_kf| {
                                                            if (ms_kf.id == frame_kf.id)
                                                                draw_temp_node = false;
                                                        }
                                                    }

                                                    if (draw_temp_node) {
                                                        const index_float: f32 = @floatFromInt(if (animation.getKeyframeMilliseconds(ms)) |kf| kf.frames.items.len else 0);

                                                        const y: f32 = imgui.getWindowPos().y + (index_float * ((frame_node_radius * 2.0) + frame_node_spacing)) + work_area_offset;

                                                        const color_index: usize = @mod(frame_id * 2, 35);

                                                        const color = if (pixi.state.colors.keyframe_palette) |palette| pixi.math.Color.initBytes(
                                                            palette.colors[color_index][0],
                                                            palette.colors[color_index][1],
                                                            palette.colors[color_index][2],
                                                            palette.colors[color_index][3],
                                                        ).toU32() else pixi.state.theme.text.toU32();

                                                        draw_list.addCircleFilled(.{ .x = x, .y = y }, frame_node_radius * 2.0, color, 20);
                                                        draw_list.addCircle(.{ .x = x, .y = y }, frame_node_radius * 2.0 + 1.0, pixi.state.theme.text_background.toU32());
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (imgui.beginChild("FlipbookTimelineTextArea", .{ .x = work_area_width, .y = text_area_height }, imgui.ChildFlags_None, imgui.WindowFlags_ChildWindow)) {
                defer imgui.endChild();

                if (imgui.getWindowDrawList()) |draw_list| {
                    for (0..animation_ms) |ms| {
                        var x: f32 = @floatFromInt(ms);
                        x += work_area_offset - scroll_x + window_position.x;

                        const y: f32 = imgui.getWindowPos().y;

                        if (@mod(ms, 100) == 0) {
                            const template = if (@mod(ms, 1000) == 0) "s" else "ms";
                            const value = if (@mod(ms, 1000) == 0) @divExact(ms, 1000) else ms;

                            const text = std.fmt.allocPrintZ(pixi.state.allocator, "{d} {s}", .{ value, template }) catch unreachable;
                            defer pixi.state.allocator.free(text);

                            draw_list.addText(.{ .x = x, .y = y }, pixi.state.theme.text_background.toU32(), text);
                        }
                    }
                }
            }
        }
    }

    if (imgui.beginChild("FlipbookCanvas", .{ .x = window_width, .y = 0.0 }, imgui.ChildFlags_None, imgui.WindowFlags_ChildWindow)) {
        defer imgui.endChild();

        // Handle zooming, panning and extents
        {
            var sprite_camera: pixi.gfx.Camera = .{
                .zoom = window_height / tile_height,
            };
            const zoom_index = sprite_camera.nearestZoomIndex();
            const max_zoom_index = if (zoom_index < pixi.state.settings.zoom_steps.len - 2) zoom_index + 2 else zoom_index;
            const max_zoom = pixi.state.settings.zoom_steps[max_zoom_index];
            sprite_camera.setNearZoomFloor();
            const min_zoom = 1.0;

            file.flipbook_camera.processPanZoom();

            // Lock camera from zooming in or out too far for the flipbook
            file.flipbook_camera.zoom = std.math.clamp(file.flipbook_camera.zoom, min_zoom, max_zoom);

            const view_width: f32 = tile_width * 4.0;
            const view_height: f32 = tile_height * 4.0;

            // Lock camera from moving too far away from canvas
            const min_position: [2]f32 = .{ canvas_center_offset[0] - view_width / 2.0, canvas_center_offset[1] - view_height / 2.0 };
            const max_position: [2]f32 = .{ canvas_center_offset[0] + view_width, canvas_center_offset[1] + view_height };

            file.flipbook_camera.position[0] = std.math.clamp(file.flipbook_camera.position[0], min_position[0], max_position[0]);
            file.flipbook_camera.position[1] = std.math.clamp(file.flipbook_camera.position[1], min_position[1], max_position[1]);
        }

        const grid_columns: f32 = 20;
        const grid_rows: f32 = 20;
        const grid_width: f32 = tile_width * grid_columns;
        const grid_height: f32 = tile_height * grid_rows;

        file.flipbook_camera.drawGrid(.{ -grid_width / 2.0, -grid_height / 2.0 }, grid_width, grid_height, @intFromFloat(grid_columns), @intFromFloat(grid_rows), pixi.state.theme.text_background.toU32(), true);
        file.flipbook_camera.drawCircleFilled(.{ 0.0, 0.0 }, half_grip_size, pixi.state.theme.text_background.toU32());

        const l: f32 = 2000;
        file.flipbook_camera.drawLine(.{ 0.0, l / 2.0 }, .{ 0.0, -l / 2.0 }, 0x5500FF00, 1.0);
        file.flipbook_camera.drawLine(.{ -l / 2.0, 0.0 }, .{ l / 2.0, 0.0 }, 0x550000FF, 1.0);

        file.flipbook_camera.drawTexture(
            file.keyframe_animation_texture.view_handle,
            file.keyframe_animation_texture.image.width,
            file.keyframe_animation_texture.image.height,
            file.canvasCenterOffset(.primary),
            0xFFFFFFFF,
        );

        if (file.keyframe_animations.items.len > 0) {
            const selected_animation = &file.keyframe_animations.items[file.selected_keyframe_animation_index];

            var active_keyframe_index: usize = 0;
            for (selected_animation.keyframes.items, 0..) |keyframe, i| {
                if (keyframe.id == selected_animation.active_keyframe_id)
                    active_keyframe_index = i;
            }

            if (selected_animation.keyframes.items.len > 0) {
                var selected_keyframe: *pixi.storage.Internal.Keyframe = &selected_animation.keyframes.items[active_keyframe_index];

                // Draw transform texture on gpu to temporary texture

                const width: f32 = @floatFromInt(file.width);
                const height: f32 = @floatFromInt(file.height);

                const uniforms = pixi.gfx.UniformBufferObject{ .mvp = zmath.transpose(
                    zmath.orthographicLh(width, height, -100, 100),
                ) };

                for (selected_keyframe.frames.items) |*frame| {
                    const color_index: usize = @mod(frame.id * 2, 35);

                    const color = if (pixi.state.colors.keyframe_palette) |palette| pixi.math.Color.initBytes(
                        palette.colors[color_index][0],
                        palette.colors[color_index][1],
                        palette.colors[color_index][2],
                        palette.colors[color_index][3],
                    ).toU32() else pixi.state.theme.text.toU32();

                    if (file.layer(frame.layer_id)) |layer| {
                        if (layer.transform_bindgroup) |transform_bindgroup| {
                            pixi.state.batcher.begin(.{
                                .pipeline_handle = pixi.state.pipeline_default,
                                .bind_group_handle = transform_bindgroup,
                                .output_texture = &file.keyframe_animation_texture,
                                .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
                            }) catch unreachable;

                            if (file.flipbook_camera.isHovered(.{
                                frame.pivot.position[0] - scaled_grip_size / 2.0,
                                frame.pivot.position[1] - scaled_grip_size / 2.0,
                                scaled_grip_size,
                                scaled_grip_size,
                            })) {
                                if (frame.id != selected_keyframe.active_frame_id) {
                                    if (pixi.state.mouse.button(.primary)) |bt| {
                                        if (bt.pressed()) {
                                            var change: bool = true;

                                            if (pixi.state.hotkeys.hotkey(.{ .proc = .secondary })) |hk| {
                                                if (hk.down()) {
                                                    frame.parent_id = null;
                                                    change = false;
                                                }
                                            }

                                            if (frame.id != selected_keyframe.active_frame_id) {
                                                if (pixi.state.hotkeys.hotkey(.{ .proc = .primary })) |hk| {
                                                    if (hk.down()) {
                                                        if (selected_keyframe.frame(selected_keyframe.active_frame_id)) |active_frame| {
                                                            active_frame.parent_id = frame.id;
                                                        }

                                                        change = false;
                                                    }
                                                }
                                                if (change) {
                                                    selected_keyframe.active_frame_id = frame.id;
                                                }
                                            }
                                        }
                                    }
                                    file.flipbook_camera.drawCircleFilled(
                                        .{ frame.pivot.position[0], frame.pivot.position[1] },
                                        half_grip_size * 1.5,
                                        color,
                                    );
                                    file.flipbook_camera.drawCircle(
                                        .{ frame.pivot.position[0], frame.pivot.position[1] },
                                        half_grip_size * 1.5 + 1.0,
                                        1.0,
                                        pixi.state.theme.text_background.toU32(),
                                    );
                                }
                            } else {
                                file.flipbook_camera.drawCircleFilled(
                                    .{ frame.pivot.position[0], frame.pivot.position[1] },
                                    half_grip_size,
                                    color,
                                );
                                file.flipbook_camera.drawCircle(
                                    .{ frame.pivot.position[0], frame.pivot.position[1] },
                                    half_grip_size + 1.0,
                                    1.0,
                                    pixi.state.theme.text_background.toU32(),
                                );
                            }

                            const tiles_wide = @divExact(file.width, file.tile_width);

                            const src_col = @mod(@as(u32, @intCast(frame.sprite_index)), tiles_wide);
                            const src_row = @divTrunc(@as(u32, @intCast(frame.sprite_index)), tiles_wide);

                            const src_x = src_col * file.tile_width;
                            const src_y = src_row * file.tile_height;

                            const sprite: pixi.gfx.Sprite = .{
                                .name = "",
                                .origin = .{ 0, 0 },
                                .source = .{
                                    src_x,
                                    src_y,
                                    file.tile_width,
                                    file.tile_height,
                                },
                            };

                            var rotation = -frame.rotation;

                            if (frame.parent_id) |parent_id| {
                                for (selected_keyframe.frames.items) |parent_frame| {
                                    if (parent_frame.id == parent_id) {
                                        const diff = parent_frame.pivot.position - frame.pivot.position;

                                        const angle = std.math.atan2(diff[1], diff[0]);

                                        rotation -= std.math.radiansToDegrees(angle) - 90.0;

                                        file.flipbook_camera.drawLine(
                                            .{ frame.pivot.position[0], frame.pivot.position[1] },
                                            .{ parent_frame.pivot.position[0], parent_frame.pivot.position[1] },
                                            color,
                                            1.0,
                                        );
                                    }
                                }
                            }

                            pixi.state.batcher.transformSprite(
                                &layer.texture,
                                sprite,
                                frame.vertices,
                                .{ 0.0, 0.0 },
                                .{ frame.pivot.position[0], -frame.pivot.position[1] },
                                .{
                                    .rotation = rotation,
                                },
                            ) catch unreachable;

                            pixi.state.batcher.end(uniforms, pixi.state.uniform_buffer_default) catch unreachable;
                        }

                        if (selected_keyframe.active_frame_id == frame.id) {
                            // Write from the frame to the transform texture
                            @memcpy(&file.keyframe_transform_texture.vertices, &frame.vertices);
                            file.keyframe_transform_texture.pivot = frame.pivot;
                            file.keyframe_transform_texture.rotation = frame.rotation;

                            // Write parent id
                            if (frame.parent_id) |parent_id| {
                                file.keyframe_transform_texture.keyframe_parent_id = parent_id;
                            }

                            // Process transform texture controls
                            file.processTransformTextureControls(&file.keyframe_transform_texture, .{
                                .canvas = .flipbook,
                                .allow_pivot_move = false,
                                .allow_vert_move = false,
                                .color = color,
                            });

                            // Clear the parent
                            file.keyframe_transform_texture.keyframe_parent_id = null;

                            // Write back to the frame
                            @memcpy(&frame.vertices, &file.keyframe_transform_texture.vertices);
                            frame.pivot = file.keyframe_transform_texture.pivot.?;
                            frame.rotation = file.keyframe_transform_texture.rotation;
                        }

                        // We are using a load on the gpu texture, so we need to clear this texture on the gpu after we are done
                        @memset(file.keyframe_animation_texture.image.data, 0.0);
                        file.keyframe_animation_texture.update(core.device);
                    }
                }
            }
        }

        time_hovered_ms = null;
    }
}
