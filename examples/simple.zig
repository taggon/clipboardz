const std = @import("std");
const clipboard = @import("clipboardz");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cb = clipboard.Clipboardz.init(allocator);

    const text_to_write = "Hello from Zig Clipboard!";
    try cb.writeText(text_to_write);
    std.debug.print("Wrote to clipboard: {s}\n", .{text_to_write});

    // Wait for clipboard server to be ready (especially important on Linux with xvfb)
    sleepMs(200);

    const read_back = try cb.readText();
    defer allocator.free(read_back);
    std.debug.print("Read from clipboard: {s}\n", .{read_back});

    // HTML Example
    const html_content = "<h1>Hello from Zig HTML!</h1>";
    try cb.writeHTML(html_content);
    std.debug.print("Wrote HTML to clipboard: {s}\n", .{html_content});

    // Wait for clipboard server to be ready
    sleepMs(200);

    if (cb.has(.html)) {
        const html_read = try cb.readHTML();
        defer allocator.free(html_read);
        std.debug.print("Read HTML from clipboard: {s}\n", .{html_read});
    }
}

fn sleepMs(ms: u64) void {
    if (builtin.os.tag == .linux) {
        const timespec = std.os.linux.timespec{
            .tv_sec = 0,
            .tv_nsec = @as(isize, @intCast(ms * 1_000_000)),
        };
        _ = std.os.linux.nanosleep(&timespec, null);
    } else if (builtin.os.tag == .macos) {
        const c = @cImport(@cInclude("unistd.h"));
        _ = c.usleep(@intCast(ms * 1000));
    } else if (builtin.os.tag == .windows) {
        const c = @cImport(@cInclude("windows.h"));
        c.Sleep(@intCast(ms));
    }
}
