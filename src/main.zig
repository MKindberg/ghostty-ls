const std = @import("std");
const lsp = @import("lsp");
const builtin = @import("builtin");

pub const std_options = .{ .log_level = if (builtin.mode == .Debug) .debug else .info, .logFn = lsp.log };

const Lsp = lsp.Lsp(void);

const Option = struct {
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
fn handleHover(arena: std.mem.Allocator, context: *Lsp.Context, position: lsp.types.Position) ?[]const u8 {
    const word = context.document.getWord(position, "\n =") orelse return null;
    const opt = options.get(word) orelse return null;

    return std.fmt.allocPrint(arena, "# {s}\n\n{s}\n\nDefault: {s}", .{ opt.name, opt.comment, opt.default }) catch unreachable;
}
