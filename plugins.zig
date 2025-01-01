const std = @import("std");

const editorgen = @import("lsp_plugins");

pub fn main() !void {
    var info = editorgen.ServerInfo{
        .name = "ghostty-ls",
        .description = "Help with writing ghostty configuration",
        .publisher = "mkindberg",
        .languages = &[_][]const u8{"ghostty"},
        .repository = "https://github.com/mkindberg/ghostty-ls",
        .source_id = "pkg:github/mkindberg/ghostty-ls",
        .license = "MIT",
    };
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    try editorgen.generate(allocator, info);
    info.languages = &[_][]const u8{};
    try editorgen.generateMasonRegistry(allocator, info);
}
