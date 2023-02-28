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
