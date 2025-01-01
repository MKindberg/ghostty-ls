const std = @import("std");
const types = @import("lsp").types;
const Option = @import("main.zig").Option;
const CompletionItem = types.CompletionItem;

pub fn keywords(arena: std.mem.Allocator, options: std.StringHashMap(Option)) ?[]CompletionItem {
    var completions = std.ArrayList(CompletionItem).init(arena);

    var opt_it = options.iterator();
    while (opt_it.next()) |opt| {
        completions.append(.{
            .label = opt.key_ptr.*,
            .kind = .Keyword,
            .documentation = opt.value_ptr.comment,
        }) catch return null;
    }

    return completions.items;
}

pub fn fonts(arena: std.mem.Allocator) ?[]CompletionItem {
    var completions = std.ArrayList(CompletionItem).init(arena);

    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-fonts" },
        .max_output_bytes = 50_000,
    }) catch return null;

    var lines = std.mem.split(u8, res.stdout, "\n");
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == ' ') continue;
        completions.append(.{
            .label = line,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn themes(arena: std.mem.Allocator) ?[]CompletionItem {
    var completions = std.ArrayList(CompletionItem).init(arena);

    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-themes", "--plain" },
        .max_output_bytes = 30_000,
    }) catch return null;

    var lines = std.mem.split(u8, res.stdout, "\n");
    while (lines.next()) |line| {
        const end = std.mem.lastIndexOf(u8, line, " (resources)") orelse line.len;
        completions.append(.{
            .label = line[0..end],
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}
