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
            const message = std.fmt.allocPrint(p.arena, "Unknown key \"{s}\"", .{c.key.name}) catch unreachable;
            diagnostics.append(p.arena, .{ .message = message, .range = c.key.range, .severity = .Error }) catch unreachable;
        }
    }
    p.context.server.writeResponse(p.arena, lsp.types.Notification.PublishDiagnostics{ .params = .{
        .uri = p.context.document.uri,
        .diagnostics = diagnostics.items,
    } }) catch unreachable;
}

fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    const word = p.context.document.getWord(p.position, "\n =") orelse return null;
    const opt = options.get(word) orelse return null;

    return std.fmt.allocPrint(p.arena, "# {s}\n\n{s}\n\nDefault: {s}", .{ opt.name, opt.comment, opt.default }) catch unreachable;
}

fn handleRangeFormat(p: Lsp.RangeFormattingParameters) ?[]const lsp.types.TextEdit {
    const doc = p.context.document;
    const offset = doc.posToIdx(p.range.start).?;
    const t = p.context.document.getRange(p.range).?;
    const edits = formatText(p.arena, t);
    for (edits) |*e| {
        const start = lsp.Document.posToIdxText(t, e.range.start).?;
        const end = lsp.Document.posToIdxText(t, e.range.start).?;
        e.range.start = doc.idxToPos(offset + start).?;
        e.range.end = doc.idxToPos(offset + end).?;
    }
    return edits;
}

fn handleFormat(p: Lsp.FormattingParameters) ?[]const lsp.types.TextEdit {
    return formatText(p.arena, p.context.document.text);
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
fn formatText(arena: std.mem.Allocator, text: []const u8) []lsp.types.TextEdit {
    var edits = std.array_list.Managed(lsp.types.TextEdit).init(arena);
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

fn handleCompletion(p: Lsp.CompletionParameters) ?lsp.types.CompletionList {
    const line = std.mem.trim(u8, p.context.document.getLine(p.position).?, " ");
    if (std.mem.startsWith(u8, line, "#")) return null;

    const items = items: {
        if (std.mem.indexOf(u8, line[0..p.position.character], " ") == null and
            std.mem.indexOf(u8, line[0..p.position.character], "=") == null)
        {
            break :items completion.keywords(p.arena, options) orelse return null;
        } else if (std.mem.indexOf(u8, line[0..p.position.character], "=") != null) {
            if (std.mem.startsWith(u8, line, "font-family")) {
                break :items completion.fonts(p.arena, fonts) orelse return null;
            }
            if (std.mem.startsWith(u8, line, "theme")) {
                break :items completion.themes(p.arena, themes) orelse return null;
            }
            if (std.mem.startsWith(u8, line, "keybind") and
                std.mem.containsAtLeast(u8, line[0..p.position.character], 2, "="))
            {
                break :items completion.actions(p.arena, actions) orelse return null;
            }
            if (std.mem.startsWith(u8, line, "background") or
                std.mem.startsWith(u8, line, "foreground") or
                std.mem.startsWith(u8, line, "selection-foreground") or
                std.mem.startsWith(u8, line, "selection-background") or
                std.mem.startsWith(u8, line, "cursor-color") or
                std.mem.startsWith(u8, line, "cursor-text") or
                std.mem.startsWith(u8, line, "unfocused-split-fill") or
                std.mem.startsWith(u8, line, "macos-icon-ghost-color") or
                std.mem.startsWith(u8, line, "macos-icon-screen-color") or
                (std.mem.startsWith(u8, line, "palette") and std.mem.containsAtLeast(u8, line[0..p.position.character], 2, "=")))
            {
                std.debug.print("complete color\n", .{});
                break :items completion.colors(p.arena, colors) orelse return null;
            }
            return null;
        } else return null;
    };

    return .{ .items = items };
}

fn handleColor(p: Lsp.ColorParameters) Lsp.ColorReturn {
    const doc: lsp.Document = p.context.document;
    var color_info = std.array_list.Managed(lsp.types.ColorInformation).init(p.arena);
    for (colors.list.items) |c| {
        var found = doc.find(c.name);
        while (found.next()) |f| {
            color_info.append(
                .{
                    .color = lsp.types.Color.fromHex(c.code) orelse continue,
                    .range = f,
                },
            ) catch unreachable;
        }
    }
    return color_info.items;
}
