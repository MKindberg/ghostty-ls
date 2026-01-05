const std = @import("std");
const builtin = @import("builtin");

const lsp = @import("lsp");

const completion = @import("completion.zig");
const parser = @import("parser.zig");

pub const std_options = std.Options{ .log_level = if (builtin.mode == .Debug) .debug else .info, .logFn = lsp.log };

const Lsp = lsp.Lsp(.{ .state_type = parser.Config });

pub const Option = struct {
    name: []const u8,
    comment: []const u8,
    default: []const u8,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var actions: parser.Actions = undefined;
var colors: parser.Colors = undefined;
var fonts: parser.Fonts = undefined;
var options: parser.OptionsMap = undefined;
var themes: parser.Themes = undefined;

pub fn main() !u8 {
    actions = try parser.Actions.init(allocator);
    defer actions.deinit();
    colors = try parser.Colors.init(allocator);
    defer colors.deinit();
    fonts = try parser.Fonts.init(allocator);
    defer fonts.deinit();
    options = try parser.OptionsMap.init(allocator);
    defer options.deinit();
    themes = try parser.Themes.init(allocator);
    defer themes.deinit();

    const server_info = lsp.types.ServerInfo{
        .name = "ghostty-ls",
        .version = "0.1.0",
    };

    var in_buffer: [4096]u8 = undefined;
    var out_buffer: [4096]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&in_buffer);
    var stdout = std.fs.File.stdout().writer(&out_buffer);

    var server = Lsp.init(allocator, &stdin.interface, &stdout.interface, server_info);
    defer server.deinit();

    return server.start(setup);
}

fn setup(p: Lsp.SetupParameters) void {
    p.server.registerDocOpenCallback(handleOpen);
    p.server.registerDocChangeCallback(handleChange);
    if (p.initialize.capabilities.textDocument.?.hover != null)
        p.server.registerHoverCallback(handleHover);
    if (p.initialize.capabilities.textDocument.?.formatting != null)
        p.server.registerFormattingCallback(handleFormat);
    if (p.initialize.capabilities.textDocument.?.rangeFormatting != null)
        p.server.registerRangeFormattingCallback(handleRangeFormat);
    if (p.initialize.capabilities.textDocument.?.completion != null)
        p.server.registerCompletionCallback(handleCompletion);
    if (p.initialize.capabilities.textDocument.?.colorProvider != null)
        p.server.registerColorCallback(handleColor);
    p.server.registerDocCloseCallback(handleClose);
}

fn handleOpen(p: Lsp.OpenDocumentParameters) Lsp.OpenDocumentReturn {
    p.context.state = parser.Config.init(allocator);
    p.context.state.?.update(p.context.document);
}

fn handleClose(p: Lsp.CloseDocumentParameters) Lsp.CloseDocumentReturn {
    p.context.state.?.deinit();
}
fn handleChange(p: Lsp.ChangeDocumentParameters) Lsp.ChangeDocumentReturn {
    var config: parser.Config = p.context.state.?;
    config.update(p.context.document);

    var diagnostics: std.ArrayList(lsp.types.Diagnostic) = .empty;
    for (config.config.items) |c| {
        if (!options.map.contains(c.key.name)) {
            const message = std.fmt.allocPrint(p.allocator, "Unknown key \"{s}\"", .{c.key.name}) catch unreachable;
            diagnostics.append(p.allocator, .{ .message = message, .range = c.key.range, .severity = .Error }) catch unreachable;
        }
        if (c.value != null and c.value.? == .keybind) {
            if (c.value.?.keybind.action) |a| {
                if (!actions.map.contains(a.name)) {
                    const message = std.fmt.allocPrint(p.allocator, "Unknown action \"{s}\"", .{a.name}) catch unreachable;
                    diagnostics.append(p.allocator, .{ .message = message, .range = a.range, .severity = .Error }) catch unreachable;
                }
            }
        }
    }
    p.context.server.writeResponse(p.allocator, lsp.types.Notification.PublishDiagnostics{ .params = .{
        .uri = p.context.document.uri,
        .diagnostics = diagnostics.items,
    } }) catch unreachable;
}

fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    const line = p.context.document.getLine(p.position).?;
    const word = p.context.document.getWord(p.position, "\n =:") orelse return null;
    const equal = std.mem.indexOf(u8, line, "=") orelse line.len;
    if (p.position.character < equal) if (options.get(word)) |opt| {
        return std.fmt.allocPrint(p.allocator, "# {s}\n\n{s}\n\nDefault: {s}", .{ opt.name, opt.comment, opt.default }) catch unreachable;
    };
    const equal2 = std.mem.indexOfPos(u8, line, equal + 1, "=") orelse line.len;
    const colon = std.mem.indexOfPos(u8, line, equal2, ":") orelse line.len;
    if (equal2 < p.position.character and p.position.character < colon) if (actions.map.get(word)) |a| {
        return std.fmt.allocPrint(p.allocator, "# {s}\n\n{s}", .{ word, a }) catch unreachable;
    };
    return null;
}

