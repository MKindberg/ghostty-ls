const std = @import("std");

const lsp = @import("lsp");

pub const Config = struct {
    config: std.ArrayList(ConfigItem),
    allocator: std.mem.Allocator,

    pub const Item = struct {
        name: []const u8,
        range: lsp.types.Range,
    };
    pub const Value = union(enum) {
        keybind: Keybind,
        other: Item,

        pub const Keybind = struct {
            keys: ?Item = null,
            action: ?Item = null,
            option: ?Item = null,
        };
    };

    pub const ConfigItem = struct {
        key: Item,
        value: ?Value = null,

        fn getItem(line: []const u8, line_num: usize, start: usize, end: usize) Item {
            const name = std.mem.trim(u8, line[start..end], " ");
            const s = std.mem.indexOfPos(u8, line, start, name).?;
            return .{
                .name = name,
                .range = .{
                    .start = .{
                        .line = line_num,
                        .character = s,
                    },
                    .end = .{
                        .line = line_num,
                        .character = s + name.len,
                    },
                },
            };
        }
        pub fn parse(line: []const u8, line_num: usize) ?ConfigItem {
            const l = std.mem.trim(u8, line, " ");
            if (l.len == 0 or l[0] == '#') return null;

            const split_idx = std.mem.indexOfScalar(u8, line, '=') orelse line.len;
            const key = getItem(line, line_num, 0, split_idx);
            if (std.mem.indexOfScalar(u8, line, '=') == null) return .{ .key = key };

            const value = value: {
                if (std.mem.eql(u8, key.name, "keybind")) {
                    var keybind = Value.Keybind{};

                    const split_idx2 = std.mem.indexOfScalarPos(u8, line, split_idx + 1, '=') orelse line.len;
                    keybind.keys = getItem(line, line_num, split_idx + 1, split_idx2);
                    if (std.mem.indexOfScalarPos(u8, line, split_idx + 1, '=') == null) break :value Value{ .keybind = keybind };

                    const split_idx3 = std.mem.indexOfScalarPos(u8, line, split_idx2 + 1, ':') orelse line.len;
                    keybind.action = getItem(line, line_num, split_idx2 + 1, split_idx3);
                    if (std.mem.indexOfScalarPos(u8, line, split_idx2 + 1, ':') == null) break :value Value{ .keybind = keybind };

                    keybind.option = getItem(line, line_num, split_idx3 + 1, line.len);
                    break :value Value{ .keybind = keybind };
                }

                const value = getItem(line, line_num, split_idx + 1, line.len);
                break :value Value{ .other = value };
            };

            return .{
                .key = key,
                .value = value,
            };
        }
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) ?Self {
        return Self{
            .config = .empty,
            .allocator = allocator,
        };
    }

    pub fn update(self: *Self, doc: lsp.Document) void {
        self.config.clearRetainingCapacity();
        var lines = std.mem.splitScalar(u8, doc.text, '\n');

        var line_num: usize = 0;
        while (lines.next()) |line| : (line_num += 1) {
            self.config.append(self.allocator, ConfigItem.parse(line, line_num) orelse continue) catch unreachable;
        }
    }

    pub fn deinit(self: *Self) void {
        self.config.deinit(self.allocator);
    }
};

pub const Colors = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    data: std.process.RunResult,

    pub const Color = struct {
        name: []const u8,
        code: []const u8,
    };

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        const res = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "ghostty", "+list-colors", "--plain" },
        });

        var colors = std.StringHashMap([]const u8).init(allocator);
        colors.ensureTotalCapacity(@intCast(std.mem.count(u8, res.stdout, "\n"))) catch unreachable;
        var lines = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \n"), '\n');
        while (lines.next()) |line| {
            var parts = std.mem.splitSequence(u8, line, " = ");
            colors.putAssumeCapacity(
                parts.next() orelse continue,
                parts.next() orelse continue,
            );
        }

        return Self{ .map = colors, .allocator = allocator, .data = res };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.allocator.free(self.data.stdout);
        self.allocator.free(self.data.stderr);
    }
};

pub const Actions = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        const res = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "ghostty", "+list-actions", "--docs" },
        });
        defer {
            allocator.free(res.stdout);
            allocator.free(res.stderr);
        }

        var actions = std.StringHashMap([]const u8).init(allocator);
        actions.ensureTotalCapacity(@intCast(std.mem.count(u8, res.stdout, ":\n "))) catch unreachable;

        var doc_lines = std.ArrayList([]const u8).initCapacity(allocator, 128) catch unreachable;
        var lines = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \t\n"), '\n');
        var action: []const u8 = undefined;
        while (lines.next()) |line| {
            if (line.len > 0 and line[0] != ' ') {
                if (doc_lines.items.len > 0) {
                    const doc = std.mem.join(allocator, "\n", doc_lines.items) catch unreachable;
                    actions.putAssumeCapacity(action, doc);
                }
                doc_lines.clearRetainingCapacity();
                action = allocator.dupe(u8, line[0 .. line.len - 1]) catch unreachable;
                continue;
            }
            if (line.len > 2)
                doc_lines.appendAssumeCapacity(line[2..])
            else
                doc_lines.appendAssumeCapacity(line);
        }
        const doc = std.mem.join(allocator, "\n", doc_lines.items) catch unreachable;
        actions.putAssumeCapacity(action, doc);

        return Self{ .map = actions, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.iterator();
        while (it.next()) |i| {
            self.allocator.free(i.key_ptr.*);
            self.allocator.free(i.value_ptr.*);
        }
        self.map.deinit();
    }
};

pub const Themes = struct {
    list: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        const res = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "ghostty", "+list-themes", "--plain" },
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
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        const res = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "ghostty", "+list-fonts" },
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
    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        const res = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "ghostty", "+show-config", "--default", "--docs" },
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
