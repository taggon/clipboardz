const std = @import("std");
const clipboard = @import("clipboardz");
const builtin = @import("builtin");

// Windows Sleep function
extern "kernel32" fn Sleep(dwMilliseconds: c_ulong) callconv(.winapi) void;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cb = clipboard.Clipboardz.init(allocator);

    const text_to_write = "Hello from Zig Clipboard!";
    try cb.writeText(text_to_write);
    std.debug.print("Wrote to clipboard: {s}\n", .{text_to_write});

    // Add a short delay just in case to avoid race conditions with the clipboard server.
    // (e.g. xvfb on Linux).
    sleepMs(200);

    const read_back = try cb.readText();
    defer allocator.free(read_back);
    std.debug.print("Read from clipboard: {s}\n", .{read_back});

    // HTML Example
    const html_content = "<h1>Hello from Zig HTML!</h1>";
    try cb.writeHTML(html_content);
    std.debug.print("Wrote HTML to clipboard: {s}\n", .{html_content});

    // Add a short delay just in case to avoid race conditions with the clipboard server.
    sleepMs(200);

    if (cb.has(.html)) {
        const html_read = try cb.readHTML();
        defer allocator.free(html_read);
        std.debug.print("Read HTML from clipboard: {s}\n", .{html_read});
    }
}

fn sleepMs(ms: u64) void {
    if (builtin.os.tag == .windows) {
        Sleep(@intCast(ms));
    } else {
        // Use std.posix.nanosleep for POSIX systems (Linux, macOS)
        std.posix.nanosleep(0, @intCast(ms * 1_000_000));
    }
}