fn handleRangeFormat(p: Lsp.RangeFormattingParameters) ?[]const lsp.types.TextEdit {
    const doc = p.context.document;
    const offset = doc.posToIdx(p.range.start).?;
    const t = p.context.document.getRange(p.range).?;
    const edits = formatText(p.allocator, t);
    for (edits) |*e| {
        const start = lsp.Document.posToIdxText(t, e.range.start).?;
        const end = lsp.Document.posToIdxText(t, e.range.start).?;
        e.range.start = doc.idxToPos(offset + start).?;
        e.range.end = doc.idxToPos(offset + end).?;
    }
    return edits;
}

fn handleFormat(p: Lsp.FormattingParameters) ?[]const lsp.types.TextEdit {
    return formatText(p.allocator, p.context.document.text);
}

fn insertMissingSpace(line: []const u8, line_num: usize, idx: usize) ?lsp.types.TextEdit {
    if (line[idx] != ' ') {
        return .{
            .range = singleCharRange(line_num, idx),
            .newText = " ",
        };
    }
    return null;
}
fn singleCharRange(line: usize, char: usize) lsp.types.Range {
    return .{
        .start = .{ .line = line, .character = char },
        .end = .{ .line = line, .character = char },
    };
}
fn formatText(alloc: std.mem.Allocator, text: []const u8) []lsp.types.TextEdit {
    var edits = std.array_list.Managed(lsp.types.TextEdit).init(alloc);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var l: usize = 0;
    while (lines.next()) |line| : (l += 1) {
        if (std.mem.indexOf(u8, line, "#")) |idx| {
            // Comments are only valid on their own line
            if (std.mem.trim(u8, line[0..idx], " ").len != 0) continue;
            // Don't format empty comments
            if (idx == line.len - 1) continue;
            // Don't insert spaces in #########
            if (line[idx + 1] == '#') continue;
            if (line[idx + 1] != ' ') {
                edits.append(
                    .{
                        .range = singleCharRange(l, idx + 1),
                        .newText = " ",
                    },
                ) catch unreachable;
            }
            continue;
        }
        if (std.mem.indexOf(u8, line, "=")) |idx| {
            if (idx == 0) continue;
            if (line[idx - 1] != ' ') {
                edits.append(
                    .{
                        .range = singleCharRange(l, idx),
                        .newText = " ",
                    },
                ) catch unreachable;
            }

            if (idx == line.len - 1) continue;
            if (line[idx + 1] != ' ') {
                edits.append(
                    .{
                        .range = singleCharRange(l, idx + 1),
                        .newText = " ",
                    },
                ) catch unreachable;
            }
        }
    }
    return edits.items;
}

const color_options = [_][]const u8{
    "background",
    "cursor-color",
    "cursor-text",
    "foreground",
    "macos-icon-ghost-color",
    "macos-icon-screen-color",
    "palette",
    "selection-background",
    "selection-foreground",
    "unfocused-split-fill",
};

fn handleCompletion(p: Lsp.CompletionParameters) ?lsp.types.CompletionList {
    const line = std.mem.trim(u8, p.context.document.getLine(p.position).?, " ");
    if (std.mem.startsWith(u8, line, "#")) return null;

    const items = items: {
        if (std.mem.indexOf(u8, line[0..p.position.character], " ") == null and
            std.mem.indexOf(u8, line[0..p.position.character], "=") == null)
        {
            break :items completion.keywords(p.allocator, options) orelse return null;
        } else if (std.mem.indexOf(u8, line[0..p.position.character], "=")) |idx| {
            const keyword = std.mem.trim(u8, line[0..idx], " ");
            if (std.mem.eql(u8, keyword, "font-family")) {
                break :items completion.fonts(p.allocator, fonts) orelse return null;
            }
            if (std.mem.eql(u8, keyword, "theme")) {
                break :items completion.themes(p.allocator, themes) orelse return null;
            }
            if (std.mem.eql(u8, keyword, "keybind") and
                std.mem.containsAtLeast(u8, line[0..p.position.character], 2, "="))
            {
                break :items completion.actions(p.allocator, actions) orelse return null;
            }
            for (color_options) |c| {
                if (std.mem.eql(u8, keyword, c)) {
                    break :items completion.colors(p.allocator, colors) orelse return null;
                }
            }
            return null;
        } else return null;
    };

    return .{ .items = items };
}

fn handleColor(p: Lsp.ColorParameters) Lsp.ColorReturn {
    const config: parser.Config = p.context.state.?;
    var color_info = std.array_list.Managed(lsp.types.ColorInformation).init(p.allocator);
    for (config.config.items) |c| {
        // Only run for options in color_options
        var found = false;
        for (color_options) |co| {
            if (std.mem.eql(u8, co, c.key.name)) found = true;
        }
        if(!found) continue;

        if(c.value == null) continue;
        if (lsp.types.Color.fromHex(c.value.?.other.name)) |color| {
            color_info.append(
                .{
                    .color = color,
                    .range = c.value.?.other.range,
                },
            ) catch unreachable;
            continue;
        }
        for (color_options) |cc| {
            if (!std.mem.eql(u8, cc, c.key.name)) continue;
            if (colors.map.get(c.value.?.other.name)) |color| {
                color_info.append(
                    .{
                        .color = lsp.types.Color.fromHex(color) orelse continue,
                        .range = c.value.?.other.range,
                    },
                ) catch unreachable;
            }
            break;
        }
    }
    return color_info.items;
}
