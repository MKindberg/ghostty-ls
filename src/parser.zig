const std = @import("std");

const lsp = @import("lsp");

pub const Config = struct {
    config: std.ArrayList(ConfigItem),
    allocator: std.mem.Allocator,

    pub const Value = struct {
        data: []const u8,
        range: lsp.types.Range,
    };

    pub const ConfigItem = struct {
        key: Value,
        value: Value,
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .config = .empty,
            .allocator = allocator,
        };
    }

    pub fn update(self: *Self, doc: lsp.Document) void {
        self.config.clearRetainingCapacity();
        var lines = std.mem.splitScalar(u8, doc.text, '\n');

        var line_num = 0;
        while (lines.next()) |l| : (line_num += 1) {
            const line = std.mem.trim(u8, l, " ");
            if (line.len == 0 or line[0] == '#') continue;

            const split_idx = std.mem.indexOfScalar(u8, l, '=') orelse continue;
            const key = std.mem.trim(u8, l[0..split_idx], " ");
            const key_start = std.mem.indexOf(u8, l, key).?;
            const value = std.mem.trim(u8, l[split_idx..], " ");
            const value_start = std.mem.indexOfPos(u8, l, value).?;
            self.config.append(self.allocator, .{
                .key = .{
                    .data = key,
                    .range = .{
                        .start = .{
                            .line = line_num,
                            .character = key_start,
                        },
                        .end = .{
                            .line = line_num,
                            .character = key_start + key.len,
                        },
                    },
                },
                .value = .{
                    .data = value,
                    .range = .{
                        .start = .{
                            .line = line_num,
                            .character = value_start,
                        },
                        .end = .{
                            .line = line_num,
                            .character = value_start + value.len,
                        },
                    },
                },
            });
        }
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit(self.allocator);
    }
};

pub const Colors = struct {
    list: std.ArrayList(Color),
    allocator: std.mem.Allocator,

    pub const Color = struct {
        name: []const u8,
        code: []const u8,
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "ghostty", "+list-colors" },
            .max_output_bytes = 50_000,
        });

        var colors = std.ArrayList(Color).initCapacity(allocator, std.mem.count(u8, res.stdout, "\n")) catch unreachable;
        var lines = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \n"), '\n');
        while (lines.next()) |line| {
            var parts = std.mem.splitSequence(u8, line, " = ");
            colors.appendAssumeCapacity(.{
                .name = parts.next() orelse continue,
                .code = parts.next() orelse continue,
            });
        }

        return Self{ .list = colors, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }
};

pub const Actions = struct {
    list: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "ghostty", "+list-actions" },
            .max_output_bytes = 5000,
        });

        var actions = std.ArrayList([]const u8).initCapacity(allocator, std.mem.count(u8, res.stdout, "\n") + 1) catch unreachable;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            actions.appendAssumeCapacity(line);
        }

        return Self{ .list = actions, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }
};

pub const Themes = struct {
    list: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "ghostty", "+list-themes", "--plain" },
            .max_output_bytes = 30_000,
        });

        var themes = std.ArrayList([]const u8).initCapacity(allocator, std.mem.count(u8, res.stdout, "\n") + 1) catch unreachable;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const end = std.mem.lastIndexOf(u8, line, " (resources)") orelse line.len;
            themes.appendAssumeCapacity(line[0..end]);
        }

        return Self{
            .list = themes,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }
};

pub const Fonts = struct {
    list: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "ghostty", "+list-fonts" },
            .max_output_bytes = 50_000,
        });

        var fonts = std.ArrayList([]const u8).initCapacity(allocator, std.mem.count(u8, res.stdout, "\n") + 1) catch unreachable;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] == ' ') continue;
            fonts.appendAssumeCapacity(line);
        }

        return Self{
            .list = fonts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit(self.allocator);
    }
};

pub const OptionsMap = struct {
    map: std.StringHashMap(Option),
    allocator: std.mem.Allocator,

    pub const Option = struct {
        name: []const u8,
        comment: []const u8,
        default: []const u8,
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "ghostty", "+show-config", "--default", "--docs" },
            .max_output_bytes = 500_000,
        });
        defer allocator.free(res.stdout);
        defer allocator.free(res.stderr);

        var opt = std.StringHashMap(Option).init(allocator);
        errdefer opt.deinit();

        var comment_buf = std.array_list.Managed([]const u8).init(allocator);
        defer comment_buf.deinit();
        var comment: []u8 = "";

        var it = std.mem.splitScalar(u8, res.stdout, '\n');
        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) {
                comment_buf.append(line[2..]) catch unreachable;
                continue;
            }

            if (comment_buf.items.len > 0) {
                comment = std.mem.join(allocator, "\n", comment_buf.items) catch unreachable;
                comment_buf.clearRetainingCapacity();
            }
            if (std.mem.indexOf(u8, line, "=")) |idx| {
                const name = allocator.dupe(u8, std.mem.trim(u8, line[0..idx], " ")) catch unreachable;
                const default = allocator.dupe(u8, std.mem.trim(u8, line[idx..], " ")) catch unreachable;

                const o = Option{ .name = name, .comment = comment, .default = default };

                opt.put(name, o) catch unreachable;
            }
        }
        return Self{
            .map = opt,
            .allocator = allocator,
        };
    }

    pub fn get(self: Self, key: []const u8) ?Option {
        return self.map.get(key);
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.valueIterator();
        while (it.next()) |v| {
            self.allocator.free(v.name);
            self.allocator.free(v.comment);
            self.allocator.free(v.default);
        }
        self.map.deinit();
    }
};
