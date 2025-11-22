const std = @import("std");
const types = @import("../types.zig");
const objc_lib = @import("macos_objc.zig");

const ClipboardError = types.ClipboardError;
const ClipboardContent = types.ClipboardContent;
const objc = objc_lib.objc;

fn getPasteboard() !objc.id {
    const NSPasteboard = objc.objc_getClass("NSPasteboard");
    if (NSPasteboard == null) return error.SystemError;

    const generalPasteboardSel = objc.sel_registerName("generalPasteboard");
    return objc_lib.msgSend_noArgs(NSPasteboard, generalPasteboardSel);
}

pub fn read(allocator: std.mem.Allocator, content: ClipboardContent) ClipboardError![]u8 {
    const pasteboard = getPasteboard() catch return error.SystemError;

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const targetNsStr = objc_lib.NSStringFromSlice(targetType) catch return error.OutOfMemory;
    defer objc_lib.msgSend_void(targetNsStr, objc.sel_registerName("release"));

    const stringForTypeSel = objc.sel_registerName("stringForType:");
    const nsStr = objc_lib.msgSend_id(pasteboard, stringForTypeSel, targetNsStr);

    if (nsStr == null) return error.SystemError;

    return objc_lib.SliceFromNSString(allocator, nsStr);
}

pub fn write(_: std.mem.Allocator, content: ClipboardContent, data: []const u8) ClipboardError!void {
    const pasteboard = getPasteboard() catch return error.SystemError;

    const clearContentsSel = objc.sel_registerName("clearContents");
    _ = objc_lib.msgSend_int(pasteboard, clearContentsSel);

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const targetNsStr = objc_lib.NSStringFromSlice(targetType) catch return error.OutOfMemory;
    defer objc_lib.msgSend_void(targetNsStr, objc.sel_registerName("release"));

    const declareTypesSel = objc.sel_registerName("declareTypes:owner:");
    const arrayWithObjectSel = objc.sel_registerName("arrayWithObject:");
    const nsArrayClass = objc.objc_getClass("NSArray");

    // Create array with target type
    const FnArray = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) objc.id;
    const arrayWithObject = @as(FnArray, @ptrCast(&objc.objc_msgSend));
    const typesArray = arrayWithObject(nsArrayClass, arrayWithObjectSel, targetNsStr);

    _ = objc_lib.msgSend_int_id_id(pasteboard, declareTypesSel, typesArray, null);

    const setStringSel = objc.sel_registerName("setString:forType:");
    const nsStr = objc_lib.NSStringFromSlice(data) catch return error.OutOfMemory;
    defer objc_lib.msgSend_void(nsStr, objc.sel_registerName("release"));

    const ret = objc_lib.msgSend_bool_id_id(pasteboard, setStringSel, nsStr, targetNsStr);
    if (!ret) return error.SystemError;
}

pub fn writeMultiple(_: std.mem.Allocator, items: []const types.ClipboardItem) ClipboardError!void {
    if (items.len == 0) return error.InvalidInput;
    const pasteboard = getPasteboard() catch return error.SystemError;

    const clearContentsSel = objc.sel_registerName("clearContents");
    _ = objc_lib.msgSend_int(pasteboard, clearContentsSel);

    const NSMutableArray = objc.objc_getClass("NSMutableArray");
    if (NSMutableArray == null) return error.SystemError;

    const allocSel = objc.sel_registerName("alloc");
    const initWithCapacitySel = objc.sel_registerName("initWithCapacity:");
    const addObjectSel = objc.sel_registerName("addObject:");
    const objectAtIndexSel = objc.sel_registerName("objectAtIndex:");
    const releaseSel = objc.sel_registerName("release");

    // alloc/initWithCapacity:
    const FnAlloc = *const fn (objc.id, objc.SEL) callconv(.c) objc.id;
    const FnInitCap = *const fn (objc.id, objc.SEL, usize) callconv(.c) objc.id;
    const FnAdd = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) void;
    const FnObjectAtIndex = *const fn (objc.id, objc.SEL, usize) callconv(.c) objc.id;

    const mutArrayAlloc = @as(FnAlloc, @ptrCast(&objc.objc_msgSend));
    var mutArray = mutArrayAlloc(NSMutableArray, allocSel);
    const mutArrayInit = @as(FnInitCap, @ptrCast(&objc.objc_msgSend));
    mutArray = mutArrayInit(mutArray, initWithCapacitySel, items.len);

    const addFunc = @as(FnAdd, @ptrCast(&objc.objc_msgSend));

    // Populate types array with UTI NSStrings for each item
    for (items) |it| {
        const targetType = switch (it.content) {
            .text => "public.utf8-plain-text",
            .richtext => "public.rtf",
            .html => "public.html",
        };

        const targetNsStr = objc_lib.NSStringFromSlice(targetType) catch return error.OutOfMemory;
        // addObject: will retain the object, so release our reference afterwards
        addFunc(mutArray, addObjectSel, targetNsStr);
        objc_lib.msgSend_void(targetNsStr, releaseSel);
    }

    const declareTypesSel = objc.sel_registerName("declareTypes:owner:");
    _ = objc_lib.msgSend_int_id_id(pasteboard, declareTypesSel, mutArray, null);

    const setStringSel = objc.sel_registerName("setString:forType:");
    const objectAtIndex = @as(FnObjectAtIndex, @ptrCast(&objc.objc_msgSend));

    // For each item, fetch the corresponding UTI NSString from the array and set the string for that type
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const it = items[i];
        const typeObj = objectAtIndex(mutArray, objectAtIndexSel, i);

        const nsStr = objc_lib.NSStringFromSlice(it.data) catch return error.OutOfMemory;
        const ret = objc_lib.msgSend_bool_id_id(pasteboard, setStringSel, nsStr, typeObj);
        // release our created data string
        objc_lib.msgSend_void(nsStr, releaseSel);
        if (!ret) {
            // release array before returning
            objc_lib.msgSend_void(mutArray, releaseSel);
            return error.SystemError;
        }
    }

    // release the NSMutableArray we created
    objc_lib.msgSend_void(mutArray, releaseSel);
}

pub fn has(content: ClipboardContent) bool {
    const pasteboard = getPasteboard() catch return false;
    const typesSel = objc.sel_registerName("types");
    const typesObj = objc_lib.msgSend_noArgs(pasteboard, typesSel);

    if (typesObj == null) return false;

    const containsObjectSel = objc.sel_registerName("containsObject:");

    const targetType = switch (content) {
        .text => "public.utf8-plain-text",
        .richtext => "public.rtf",
        .html => "public.html",
    };

    const targetNsStr = objc_lib.NSStringFromSlice(targetType) catch return false;

    // containsObject returns BOOL (signed char or bool)
    const Fn = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) bool;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(typesObj, containsObjectSel, targetNsStr);
}

pub fn clear(_: std.mem.Allocator) ClipboardError!void {
    const pasteboard = getPasteboard() catch return error.SystemError;
    const clearContentsSel = objc.sel_registerName("clearContents");
    _ = objc_lib.msgSend_int(pasteboard, clearContentsSel);
    return;
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
