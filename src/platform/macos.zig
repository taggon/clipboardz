const std = @import("std");
const types = @import("../types.zig");
const objc = @import("objc");

const ClipboardError = types.ClipboardError;
const ClipboardContent = types.ClipboardContent;

fn getPasteboard() !objc.Object {
    const NSPasteboardClass = objc.getClass("NSPasteboard") orelse return error.SystemError;
    return NSPasteboardClass.msgSend(objc.Object, objc.sel("generalPasteboard"), .{});
}

pub fn read(allocator: std.mem.Allocator, content: ClipboardContent) ClipboardError![]u8 {
    const pasteboard = getPasteboard() catch return error.SystemError;

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const NSStringClass = objc.getClass("NSString") orelse return error.SystemError;
    const targetNsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{targetType.ptr});

    const nsStr = pasteboard.msgSend(objc.Object, objc.sel("stringForType:"), .{targetNsStr});

    if (nsStr.value == null) return error.SystemError;

    const utf8Ptr = nsStr.msgSend(?[*]const u8, objc.sel("UTF8String"), .{});
    if (utf8Ptr) |ptr| {
        const len = nsStr.msgSend(usize, objc.sel("lengthOfBytesUsingEncoding:"), .{@as(usize, 4)}); // 4 = NSUTF8StringEncoding
        return allocator.dupe(u8, ptr[0..len]);
    }

    return error.SystemError;
}

pub fn write(_: std.mem.Allocator, content: ClipboardContent, data: []const u8) ClipboardError!void {
    const pasteboard = getPasteboard() catch return error.SystemError;

    _ = pasteboard.msgSend(isize, objc.sel("clearContents"), .{});

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const NSStringClass = objc.getClass("NSString") orelse return error.SystemError;
    const targetNsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{targetType.ptr});

    const NSArrayClass = objc.getClass("NSArray") orelse return error.SystemError;
    const typesArray = NSArrayClass.msgSend(objc.Object, objc.sel("arrayWithObject:"), .{targetNsStr});

    _ = pasteboard.msgSend(isize, objc.sel("declareTypes:owner:"), .{typesArray, null});

    const nsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{data.ptr});
    const ret = pasteboard.msgSend(bool, objc.sel("setString:forType:"), .{nsStr, targetNsStr});
    if (!ret) return error.SystemError;
}

pub fn writeMultiple(_: std.mem.Allocator, items: []const types.ClipboardItem) ClipboardError!void {
    if (items.len == 0) return error.InvalidInput;
    const pasteboard = getPasteboard() catch return error.SystemError;

    _ = pasteboard.msgSend(isize, objc.sel("clearContents"), .{});

    const NSMutableArrayClass = objc.getClass("NSMutableArray") orelse return error.SystemError;
    const NSStringClass = objc.getClass("NSString") orelse return error.SystemError;

    var mutArray = NSMutableArrayClass.msgSend(objc.Object, objc.sel("alloc"), .{});
    mutArray = mutArray.msgSend(objc.Object, objc.sel("initWithCapacity:"), .{items.len});

    // Populate types array with UTI NSStrings for each item
    for (items) |it| {
        const targetType = switch (it.content) {
            .text => "public.utf8-plain-text",
            .richtext => "public.rtf",
            .html => "public.html",
        };

        const targetNsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{targetType.ptr});
        _ = mutArray.msgSend(void, objc.sel("addObject:"), .{targetNsStr});
    }

    _ = pasteboard.msgSend(isize, objc.sel("declareTypes:owner:"), .{mutArray, null});

    // For each item, fetch the corresponding UTI NSString from the array and set the string for that type
    for (items, 0..) |it, i| {
        const typeObj = mutArray.msgSend(objc.Object, objc.sel("objectAtIndex:"), .{i});

        const nsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{it.data.ptr});
        const ret = pasteboard.msgSend(bool, objc.sel("setString:forType:"), .{nsStr, typeObj});
        if (!ret) {
            return error.SystemError;
        }
    }
}

pub fn has(content: ClipboardContent) bool {
    const pasteboard = getPasteboard() catch return false;
    const typesObj = pasteboard.msgSend(objc.Object, objc.sel("types"), .{});

    if (typesObj.value == null) return false;

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const NSStringClass = objc.getClass("NSString") orelse return false;
    const targetNsStr = NSStringClass.msgSend(objc.Object, objc.sel("stringWithUTF8String:"), .{targetType.ptr});

    return typesObj.msgSend(bool, objc.sel("containsObject:"), .{targetNsStr});
}

