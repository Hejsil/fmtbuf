<!---
README.md is autogenerated. Please edit example/README.md.template instead.
-->
# fmtbuf

An alternative to `std.fmt.bufPrintZ` which can:

* Automatically figure out the buffer size at compile time
* Can be partially formatted, allowing for a prefix to be formatted and reused.

```zig
const FmtBuf = @import("fmtbuf").FmtBuf;
const std = @import("std");

test {
    var buf = FmtBuf("[{}] = {}", std.meta.Tuple(&.{ usize, u8 })){};
    try std.testing.expectEqualStrings("[0] = 0", buf.format(.{ 0, 0 }));
    try std.testing.expectEqualStrings("[12] = 3", buf.format(.{ 12, 3 }));

    var partial = buf.partialFormat(1, .{500});
    try std.testing.expectEqualStrings("[500] = 0", partial.format(.{0}));
    try std.testing.expectEqualStrings("[500] = 1", partial.format(.{1}));
    try std.testing.expectEqualStrings("[500] = 2", partial.format(.{2}));
}

```

