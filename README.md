# clipboardz

A cross-platform clipboard library for Zig.

## Features

- **Cross-Platform Support**:
    - **macOS**: Uses `NSPasteboard` via Objective-C runtime.
    - **Windows**: Uses Win32 API (`user32.dll`).
    - **Linux**: Uses native X11 C API (`libX11`).
- **Content Types**:
    - Plain Text (`text/plain`, `UTF8_STRING`, `CF_TEXT`)
    - Rich Text (`public.rtf`, `text/rtf`, `Rich Text Format`)
    - HTML (`public.html`, `text/html`, `HTML Format`)

## Installation

You can install `clipboardz` using `zig fetch`.

```bash
zig fetch --save git+https://github.com/taggon/clipboardz.git
```

Then, add it to your `build.zig`:

```zig
const clipboardz = b.dependency("clipboardz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("clipboardz", clipboardz.module("clipboardz"));
```

> **Note**: On macOS, you need to link `objc`, `Foundation`, and `AppKit`. On Linux, you need to link `X11` and `c`.

## Usage

```zig
const std = @import("std");
const clipboard = @import("clipboardz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize
    const cb = clipboard.Clipboardz.init(allocator);

    // Write Text
    try cb.writeText("Hello, Zig!");

    // Read Text
    const text = try cb.readText();
    defer allocator.free(text);
    std.debug.print("Read: {s}\n", .{text});

    // Write HTML
    try cb.writeHtml("<h1>Hello</h1>");

    // Check Content
    if (cb.has(.html)) {
        const html = try cb.readHtml();
        defer allocator.free(html);
        std.debug.print("HTML: {s}\n", .{html});
    }
}
```

## Limitations & Future Work

Currently, the library supports **Text**, **RichText**, and **HTML**.

Support for the following content types is **planned but not yet implemented**:
- **Images** (PNG, JPEG, etc.)
- **File Lists** (Copying/Pasting files from file managers)

## License

MIT
