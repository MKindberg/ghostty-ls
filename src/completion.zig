const std = @import("std");
const types = @import("lsp").types;
const Option = @import("main.zig").Option;
const CompletionItem = types.CompletionItem;

pub fn keywords(arena: std.mem.Allocator, options: std.StringHashMap(Option)) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

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
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-fonts" },
        .max_output_bytes = 50_000,
    }) catch return null;

    var lines = std.mem.splitScalar(u8, res.stdout, '\n');
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
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-themes", "--plain" },
        .max_output_bytes = 30_000,
    }) catch return null;

    var lines = std.mem.splitScalar(u8, res.stdout, '\n');
    while (lines.next()) |line| {
        const end = std.mem.lastIndexOf(u8, line, " (resources)") orelse line.len;
        completions.append(.{
            .label = line[0..end],
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn actions(arena: std.mem.Allocator) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-actions" },
        .max_output_bytes = 5000,
    }) catch return null;

    var lines = std.mem.splitScalar(u8, res.stdout, '\n');
    while (lines.next()) |line| {
        completions.append(.{
            .label = line,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub const Color = struct {
    name: []const u8,
    code: []const u8,
};

pub fn colorList(arena: std.mem.Allocator) ?[]const Color {
    const res = std.process.Child.run(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "ghostty", "+list-colors" },
        .max_output_bytes = 50_000,
    }) catch return null;

    var list = std.ArrayList(Color).initCapacity(arena, std.mem.count(u8, res.stdout, "\n")) catch return null;
    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \n"), '\n');
    while (lines.next()) |line| {
        var parts = std.mem.splitSequence(u8, line, " = ");
        list.appendAssumeCapacity(.{
            .name = parts.next() orelse return list.items,
            .code = parts.next() orelse return list.items,
        });
    }

    return list.items;
}

pub fn colors(arena: std.mem.Allocator) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    const color_list = colorList(arena) orelse return null;

    for (color_list) |c| {
        completions.append(.{
            .label = c.name,
            .detail = c.code,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}
