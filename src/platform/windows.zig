const std = @import("std");
const ClipboardError = @import("../types.zig").ClipboardError;
const types = @import("../types.zig");
const windows = std.os.windows;

// Win32 API definitions
const BOOL = windows.BOOL;
const HWND = windows.HWND;
const HANDLE = windows.HANDLE;
const LPCSTR = [*:0]const u8;
const UINT = c_uint;
const SIZE_T = usize;

// Clipboard formats
const CF_TEXT = 1;

extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn SetClipboardData(uFormat: UINT, hMem: ?HANDLE) callconv(.winapi) ?HANDLE;
extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.winapi) ?HANDLE;
extern "user32" fn IsClipboardFormatAvailable(format: UINT) callconv(.winapi) BOOL;
extern "user32" fn RegisterClipboardFormatA(lpszFormat: LPCSTR) callconv(.winapi) UINT;

extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: SIZE_T) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalLock(hMem: ?HANDLE) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: ?HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GlobalFree(hMem: ?HANDLE) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalSize(hMem: ?HANDLE) callconv(.winapi) SIZE_T;

const GMEM_MOVEABLE = 0x0002;

fn getFormatId(content: types.ClipboardContent) UINT {
    return switch (content) {
        .text => CF_TEXT,
        .richtext => RegisterClipboardFormatA("Rich Text Format"),
        .html => RegisterClipboardFormatA("HTML Format"),
    };
}

pub fn read(allocator: std.mem.Allocator, content: types.ClipboardContent) ClipboardError![]u8 {
    if (OpenClipboard(null) == 0) return error.SystemError;
    defer _ = CloseClipboard();

    const format_id = getFormatId(content);

    if (format_id == 0) return error.NotSupported;

    const hMem = GetClipboardData(format_id);
    if (hMem == null) return error.SystemError;

    const ptr = GlobalLock(hMem) orelse return error.SystemError;
    defer _ = GlobalUnlock(hMem);

    const src = @as([*:0]const u8, @ptrCast(ptr));
    const len = std.mem.len(src);

    return allocator.dupe(u8, src[0..len]);
}

pub fn write(allocator: std.mem.Allocator, content: types.ClipboardContent, data: []const u8) ClipboardError!void {
    _ = allocator;
    if (OpenClipboard(null) == 0) return error.SystemError;
    defer _ = CloseClipboard();

    if (EmptyClipboard() == 0) return error.SystemError;

    const format_id = getFormatId(content);

    if (format_id == 0) return error.NotSupported;

    // Allocate global memory
    const hMem = GlobalAlloc(GMEM_MOVEABLE, data.len + 1);
    if (hMem == null) return error.OutOfMemory;

    {
        const ptr = GlobalLock(hMem) orelse {
            _ = GlobalFree(hMem);
            return error.SystemError;
        };
        defer _ = GlobalUnlock(hMem);

        const dest = @as([*]u8, @ptrCast(ptr));
        @memcpy(dest[0..data.len], data);
        dest[data.len] = 0;
    }

    if (SetClipboardData(format_id, hMem) == null) {
        _ = GlobalFree(hMem);
        return error.SystemError;
    }
}

pub fn writeMultiple(allocator: std.mem.Allocator, items: []const types.ClipboardItem) ClipboardError!void {
    _ = allocator;
    if (items.len == 0) return error.InvalidInput;
    if (OpenClipboard(null) == 0) return error.SystemError;
    defer _ = CloseClipboard();

    if (EmptyClipboard() == 0) return error.SystemError;

    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const it = items[i];
        const format_id = getFormatId(it.content);
        if (format_id == 0) return error.NotSupported;

        const hMem = GlobalAlloc(GMEM_MOVEABLE, it.data.len + 1);
        if (hMem == null) return error.OutOfMemory;

        {
            const ptr = GlobalLock(hMem) orelse {
                _ = GlobalFree(hMem);
                return error.SystemError;
            };
            defer _ = GlobalUnlock(hMem);

            const dest = @as([*]u8, @ptrCast(ptr));
            @memcpy(dest[0..it.data.len], it.data);
            dest[it.data.len] = 0;
        }

        if (SetClipboardData(format_id, hMem) == null) {
            _ = GlobalFree(hMem);
            return error.SystemError;
        }
    }
}

pub fn has(content: types.ClipboardContent) bool {
    const format_id = getFormatId(content);

    if (format_id == 0) return false;

    return IsClipboardFormatAvailable(format_id) != 0;
}

pub fn clear(_: std.mem.Allocator) ClipboardError!void {
    if (OpenClipboard(null) == 0) return error.SystemError;
    defer _ = CloseClipboard();

    if (EmptyClipboard() == 0) return error.SystemError;
    return;
}

test "windows writeMultiple empty returns InvalidInput" {
    const allocator = std.testing.allocator;
    const empty: [0]types.ClipboardItem = undefined;
    try std.testing.expectError(types.ClipboardError.InvalidInput, writeMultiple(allocator, empty[0..0]));
}

test "windows integration write/read roundtrip" {
    const allocator = std.testing.allocator;
    const text = "Hello from Zig Windows Test";
    try write(allocator, .text, text);

    const got = try read(allocator, .text);
    defer allocator.free(got);
    try std.testing.expectEqualStrings(text, got);
}
