pub const ClipboardError = error{
    SystemError,
    OutOfMemory,
    NotSupported,
    InvalidInput,
};

pub const ClipboardContent = enum {
    text,
    richtext,
    html,
};

pub const ClipboardItem = struct {
    content: ClipboardContent,
    data: []const u8,
};
