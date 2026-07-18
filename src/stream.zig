const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

const Terminal = ghostty_vt.Terminal;
const Screen = ghostty_vt.Screen;
const Action = ghostty_vt.StreamAction;
const apc = ghostty_vt.apc;
const color = ghostty_vt.color;
const osc = ghostty_vt.osc;
const size_report = ghostty_vt.size_report;
const kitty = ghostty_vt.kitty;
const modes = ghostty_vt.modes;
const device_status = ghostty_vt.device_status;
const device_attributes = struct {
    const Req = Action.Value(.device_attributes);
    const Attributes = @typeInfo(
        @typeInfo(
            @typeInfo(
                @FieldType(
                    ghostty_vt.TerminalStream.Handler.Effects,
                    "device_attributes",
                ),
            ).optional.child,
        ).pointer.child,
    ).@"fn".return_type.?;
};
const csi = struct {
    const SizeReportStyle = ghostty_vt.SizeReportStyle;
};

pub const Handler = struct {
    terminal: *Terminal,

    apc_handler: apc.Handler = .{},

    const default_cursor_style: Screen.CursorStyle = .block;
    const default_cursor_blink: bool = false;

    pub fn init(terminal: *Terminal) Handler {
        return .{
            .terminal = terminal,
        };
    }

    pub fn deinit(self: *Handler) void {
        self.apc_handler.deinit();
    }

    pub fn vt(
        self: *Handler,
        comptime action: Action.Tag,
        value: Action.Value(action),
    ) void {
        self.vtFallible(action, value) catch |err| {
            std.log.warn("error handling VT action action={} err={}", .{ action, err });
        };
    }

    inline fn vtFallible(
        self: *Handler,
        comptime action: Action.Tag,
        value: Action.Value(action),
    ) !void {
        switch (action) {
            .print => {
                try self.terminal.print(value.cp);
            },
            .print_slice => {
                try self.terminal.printSlice(value.cps);
            },
            .print_repeat => {
                try self.terminal.printRepeat(value);
            },
            .backspace => {
                self.terminal.backspace();
            },
            .carriage_return => {
                self.terminal.carriageReturn();
            },
            .linefeed => {
                try self.terminal.linefeed();
            },
            .index => {
                try self.terminal.index();
            },
            .next_line => {
                try self.terminal.index();
                self.terminal.carriageReturn();
            },
            .reverse_index => {
                self.terminal.reverseIndex();
            },
            .cursor_up => {
                self.terminal.cursorUp(value.value);
            },
            .cursor_down => {
                self.terminal.cursorDown(value.value);
            },
            .cursor_left => {
                self.terminal.cursorLeft(value.value);
            },
            .cursor_right => {
                self.terminal.cursorRight(value.value);
            },
            .cursor_pos => {
                self.terminal.setCursorPos(value.row, value.col);
            },
            .cursor_col => {
                self.terminal.setCursorPos(self.terminal.screens.active.cursor.y + 1, value.value);
            },
            .cursor_row => {
                self.terminal.setCursorPos(value.value, self.terminal.screens.active.cursor.x + 1);
            },
            .cursor_col_relative => {
                self.terminal.setCursorPos(
                    self.terminal.screens.active.cursor.y + 1,
                    self.terminal.screens.active.cursor.x + 1 +| value.value,
                );
            },
            .cursor_row_relative => {
                self.terminal.setCursorPos(
                    self.terminal.screens.active.cursor.y + 1 +| value.value,
                    self.terminal.screens.active.cursor.x + 1,
                );
            },
            .cursor_style => {
                const blink = switch (value) {
                    .default => default_cursor_blink,
                    .steady_block, .steady_bar, .steady_underline => false,
                    .blinking_block, .blinking_bar, .blinking_underline => true,
                };
                const style: Screen.CursorStyle = switch (value) {
                    .default => default_cursor_style,
                    .blinking_block, .steady_block => .block,
                    .blinking_bar, .steady_bar => .bar,
                    .blinking_underline, .steady_underline => .underline,
                };
                self.terminal.modes.set(.cursor_blinking, blink);
                self.terminal.screens.active.cursor.cursor_style = style;
            },
            .erase_display_below => {
                self.terminal.eraseDisplay(.below, value);
            },
            .erase_display_above => {
                self.terminal.eraseDisplay(.above, value);
            },
            .erase_display_complete => {
                self.terminal.eraseDisplay(.complete, value);
            },
            .erase_display_scrollback => {
                self.terminal.eraseDisplay(.scrollback, value);
            },
            .erase_display_scroll_complete => {
                self.terminal.eraseDisplay(.scroll_complete, value);
            },
            .erase_line_right => {
                self.terminal.eraseLine(.right, value);
            },
            .erase_line_left => {
                self.terminal.eraseLine(.left, value);
            },
            .erase_line_complete => {
                self.terminal.eraseLine(.complete, value);
            },
            .erase_line_right_unless_pending_wrap => {
                self.terminal.eraseLine(.right_unless_pending_wrap, value);
            },
            .delete_chars => {
                self.terminal.deleteChars(value);
            },
            .erase_chars => {
                self.terminal.eraseChars(value);
            },
            .insert_lines => {
                self.terminal.insertLines(value);
            },
            .insert_blanks => {
                self.terminal.insertBlanks(value);
            },
            .delete_lines => {
                self.terminal.deleteLines(value);
            },
            .scroll_up => {
                try self.terminal.scrollUp(value);
            },
            .scroll_down => {
                self.terminal.scrollDown(value);
            },
            .horizontal_tab => {
                self.horizontalTab(value);
            },
            .horizontal_tab_back => {
                self.horizontalTabBack(value);
            },
            .tab_clear_current => {
                self.terminal.tabClear(.current);
            },
            .tab_clear_all => {
                self.terminal.tabClear(.all);
            },
            .tab_set => {
                self.terminal.tabSet();
            },
            .tab_reset => {
                self.terminal.tabReset();
            },
            .set_mode => {
                try self.setMode(value.mode, true);
            },
            .reset_mode => {
                try self.setMode(value.mode, false);
            },
            .save_mode => {
                self.terminal.modes.save(value.mode);
            },
            .restore_mode => {
                const v = self.terminal.modes.restore(value.mode);
                try self.setMode(value.mode, v);
            },
            .top_and_bottom_margin => {
                self.terminal.setTopAndBottomMargin(value.top_left, value.bottom_right);
            },
            .left_and_right_margin => {
                self.terminal.setLeftAndRightMargin(value.top_left, value.bottom_right);
            },
            .left_and_right_margin_ambiguous => {
                if (self.terminal.modes.get(.enable_left_and_right_margin)) {
                    self.terminal.setLeftAndRightMargin(0, 0);
                } else {
                    self.terminal.saveCursor();
                }
            },
            .save_cursor => {
                self.terminal.saveCursor();
            },
            .restore_cursor => {
                self.terminal.restoreCursor();
            },
            .invoke_charset => {
                self.terminal.invokeCharset(value.bank, value.charset, value.locking);
            },
            .configure_charset => {
                self.terminal.configureCharset(value.slot, value.charset);
            },
            .set_attribute => {
                try self.terminal.setAttribute(value);
            },
            .protected_mode_off => {
                self.terminal.setProtectedMode(.off);
            },
            .protected_mode_iso => {
                self.terminal.setProtectedMode(.iso);
            },
            .protected_mode_dec => {
                self.terminal.setProtectedMode(.dec);
            },
            .mouse_shift_capture => {
                self.terminal.flags.mouse_shift_capture = if (value) .true else .false;
            },
            .kitty_keyboard_push => {
                self.terminal.screens.active.kitty_keyboard.push(value.flags);
            },
            .kitty_keyboard_pop => {
                self.terminal.screens.active.kitty_keyboard.pop(@intCast(value));
            },
            .kitty_keyboard_set => {
                self.terminal.screens.active.kitty_keyboard.set(.set, value.flags);
            },
            .kitty_keyboard_set_or => {
                self.terminal.screens.active.kitty_keyboard.set(.@"or", value.flags);
            },
            .kitty_keyboard_set_not => {
                self.terminal.screens.active.kitty_keyboard.set(.not, value.flags);
            },
            .modify_key_format => {
                self.terminal.flags.modify_other_keys_2 = switch (value) {
                    .other_keys_numeric => true,
                    .legacy,
                    .cursor_keys,
                    .function_keys,
                    .other_keys_none,
                    .other_keys_numeric_except,
                    => false,
                };
            },
            .active_status_display => {
                self.terminal.status_display = value;
            },
            .decaln => {
                try self.terminal.decaln();
            },
            .full_reset => {
                self.terminal.fullReset();
                self.terminal.modes.set(.cursor_blinking, default_cursor_blink);
                self.terminal.screens.active.cursor.cursor_style = default_cursor_style;
            },
            .start_hyperlink => {
                try self.terminal.screens.active.startHyperlink(value.uri, value.id);
            },
            .end_hyperlink => {
                self.terminal.screens.active.endHyperlink();
            },
            .semantic_prompt => {
                try self.terminal.semanticPrompt(value);
            },
            .mouse_shape => {
                self.terminal.mouse_shape = value;
            },
            .color_operation => {
                try self.colorOperation(&value.requests, value.terminator);
            },
            .kitty_color_report => {
                try self.kittyColorOperation(value);
            },

            // APC
            .apc_start => {
                self.apc_handler.start();
            },
            .apc_put => {
                self.apc_handler.feed(self.terminal.gpa(), value);
            },
            .apc_put_slice => {
                self.apc_handler.feedSlice(self.terminal.gpa(), value.bytes);
            },
            .apc_end => {
                self.apcEnd();
            },

            // Effect-based handlers
            .bell => {},
            .device_attributes => {
                self.reportDeviceAttributes(value);
            },
            .device_status => {
                self.deviceStatus(value.request);
            },
            .enquiry => {},
            .kitty_keyboard_query => {
                self.queryKittyKeyboard();
            },
            .request_mode => {
                self.requestMode(value.mode);
            },
            .request_mode_unknown => {
                self.requestModeUnknown(value.mode, value.ansi);
            },
            .size_report => {
                self.reportSize(value);
            },
            .window_title => {
                self.windowTitle(value.title);
            },
            .report_pwd => {
                self.reportPwd(value.url);
            },
            .xtversion => {
                self.reportXtversion();
            },
            .clipboard_contents => {},

            // No supported DCS commands have any terminal-modifying effects,
            // but they may in the future. For now we just ignore it.
            .dcs_hook,
            .dcs_put,
            .dcs_unhook,
            => {},

            // Have no terminal-modifying effect
            .show_desktop_notification,
            .progress_report,
            .title_push,
            .title_pop,
            => {},
        }
    }

    inline fn horizontalTab(self: *Handler, count: u16) void {
        for (0..count) |_| {
            const x = self.terminal.screens.active.cursor.x;
            self.terminal.horizontalTab();
            if (x == self.terminal.screens.active.cursor.x) break;
        }
    }

    inline fn horizontalTabBack(self: *Handler, count: u16) void {
        for (0..count) |_| {
            const x = self.terminal.screens.active.cursor.x;
            self.terminal.horizontalTabBack();
            if (x == self.terminal.screens.active.cursor.x) break;
        }
    }

    fn setMode(self: *Handler, mode: modes.Mode, enabled: bool) !void {
        // Set the mode on the terminal
        self.terminal.modes.set(mode, enabled);

        // Some modes require additional processing
        switch (mode) {
            .autorepeat,
            .reverse_colors,
            => {},

            .origin => self.terminal.setCursorPos(1, 1),

            .enable_left_and_right_margin => if (!enabled) {
                self.terminal.scrolling_region.left = 0;
                self.terminal.scrolling_region.right = self.terminal.cols - 1;
            },

            .alt_screen_legacy => try self.terminal.switchScreenMode(.@"47", enabled),
            .alt_screen => try self.terminal.switchScreenMode(.@"1047", enabled),
            .alt_screen_save_cursor_clear_enter => try self.terminal.switchScreenMode(.@"1049", enabled),

            .save_cursor => if (enabled) {
                self.terminal.saveCursor();
            } else {
                self.terminal.restoreCursor();
            },

            .enable_mode_3 => {},

            .@"132_column" => try self.terminal.deccolm(
                self.terminal.screens.active.alloc,
                if (enabled) .@"132_cols" else .@"80_cols",
            ),

            .synchronized_output,
            .linefeed,
            .in_band_size_reports,
            .focus_event,
            => {},

            .mouse_event_x10 => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .x10;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_normal => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .normal;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_button => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .button;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },
            .mouse_event_any => {
                if (enabled) {
                    self.terminal.flags.mouse_event = .any;
                } else {
                    self.terminal.flags.mouse_event = .none;
                }
            },

            .mouse_format_utf8 => self.terminal.flags.mouse_format = if (enabled) .utf8 else .x10,
            .mouse_format_sgr => self.terminal.flags.mouse_format = if (enabled) .sgr else .x10,
            .mouse_format_urxvt => self.terminal.flags.mouse_format = if (enabled) .urxvt else .x10,
            .mouse_format_sgr_pixels => self.terminal.flags.mouse_format = if (enabled) .sgr_pixels else .x10,

            .disable_keyboard,
            .insert,
            .send_receive_mode,
            .cursor_keys,
            .slow_scroll,
            .wraparound,
            .cursor_blinking,
            .cursor_visible,
            .reverse_wrap,
            .keypad_keys,
            .backarrow_key_mode,
            .mouse_alternate_scroll,
            .ignore_keypad_with_numlock,
            .alt_esc_prefix,
            .alt_sends_escape,
            .reverse_wrap_extended,
            .bracketed_paste,
            .grapheme_cluster,
            .report_color_scheme,
            => {},
        }
    }

    fn colorOperation(
        self: *Handler,
        requests: *const osc.color.List,
        terminator: osc.Terminator,
    ) !void {
        if (requests.count() == 0) return;

        var stack = std.heap.stackFallback(1024, self.terminal.gpa());
        const alloc = stack.get();
        var response: std.Io.Writer.Allocating = .init(alloc);
        defer response.deinit();
        const writer = &response.writer;

        var it = requests.constIterator(0);
        while (it.next()) |req| {
            switch (req.*) {
                .set => |set| {
                    switch (set.target) {
                        .palette => |i| {
                            self.terminal.flags.dirty.palette = true;
                            self.terminal.colors.palette.set(i, set.color);
                        },
                        .dynamic => |dynamic| switch (dynamic) {
                            .foreground => self.terminal.colors.foreground.set(set.color),
                            .background => self.terminal.colors.background.set(set.color),
                            .cursor => self.terminal.colors.cursor.set(set.color),
                            .pointer_foreground,
                            .pointer_background,
                            .tektronix_foreground,
                            .tektronix_background,
                            .highlight_background,
                            .tektronix_cursor,
                            .highlight_foreground,
                            => {},
                        },
                        .special => {},
                    }
                },

                .reset => |target| switch (target) {
                    .palette => |i| {
                        self.terminal.flags.dirty.palette = true;
                        self.terminal.colors.palette.reset(i);
                    },
                    .dynamic => |dynamic| switch (dynamic) {
                        .foreground => self.terminal.colors.foreground.reset(),
                        .background => self.terminal.colors.background.reset(),
                        .cursor => self.terminal.colors.cursor.reset(),
                        .pointer_foreground,
                        .pointer_background,
                        .tektronix_foreground,
                        .tektronix_background,
                        .highlight_background,
                        .tektronix_cursor,
                        .highlight_foreground,
                        => {},
                    },
                    .special => {},
                },

                .reset_palette => {
                    const mask = &self.terminal.colors.palette.mask;
                    var mask_it = mask.iterator(.{});
                    while (mask_it.next()) |i| {
                        self.terminal.flags.dirty.palette = true;
                        self.terminal.colors.palette.reset(@intCast(i));
                    }
                    mask.* = .initEmpty();
                },

                .query => |target| {
                    const c = self.terminal.colorForXterm(target) orelse continue;
                    try writeXtermColorReport(writer, target, c, terminator);
                },

                .reset_special => {},
            }
        }

        if (response.written().len > 0) {
            const resp = try response.toOwnedSliceSentinel(0);
            defer alloc.free(resp);
            self.writePty(resp);
        }
    }

    fn writeXtermColorReport(
        writer: *std.Io.Writer,
        target: osc.color.Target,
        c: color.RGB,
        terminator: osc.Terminator,
    ) !void {
        switch (target) {
            .palette => |i| {
                try writer.print("\x1b]4;{d};", .{i});
                try c.encodeRgb16(writer);
                try writer.writeAll(terminator.string());
            },
            .dynamic => |dynamic| switch (dynamic) {
                .foreground,
                .background,
                .cursor,
                => {
                    try writer.print("\x1b]{d};", .{@intFromEnum(dynamic)});
                    try c.encodeRgb16(writer);
                    try writer.writeAll(terminator.string());
                },
                .pointer_foreground,
                .pointer_background,
                .tektronix_foreground,
                .tektronix_background,
                .highlight_background,
                .tektronix_cursor,
                .highlight_foreground,
                => {},
            },
            .special => {},
        }
    }

    fn kittyColorOperation(
        self: *Handler,
        request: kitty.color.OSC,
    ) !void {
        var stack = std.heap.stackFallback(1024, self.terminal.gpa());
        const alloc = stack.get();
        var response: std.Io.Writer.Allocating = .init(alloc);
        defer response.deinit();
        const writer = &response.writer;

        for (request.list.items) |item| {
            switch (item) {
                .set => |v| switch (v.key) {
                    .palette => |palette| {
                        self.terminal.flags.dirty.palette = true;
                        self.terminal.colors.palette.set(palette, v.color);
                    },
                    .special => |special| switch (special) {
                        .foreground => self.terminal.colors.foreground.set(v.color),
                        .background => self.terminal.colors.background.set(v.color),
                        .cursor => self.terminal.colors.cursor.set(v.color),
                        .selection_foreground,
                        .selection_background,
                        .cursor_text,
                        .visual_bell,
                        .second_transparent_background,
                        => {},
                    },
                },
                .reset => |key| switch (key) {
                    .palette => |palette| {
                        self.terminal.flags.dirty.palette = true;
                        self.terminal.colors.palette.reset(palette);
                    },
                    .special => |special| switch (special) {
                        .foreground => self.terminal.colors.foreground.reset(),
                        .background => self.terminal.colors.background.reset(),
                        .cursor => self.terminal.colors.cursor.reset(),
                        .selection_foreground,
                        .selection_background,
                        .cursor_text,
                        .visual_bell,
                        .second_transparent_background,
                        => {},
                    },
                },
                .query => |key| {
                    const c = self.terminal.colorForKitty(key) orelse {
                        if (!key.hasTerminalQueryColor()) continue;
                        if (response.written().len == 0) try writer.writeAll("\x1b]21");
                        try writer.print(";{f}=", .{key});
                        continue;
                    };

                    if (response.written().len == 0) try writer.writeAll("\x1b]21");
                    try writer.print(";{f}=", .{key});
                    try c.encodeRgb8(writer);
                },
            }
        }

        if (response.written().len > 0) {
            try writer.writeAll(request.terminator.string());
            const resp = try response.toOwnedSliceSentinel(0);
            defer alloc.free(resp);
            self.writePty(resp);
        }
    }

    fn apcEnd(self: *Handler) void {
        const alloc = self.terminal.gpa();
        var cmd = self.apc_handler.end() orelse return;
        defer cmd.deinit(alloc);

        switch (cmd) {
            .kitty => |*kitty_cmd| {
                if (self.terminal.kittyGraphics(
                    alloc,
                    kitty_cmd,
                )) |resp| {
                    // Encode and write the response if we have one.
                    var buf: [1024]u8 = undefined;
                    var writer: std.Io.Writer = .fixed(&buf);
                    resp.encode(&writer) catch return;
                    writer.writeByte(0) catch return;
                    const final = writer.buffered();
                    if (final.len > 3) self.writePty(final[0 .. final.len - 1 :0]);
                }
            },

            .glyph => |*glyph_req| {
                const resp = self.terminal.glyphProtocol(alloc, glyph_req);
                if (resp) |r| {
                    // Glyph responses are short and bounded by the protocol
                    // fields we emit, so this matches the Kitty response
                    // buffer size above with ample headroom.
                    var buf: [apc.glyph.Response.max_wire_bytes]u8 = undefined;
                    var writer: std.Io.Writer = .fixed(&buf);
                    r.formatWire(&writer) catch return;
                    writer.writeByte(0) catch return;
                    const final = writer.buffered();
                    self.writePty(final[0 .. final.len - 1 :0]);
                }
            },
        }
    }

    fn reportDeviceAttributes(self: *Handler, req: device_attributes.Req) void {
        const attrs: device_attributes.Attributes = .{};

        var stack = std.heap.stackFallback(128, self.terminal.gpa());
        const alloc = stack.get();

        var aw: std.Io.Writer.Allocating = .init(alloc);
        defer aw.deinit();

        attrs.encode(req, &aw.writer) catch return;

        const written = aw.toOwnedSliceSentinel(0) catch return;
        defer alloc.free(written);
        self.writePty(written);
    }

    fn deviceStatus(self: *Handler, req: device_status.Request) void {
        switch (req) {
            .operating_status => self.writePty("\x1B[0n"),

            .cursor_position => {
                const pos: struct {
                    x: usize,
                    y: usize,
                } = if (self.terminal.modes.get(.origin)) .{
                    .x = self.terminal.screens.active.cursor.x -| self.terminal.scrolling_region.left,
                    .y = self.terminal.screens.active.cursor.y -| self.terminal.scrolling_region.top,
                } else .{
                    .x = self.terminal.screens.active.cursor.x,
                    .y = self.terminal.screens.active.cursor.y,
                };

                var buf: [64]u8 = undefined;
                const resp = std.fmt.bufPrintZ(&buf, "\x1B[{};{}R", .{
                    pos.y + 1,
                    pos.x + 1,
                }) catch return;
                self.writePty(resp);
            },

            .color_scheme => {
                return;
            },
        }
    }

    fn queryKittyKeyboard(self: *Handler) void {
        // Max response is "\x1b[?31u\x00" (7 bytes): the flags are a u5 (max 31).
        var buf: [32]u8 = undefined;
        const resp = std.fmt.bufPrintZ(&buf, "\x1b[?{}u", .{
            self.terminal.screens.active.kitty_keyboard.current().int(),
        }) catch return;
        self.writePty(resp);
    }

    fn requestMode(self: *Handler, mode: modes.Mode) void {
        const report = self.terminal.modes.getReport(.fromMode(mode));
        self.sendModeReport(report);
    }

    fn requestModeUnknown(self: *Handler, mode_raw: u16, ansi: bool) void {
        const report = self.terminal.modes.getReport(.{
            .value = @truncate(mode_raw),
            .ansi = ansi,
        });
        self.sendModeReport(report);
    }

    fn sendModeReport(self: *Handler, report: modes.Report) void {
        var buf: [modes.Report.max_size + 1]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buf);
        report.encode(&writer) catch |err| {
            std.log.warn("error encoding mode report err={}", .{err});
            return;
        };
        const len = writer.buffered().len;
        buf[len] = 0;
        self.writePty(buf[0..len :0]);
    }

    fn reportSize(self: *Handler, style: csi.SizeReportStyle) void {
        // Almost all size reports will fit in 256 bytes so try that
        // on the stack before falling back to a heap allocation.
        var stack = std.heap.stackFallback(
            256,
            self.terminal.gpa(),
        );
        const alloc = stack.get();

        // Allocating writing to accumulate the response.
        var aw: std.Io.Writer.Allocating = .init(alloc);
        defer aw.deinit();

        // Build the response.
        switch (style) {
            .csi_21_t => {
                const title = self.terminal.getTitle() orelse "";
                aw.writer.print("\x1b]l{s}\x1b\\", .{title}) catch return;
            },

            .csi_14_t, .csi_16_t, .csi_18_t => {
                // TODO: get real size from pty (ideally kept in memory)
                const s: size_report.Size = .{
                    .rows = 0,
                    .columns = 0,
                    .cell_width = 0,
                    .cell_height = 0,
                };
                const report_style: size_report.Style = switch (style) {
                    .csi_14_t => .csi_14_t,
                    .csi_16_t => .csi_16_t,
                    .csi_18_t => .csi_18_t,
                    .csi_21_t => unreachable,
                };
                size_report.encode(
                    &aw.writer,
                    report_style,
                    s,
                ) catch |err| {
                    std.log.warn("error encoding size report err={}", .{err});
                    return;
                };
            },
        }

        const resp = aw.toOwnedSliceSentinel(0) catch return;
        defer alloc.free(resp);
        self.writePty(resp);
    }

    fn windowTitle(self: *Handler, title_raw: []const u8) void {
        // Prevent DoS attacks by limiting title length.
        const max_title_len = 1024;
        const title = if (title_raw.len > max_title_len) title: {
            std.log.warn("title length {d} exceeds max length {d}, truncating", .{
                title_raw.len,
                max_title_len,
            });
            break :title title_raw[0..max_title_len];
        } else title_raw;

        self.terminal.setTitle(title) catch |err| {
            std.log.warn("error setting title err={}", .{err});
            return;
        };
    }

    fn reportPwd(self: *Handler, url_raw: []const u8) void {
        // Prevent DoS attacks by limiting url length. Headroom for
        // Linux PATH_MAX (4096) plus URI scheme/host and percent-encoding.
        const max_url_len = 4096;
        const url = if (url_raw.len > max_url_len) url: {
            std.log.warn("pwd url length {d} exceeds max length {d}, truncating", .{
                url_raw.len,
                max_url_len,
            });
            break :url url_raw[0..max_url_len];
        } else url_raw;

        // We store the raw payload unparsed. Embedders read it via
        // getPwd() and are responsible for decoding any URI scheme.
        self.terminal.setPwd(url) catch |err| {
            std.log.warn("error setting pwd err={}", .{err});
            return;
        };
    }

    fn reportXtversion(self: *Handler) void {
        const version = "zmx 0.6.0";
        var buf: [288]u8 = undefined;
        const resp = std.fmt.bufPrintZ(
            &buf,
            "\x1BP>|{s}\x1B\\",
            .{if (version.len > 0) version else "libghostty"},
        ) catch return;
        self.writePty(resp);
    }

    // TODO: forward this to the real pty
    inline fn writePty(self: *Handler, data: [:0]const u8) void {
        _ = self;
        _ = data;
    }
};
