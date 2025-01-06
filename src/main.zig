const std = @import("std");
const lsp = @import("lsp");
const builtin = @import("builtin");
const completion = @import("completion.zig");

pub const std_options = .{ .log_level = if (builtin.mode == .Debug) .debug else .info, .logFn = lsp.log };

const Lsp = lsp.Lsp(void);

pub const Option = struct {
    name: []const u8,
    comment: []const u8,
    default: []const u8,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var options: std.StringHashMap(Option) = undefined;

pub fn main() !u8 {
    options = try createOptionsMap(allocator);
    const server_data = lsp.types.ServerData{
        .serverInfo = .{ .name = "ghostty-ls", .version = "0.1.0" },
    };
    var server = Lsp.init(allocator, server_data);
    defer server.deinit();

    server.registerHoverCallback(handleHover);
    server.registerFormattingCallback(handleFormat);
    server.registerRangeFormattingCallback(handleRangeFormat);
    server.registerCompletionCallback(handleCompletion);

    return server.start();
}

fn createOptionsMap(alloc: std.mem.Allocator) !std.StringHashMap(Option) {
    const res = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "ghostty", "+show-config", "--default", "--docs" },
        .max_output_bytes = 100_000,
    });
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);

    var opt = std.StringHashMap(Option).init(alloc);
    errdefer opt.deinit();

    var comment_buf = std.ArrayList([]const u8).init(alloc);
    defer comment_buf.deinit();
    var comment: []u8 = "";

    var it = std.mem.split(u8, res.stdout, "\n");
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "#")) {
            try comment_buf.append(line[2..]);
            continue;
        }

        if (comment_buf.items.len > 0) {
            comment = try std.mem.join(alloc, "\n", comment_buf.items);
            comment_buf.clearRetainingCapacity();
        }
        if (std.mem.indexOf(u8, line, "=")) |idx| {
            const name = try alloc.dupe(u8, std.mem.trim(u8, line[0..idx], " "));
            const default = try alloc.dupe(u8, std.mem.trim(u8, line[idx..], " "));

            const o = Option{ .name = name, .comment = comment, .default = default };

            try opt.put(name, o);
        }
    }
    return opt;
}
fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    const word = p.context.document.getWord(p.position, "\n =") orelse return null;
    const opt = options.get(word) orelse return null;

    return std.fmt.allocPrint(p.arena, "# {s}\n\n{s}\n\nDefault: {s}", .{ opt.name, opt.comment, opt.default }) catch unreachable;
}

fn handleRangeFormat(p: Lsp.RangeFormattingParameters) ?[]const lsp.types.TextEdit {
    const doc = p.context.document;
    const offset = lsp.Document.posToIdx(doc.text, p.range.start).?;
    const t = p.context.document.getRange(p.range).?;
    const edits = formatText(p.arena, t);
    for (edits) |*e| {
        const start = lsp.Document.posToIdx(t, e.range.start).?;
        const end = lsp.Document.posToIdx(t, e.range.start).?;
        e.range.start = lsp.Document.idxToPos(doc.text, offset + start).?;
        e.range.end = lsp.Document.idxToPos(doc.text, offset + end).?;
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
    var edits = std.ArrayList(lsp.types.TextEdit).init(arena);
    var lines = std.mem.split(u8, text, "\n");
    var l: usize = 0;
    while (lines.next()) |line| : (l += 1) {
        if (std.mem.indexOf(u8, line, "#")) |idx| {
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
    const line = p.context.document.getLine(p.position).?;
    if (std.mem.startsWith(u8, line, "#")) return null;

    if (std.mem.indexOf(u8, line[0..p.position.character], " ") == null and
        std.mem.indexOf(u8, line[0..p.position.character], "=") == null)
    {
        const items = completion.keywords(p.arena, options) orelse return null;
        return .{ .items = items };
    }
    if (std.mem.indexOf(u8, line[0..p.position.character], "=") != null) {
        if (std.mem.startsWith(u8, line, "font-family")) {
            const items = completion.fonts(p.arena) orelse return null;
            return .{ .items = items };
        }
        if (std.mem.startsWith(u8, line, "theme")) {
            const items = completion.themes(p.arena) orelse return null;
            return .{ .items = items };
        }
        if (std.mem.startsWith(u8, line, "keybind") and
            std.mem.containsAtLeast(u8, line[0..p.position.character], 2, "="))
        {
            const items = completion.actions(p.arena) orelse return null;
            return .{ .items = items };
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
            const items = completion.colors(p.arena) orelse return null;
            return .{ .items = items };
        }
    }

    return null;
}
