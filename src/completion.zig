const std = @import("std");

const types = @import("lsp").types;
const CompletionItem = types.CompletionItem;

const parser = @import("parser.zig");

pub fn keywords(allocator: std.mem.Allocator, options: parser.OptionsMap) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(allocator);

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

pub fn fonts(allocator: std.mem.Allocator, font_list: parser.Fonts) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(allocator);

    for (font_list.list.items) |f| {
        completions.append(.{
            .label = f,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn themes(allocator: std.mem.Allocator, theme_list: parser.Themes) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(allocator);

    for (theme_list.list.items) |t| {
        completions.append(.{
            .label = t,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn actions(allocator: std.mem.Allocator, action_list: parser.Actions) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(allocator);

    for (action_list.list.items) |a| {
        completions.append(.{
            .label = a,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}

pub fn colors(allocator: std.mem.Allocator, color_map: parser.Colors) ?[]CompletionItem {
    var completions = std.array_list.Managed(CompletionItem).init(allocator);

    var it = color_map.map.iterator();
    while (it.next()) |c| {
        completions.append(.{
            .label = c.key_ptr.*,
            .detail = c.value_ptr.*,
            .kind = .Value,
        }) catch return null;
    }

    return completions.items;
}