pub fn clear(_: std.mem.Allocator) ClipboardError!void {
    const pasteboard = getPasteboard() catch return error.SystemError;
    _ = pasteboard.msgSend(isize, objc.sel("clearContents"), .{});
}

test "macos writeMultiple empty returns InvalidInput" {
    const allocator = std.testing.allocator;
    const empty: [0]types.ClipboardItem = undefined;
    try std.testing.expectError(types.ClipboardError.InvalidInput, writeMultiple(allocator, empty[0..0]));
}

// Integration Tests
test "macos integration with pbcopy/pbpaste" {
    const allocator = std.testing.allocator;

    // Helper to run pbpaste
    const runPbPaste = struct {
        fn call(alloc: std.mem.Allocator) ![]u8 {
            const argv = &[_][]const u8{"pbpaste"};
            var child = std.process.Child.init(argv, alloc);
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Ignore;
            try child.spawn();

            const stdout = child.stdout.?;
            const output = try stdout.readToEndAlloc(alloc, 1024 * 1024);
            _ = try child.wait();
            return output;
        }
    }.call;

    // Helper to run pbcopy
    const runPbCopy = struct {
        fn call(alloc: std.mem.Allocator, txt: []const u8) !void {
            const argv = &[_][]const u8{"pbcopy"};
            var child = std.process.Child.init(argv, alloc);
            child.stdin_behavior = .Pipe;
            try child.spawn();

            if (child.stdin) |*stdin| {
                try stdin.writeAll(txt);
                stdin.close();
                child.stdin = null;
            }
            _ = try child.wait();
        }
    }.call;

    // 1. Write with library, verify with pbpaste
    const text1 = "Hello from Zig Library Test";
    // We need to use the internal implementation directly or mock the struct?
    // Since we are inside platform/macos.zig, we can call writeText directly IF it's still pub.
    // But main.zig wraps it.
    // Actually, platform/macos.zig exports writeText matching the signature.
    // So we can just call it directly as before, BUT we need to pass allocator.
    // Wait, the previous test code was:
    // try writeText(allocator, text1);
    // This is still valid because we are inside macos.zig and writeText is defined here.
    // The issue might be that I didn't see the error log for macos tests, only for linux build failure.
    // Let's double check if I need to change anything here.
    // If I am testing the *library* public API, I should import it.
    // But this is a unit test inside the module.
    // Let's keep it direct for now, but ensure it compiles.
    try write(allocator, .text, text1);

    const pbpaste_out = try runPbPaste(allocator);
    defer allocator.free(pbpaste_out);
    try std.testing.expectEqualStrings(text1, pbpaste_out);

    // 2. Write with pbcopy, verify with library
    const text2 = "Hello from pbcopy";
    try runPbCopy(allocator, text2);

    const lib_read = try read(allocator, .text);
    defer allocator.free(lib_read);
    try std.testing.expectEqualStrings(text2, lib_read);

    // 3. UTF-8 Support (Korean + Emoji)
    const text3 = "안녕하세요 Zig! 🚀";
    try write(allocator, .text, text3);

    const pbpaste_utf8 = try runPbPaste(allocator);
    defer allocator.free(pbpaste_utf8);
    try std.testing.expectEqualStrings(text3, pbpaste_utf8);

    // 4. Test 'has' method
    // We know we just wrote text, so has(.text) should be true
    try std.testing.expect(has(.text));
    // We didn't write RTF or HTML, so they should be false (unless some auto-conversion happens, but unlikely for simple text)
    try std.testing.expect(!has(.richtext));
    try std.testing.expect(!has(.html));

    // 5. Test RichText
    const rtf_content = "{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Courier;}} \\f0\\fs60 Hello, World!}";
    try write(allocator, .richtext, rtf_content);
    try std.testing.expect(has(.richtext));
    const read_rtf = try read(allocator, .richtext);
    defer allocator.free(read_rtf);
    try std.testing.expectEqualStrings(rtf_content, read_rtf);

    // 6. Test HTML
    const html_content = "<html><body><h1>Hello, World!</h1></body></html>";
    try write(allocator, .html, html_content);
    try std.testing.expect(has(.html));
    const read_html = try read(allocator, .html);
    defer allocator.free(read_html);
    try std.testing.expectEqualStrings(html_content, read_html);
}
