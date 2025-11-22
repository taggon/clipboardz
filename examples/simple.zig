const std = @import("std");
const clipboard = @import("clipboardz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cb = clipboard.Clipboardz.init(allocator);

    const text_to_write = "Hello from Zig Clipboard!";
    try cb.writeText(text_to_write);
    std.debug.print("Wrote to clipboard: {s}\n", .{text_to_write});

    const read_back = try cb.readText();
    defer allocator.free(read_back);
    std.debug.print("Read from clipboard: {s}\n", .{read_back});

    // HTML Example
    const html_content = "<h1>Hello from Zig HTML!</h1>";
    try cb.writeHTML(html_content);
    std.debug.print("Wrote HTML to clipboard: {s}\n", .{html_content});

    if (cb.has(.html)) {
        const html_read = try cb.readHTML();
        defer allocator.free(html_read);
        std.debug.print("Read HTML from clipboard: {s}\n", .{html_read});
    }
}
