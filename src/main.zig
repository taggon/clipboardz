const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const ClipboardError = types.ClipboardError;
pub const ClipboardContent = types.ClipboardContent;
pub const ClipboardItem = types.ClipboardItem;

const implementation = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("Unsupported OS"),
};

pub const Clipboardz = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Clipboardz {
        return .{ .allocator = allocator };
    }

    pub fn write(self: Clipboardz, content: ClipboardContent, data: []const u8) ClipboardError!void {
        const single = &[_]types.ClipboardItem{.{ .content = content, .data = data }};
        return implementation.writeMultiple(self.allocator, single);
    }

    pub fn writeMultiple(self: Clipboardz, items: []const types.ClipboardItem) ClipboardError!void {
        return implementation.writeMultiple(self.allocator, items);
    }

    pub fn writeText(self: Clipboardz, text: []const u8) ClipboardError!void {
        return self.write(.text, text);
    }

    pub fn writeHTML(self: Clipboardz, html: []const u8) ClipboardError!void {
        return self.write(.html, html);
    }

    pub fn writeRTF(self: Clipboardz, rtf: []const u8) ClipboardError!void {
        return self.write(.richtext, rtf);
    }

    pub fn read(self: Clipboardz, content: ClipboardContent) ClipboardError![]u8 {
        return implementation.read(self.allocator, content);
    }

    pub fn readText(self: Clipboardz) ClipboardError![]u8 {
        return self.read(.text);
    }

    pub fn readHTML(self: Clipboardz) ClipboardError![]u8 {
        return self.read(.html);
    }

    pub fn readRTF(self: Clipboardz) ClipboardError![]u8 {
        return self.read(.richtext);
    }

    pub fn has(self: Clipboardz, content: ClipboardContent) bool {
        _ = self;
        return implementation.has(content);
    }

    pub fn clear(self: Clipboardz) ClipboardError!void {
        return implementation.clear(self.allocator);
    }
};

test "basic test" {
    try std.testing.expect(true);
}
