const std = @import("std");
const ClipboardError = @import("../types.zig").ClipboardError;
const types = @import("../types.zig");

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
});

// X11 Atoms
fn getAtom(display: *c.Display, name: [:0]const u8) c.Atom {
    return c.XInternAtom(display, name, c.False);
}

pub fn read(allocator: std.mem.Allocator, content: types.ClipboardContent) ClipboardError![]u8 {
    const display = c.XOpenDisplay(null) orelse return error.SystemError;
    defer _ = c.XCloseDisplay(display);

    const root = c.DefaultRootWindow(display);
    const window = c.XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0);
    defer _ = c.XDestroyWindow(display, window);

    const clipboard = getAtom(display, "CLIPBOARD");
    const property = getAtom(display, "ZIG_CLIPBOARD_PROP");

    const target_atom_name = switch (content) {
        .text => "UTF8_STRING",
        .richtext => "text/rtf",
        .html => "text/html",
    };
    const target_atom = getAtom(display, target_atom_name);

    // Request conversion
    _ = c.XConvertSelection(display, clipboard, target_atom, property, window, c.CurrentTime);

    // Event loop waiting for SelectionNotify
    var event: c.XEvent = undefined;
    var selection_received = false;

    // Simple timeout mechanism could be added, but for now blocking.
    while (!selection_received) {
        _ = c.XNextEvent(display, &event);
        if (event.type == c.SelectionNotify) {
            if (event.xselection.property == c.None) {
                return error.SystemError; // Conversion failed or refused
            }
            selection_received = true;
        }
    }

    // Read property
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop_return: [*c]u8 = undefined;

    const result = c.XGetWindowProperty(display, window, property, 0, std.math.maxInt(c_long) / 4, c.False, c.AnyPropertyType, &actual_type, &actual_format, &nitems, &bytes_after, &prop_return);

    if (result != c.Success) return error.SystemError;
    defer _ = c.XFree(prop_return);

    // Relaxed check for text since some apps might return STRING instead of UTF8_STRING
    if (content == .text) {
        if (actual_type != target_atom and actual_type != getAtom(display, "STRING")) {
            // Mismatch
        }
    } else {
        if (actual_type != target_atom) {
            // Mismatch
        }
    }

    const len = @as(usize, @intCast(nitems));
    return allocator.dupe(u8, prop_return[0..len]);
}

pub fn write(allocator: std.mem.Allocator, content: types.ClipboardContent, data: []const u8) ClipboardError!void {
    _ = allocator;
    // Fork to serve
    const pid = std.os.linux.fork();
    if (pid > 0) {
        return;
    } else if (pid == 0) {
        serveClipboard(content, data) catch {};
        std.os.linux.exit(0);
    } else {
        return error.SystemError;
    }
}

pub fn writeMultiple(allocator: std.mem.Allocator, items: []const types.ClipboardItem) ClipboardError!void {
    _ = allocator;
    if (items.len == 0) return error.InvalidInput;

    const pid = std.os.linux.fork();
    if (pid > 0) {
        return;
    } else if (pid == 0) {
        serveClipboardMultiple(items) catch {};
        std.os.linux.exit(0);
    } else {
        return error.SystemError;
    }
}

fn serveClipboard(content: types.ClipboardContent, data: []const u8) !void {
    const display = c.XOpenDisplay(null) orelse return error.SystemError;
    defer _ = c.XCloseDisplay(display);

    const root = c.DefaultRootWindow(display);
    const window = c.XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0);

    const clipboard = getAtom(display, "CLIPBOARD");
    const targets = getAtom(display, "TARGETS");

    const target_atom_name = switch (content) {
        .text => "UTF8_STRING",
        .richtext => "text/rtf",
        .html => "text/html",
    };
    const target_atom = getAtom(display, target_atom_name);

    _ = c.XSetSelectionOwner(display, clipboard, window, c.CurrentTime);

    if (c.XGetSelectionOwner(display, clipboard) != window) {
        return error.SystemError;
    }

    var event: c.XEvent = undefined;
    while (true) {
        _ = c.XNextEvent(display, &event);
        switch (event.type) {
            c.SelectionClear => {
                return;
            },
            c.SelectionRequest => {
                const req = event.xselectionrequest;
                var ev: c.XSelectionEvent = undefined;
                ev.type = c.SelectionNotify;
                ev.display = req.display;
                ev.requestor = req.requestor;
                ev.selection = req.selection;
                ev.time = req.time;
                ev.target = req.target;
                ev.property = req.property;

                if (req.target == targets) {
                    const atoms = [_]c.Atom{ target_atom, targets };
                    _ = c.XChangeProperty(display, req.requestor, req.property, c.XA_ATOM, 32, c.PropModeReplace, @as([*]const u8, @ptrCast(&atoms)), atoms.len);
                } else if (req.target == target_atom or (content == .text and req.target == c.XA_STRING)) {
                    _ = c.XChangeProperty(display, req.requestor, req.property, req.target, 8, c.PropModeReplace, data.ptr, @as(c_int, @intCast(data.len)));
                } else {
                    ev.property = c.None;
                }

                _ = c.XSendEvent(display, req.requestor, c.False, 0, @as(*c.XEvent, @ptrCast(&ev)));
            },
            else => {},
        }
    }
}

