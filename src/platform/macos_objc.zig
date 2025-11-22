const std = @import("std");

// Objective-C Runtime bindings
pub const objc = struct {
    pub const id = ?*anyopaque;
    pub const SEL = ?*anyopaque;
    pub const Class = ?*anyopaque;

    pub extern "c" fn objc_getClass(name: [*:0]const u8) Class;
    pub extern "c" fn sel_registerName(name: [*:0]const u8) SEL;
    pub extern "c" fn objc_msgSend() void;
};

// Manual wrappers for specific signatures
pub fn msgSend_alloc(self: objc.id, op: objc.SEL) objc.id {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) objc.id;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op);
}

pub fn msgSend_init(self: objc.id, op: objc.SEL, bytes: [*]const u8, len: usize, encoding: usize) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, [*]const u8, usize, usize) callconv(.c) objc.id;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, bytes, len, encoding);
}

pub fn msgSend_noArgs(self: objc.id, op: objc.SEL) objc.id {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) objc.id;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op);
}

pub fn msgSend_setString(self: objc.id, op: objc.SEL, str: objc.id, typeStr: objc.id) bool {
    const Fn = *const fn (objc.id, objc.SEL, objc.id, objc.id) callconv(.c) bool;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, str, typeStr);
}

pub fn msgSend_stringForType(self: objc.id, op: objc.SEL, typeStr: objc.id) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) objc.id;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, typeStr);
}

pub fn msgSend_length(self: objc.id, op: objc.SEL, encoding: usize) usize {
    const Fn = *const fn (objc.id, objc.SEL, usize) callconv(.c) usize;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, encoding);
}

pub fn msgSend_UTF8String(self: objc.id, op: objc.SEL) ?[*]const u8 {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) ?[*]const u8;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op);
}

pub fn msgSend_void(self: objc.id, op: objc.SEL) void {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) void;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    func(self, op);
}

pub fn msgSend_int(self: objc.id, op: objc.SEL) isize {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) isize;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op);
}

pub fn msgSend_int_id_id(self: objc.id, op: objc.SEL, arg1: objc.id, arg2: objc.id) isize {
    const Fn = *const fn (objc.id, objc.SEL, objc.id, objc.id) callconv(.c) isize;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, arg1, arg2);
}

pub fn msgSend_bool_id_id(self: objc.id, op: objc.SEL, arg1: objc.id, arg2: objc.id) bool {
    const Fn = *const fn (objc.id, objc.SEL, objc.id, objc.id) callconv(.c) bool;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, arg1, arg2);
}

pub fn msgSend_id(self: objc.id, op: objc.SEL, arg1: objc.id) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) objc.id;
    const func = @as(Fn, @ptrCast(&objc.objc_msgSend));
    return func(self, op, arg1);
}

pub fn NSStringFromSlice(slice: []const u8) !objc.id {
    const NSString = objc.objc_getClass("NSString");
    if (NSString == null) return error.SystemError;

    const allocSel = objc.sel_registerName("alloc");
    const initWithBytesLengthEncodingSel = objc.sel_registerName("initWithBytes:length:encoding:");

    const NSUTF8StringEncoding: usize = 4;

    const rawStr = msgSend_alloc(NSString, allocSel);
    if (rawStr == null) return error.OutOfMemory;

    const nsStr = msgSend_init(rawStr, initWithBytesLengthEncodingSel, slice.ptr, slice.len, NSUTF8StringEncoding);

    if (nsStr == null) return error.OutOfMemory;
    return nsStr;
}

pub fn SliceFromNSString(allocator: std.mem.Allocator, nsStr: objc.id) ![]u8 {
    if (nsStr == null) return error.SystemError;

    const UTF8StringSel = objc.sel_registerName("UTF8String");
    const lengthOfBytesUsingEncodingSel = objc.sel_registerName("lengthOfBytesUsingEncoding:");
    const NSUTF8StringEncoding: usize = 4;

    const len = msgSend_length(nsStr, lengthOfBytesUsingEncodingSel, NSUTF8StringEncoding);

    const ptr = msgSend_UTF8String(nsStr, UTF8StringSel);
    if (ptr == null) return error.SystemError;

    const slice = ptr.?[0..len];

    return allocator.dupe(u8, slice);
}
