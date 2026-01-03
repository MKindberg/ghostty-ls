const std = @import("std");

const types = @import("lsp").types;
const CompletionItem = types.CompletionItem;

const parser = @import("parser.zig");

pub fn keywords(arena: std.mem.Allocator, options: parser.OptionsMap) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    var opt_it = options.map.iterator();
    while (opt_it.next()) |opt| {
        completions.append(.{
            .label = opt.key_ptr.*,
            .kind = .Keyword,
            .documentation = opt.value_ptr.comment,
        }) catch return null;
    }

    return completions.items;
}

pub fn fonts(arena: std.mem.Allocator, font_list: parser.Fonts) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    for (font_list.list.items) |f| {
        completions.append(.{
            .label = f,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn themes(arena: std.mem.Allocator, theme_list: parser.Themes) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    for (theme_list.list.items) |t| {
        completions.append(.{
            .label = t,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn actions(arena: std.mem.Allocator, action_list: parser.Actions) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    for (action_list.list.items) |a| {
        completions.append(.{
            .label = a,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn colors(arena: std.mem.Allocator, color_list: parser.Colors) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(arena);

    for (color_list.list.items) |c| {
        completions.append(.{
            .label = c.name,
            .detail = c.code,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}