fn serveClipboardMultiple(items: []const types.ClipboardItem) !void {
    const display = c.XOpenDisplay(null) orelse return error.SystemError;
    defer _ = c.XCloseDisplay(display);

    const root = c.DefaultRootWindow(display);
    const window = c.XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0);

    const clipboard = getAtom(display, "CLIPBOARD");
    const targets = getAtom(display, "TARGETS");

    // Build atom list for each item
    const atom_count: usize = items.len + 1; // items + targets
    var atoms_ptr = std.heap.c_allocator.alloc(c.Atom, atom_count) catch return error.OutOfMemory;
    defer std.heap.c_allocator.free(atoms_ptr);

    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        const name = switch (items[i].content) {
            .text => "UTF8_STRING",
            .richtext => "text/rtf",
            .html => "text/html",
        };
        atoms_ptr[i] = getAtom(display, name);
    }
    atoms_ptr[items.len] = targets;

    _ = c.XSetSelectionOwner(display, clipboard, window, c.CurrentTime);

    if (c.XGetSelectionOwner(display, clipboard) != window) {
        return error.SystemError;
    }

    var event: c.XEvent = undefined;
    while (true) {
        _ = c.XNextEvent(display, &event);
        switch (event.type) {
            c.SelectionClear => {
                return;
            },
            c.SelectionRequest => {
                const req = event.xselectionrequest;
                var ev: c.XSelectionEvent = undefined;
                ev.type = c.SelectionNotify;
                ev.display = req.display;
                ev.requestor = req.requestor;
                ev.selection = req.selection;
                ev.time = req.time;
                ev.target = req.target;
                ev.property = req.property;

                if (req.target == targets) {
                    // atoms_ptr is an allocated array of c.Atom; present it as bytes
                    _ = c.XChangeProperty(display, req.requestor, req.property, c.XA_ATOM, 32, c.PropModeReplace, @as([*]const u8, @ptrCast(atoms_ptr)), @as(c_int, @intCast(atom_count)));
                } else {
                    // Find matching item
                    var handled = false;
                    var j: usize = 0;
                    while (j < items.len) : (j += 1) {
                        const atom_for_item = atoms_ptr[j];
                        if (req.target == atom_for_item or (items[j].content == .text and req.target == c.XA_STRING)) {
                            _ = c.XChangeProperty(display, req.requestor, req.property, req.target, 8, c.PropModeReplace, items[j].data.ptr, @as(c_int, @intCast(items[j].data.len)));
                            handled = true;
                            break;
                        }
                    }
                    if (!handled) {
                        ev.property = c.None;
                    }
                }

                _ = c.XSendEvent(display, req.requestor, c.False, 0, @as(*c.XEvent, @ptrCast(&ev)));
            },
            else => {},
        }
    }
}

pub fn has(content: types.ClipboardContent) bool {
    const display = c.XOpenDisplay(null) orelse return false;
    defer _ = c.XCloseDisplay(display);

    const clipboard = getAtom(display, "CLIPBOARD");
    const targets = getAtom(display, "TARGETS");
    const property = getAtom(display, "ZIG_CLIPBOARD_CHECK");

    // Request TARGETS
    const root = c.DefaultRootWindow(display);
    const window = c.XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0);
    defer _ = c.XDestroyWindow(display, window);

    _ = c.XConvertSelection(display, clipboard, targets, property, window, c.CurrentTime);

    var event: c.XEvent = undefined;
    var selection_received = false;

    // Simple timeout loop?
    while (!selection_received) {
        _ = c.XNextEvent(display, &event);
        if (event.type == c.SelectionNotify) {
            if (event.xselection.property == c.None) {
                if (event.xselection.property == c.None) {
                    return false;
                }
            }
            selection_received = true;
        }
    }

    // Read property
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop_return: [*c]u8 = undefined;

    const result = c.XGetWindowProperty(display, window, property, 0, 4096, c.False, c.XA_ATOM, &actual_type, &actual_format, &nitems, &bytes_after, &prop_return);

    if (result != c.Success) return false;
    defer _ = c.XFree(prop_return);

    if (actual_type != c.XA_ATOM or actual_format != 32) return false;

    const atoms = @as([*]c.Atom, @ptrCast(@alignCast(prop_return)));
    const count = @as(usize, @intCast(nitems));

    const target_atom_name = switch (content) {
        .text => "UTF8_STRING",
        .richtext => "text/rtf",
        .html => "text/html",
    };
    const target_atom = getAtom(display, target_atom_name);

    for (0..count) |i| {
        if (atoms[i] == target_atom) return true;
        if (content == .text) {
            if (atoms[i] == getAtom(display, "STRING")) return true;
            if (atoms[i] == getAtom(display, "TEXT")) return true;
        }
    }

    return false;
}

pub fn clear(_: std.mem.Allocator) ClipboardError!void {
    // Clear selection owner for CLIPBOARD
    const display = c.XOpenDisplay(null) orelse return error.SystemError;
    defer _ = c.XCloseDisplay(display);

    const clipboard = getAtom(display, "CLIPBOARD");
    _ = c.XSetSelectionOwner(display, clipboard, c.None, c.CurrentTime);

    if (c.XGetSelectionOwner(display, clipboard) != c.None) {
        return error.SystemError;
    }
    return;
}

test "linux writeMultiple empty returns InvalidInput" {
    const allocator = std.testing.allocator;
    const empty: [0]types.ClipboardItem = undefined;
    try std.testing.expectError(types.ClipboardError.InvalidInput, writeMultiple(allocator, empty[0..0]));
}

test "linux integration write/read roundtrip" {
    const allocator = std.testing.allocator;
    // Integration test requires an X11 DISPLAY; skip if not present
    if (std.os.getenv("DISPLAY") == null) return;

    const text = "Hello from Zig Linux Test";
    try write(allocator, .text, text);
    // small delay to allow selection owner to be established
    std.time.sleep(std.time.millisecond * 100);

    const got = try read(allocator, .text);
    defer allocator.free(got);
    try std.testing.expectEqualStrings(text, got);
}
