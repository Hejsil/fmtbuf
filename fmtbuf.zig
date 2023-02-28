const std = @import("std");

const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

/// A buffer that has a precalculated size such that `bufPrintZ(fmt_str, args)` can never fail.
/// This type does not support the entire `std.fmt` API, as some types have no maximum printed
/// size that this type can figure out.
pub fn FmtBuf(comptime fmt_str: []const u8, comptime tuple: type) type {
    return FmtBufDedup(fmt_str.len, fmt_str[0..fmt_str.len].*, tuple);
}

fn FmtBufDedup(
    comptime fmt_len: usize,
    comptime fmt_str: [fmt_len]u8,
    comptime Tuple: type,
) type {
    const max_print_size = fmt.count(&fmt_str, biggestPrintedValueForType(Tuple));
    return FmtBufSizedDedup(fmt_len, fmt_str, @intCast(usize, max_print_size), Tuple);
}

fn biggestPrintedValueForType(comptime T: type) T {
    const err = "Cannot figure out biggest printed value for '" ++ @typeName(T) ++ "'";

    return switch (@typeInfo(T)) {
        .Void => {},
        .Bool => false,
        .Int => |info| switch (info.signedness) {
            .signed => math.minInt(T),
            .unsigned => math.maxInt(T),
        },
        .Array => |info| [_]info.child{
            biggestPrintedValueForType(info.child),
        } ** info.len,
        .Vector => |info| [_]info.child{
            biggestPrintedValueForType(info.child),
        } ** info.len,
        .Pointer => |info| &comptime biggestPrintedValueForType(info.child),
        .Struct => |info| {
            if (@hasDecl(T, "format"))
                @compileError(err ++ "because it has a 'format' function");

            var res: T = undefined;
            inline for (info.fields) |field| {
                @field(res, field.name) = biggestPrintedValueForType(field.type);
            }

            return res;
        },
        .Enum => |info| {
            if (@hasDecl(T, "format"))
                @compileError(err ++ "because it has a 'format' function");

            var res: T = @field(T, info.fields[0].name);
            for (info.fields[1..]) |field| {
                const enum_field = @field(T, field.name);
                if (@tagName(res).len < @tagName(enum_field).len)
                    res = enum_field;
            }

            return res;
        },
        else => @compileError(err),
    };
}

/// A type that has the same API as `FmtBuf` but does not figure out its own buffer size.
/// It is up to the user to provide a buffer size that can fit all things ever printed to it.
/// BE WARE. If you get the size wrong and print something that does not fit in the buffer,
/// that is considered illegal behavior.
pub fn FmtBufSized(
    comptime fmt_str: []const u8,
    comptime max_print_size: usize,
    comptime Tuple: type,
) type {
    return FmtBufSizedDedup(fmt_str.len, fmt_str[0..fmt_str.len].*, max_print_size, Tuple);
}

fn FmtBufSizedDedup(
    comptime fmt_len: usize,
    comptime fmt_str: [fmt_len]u8,
    comptime max_print_size: usize,
    comptime Tuple: type,
) type {
    return struct {
        start: usize = 0,
        buf: [max_print_size + 1]u8 = undefined,

        /// Performs a `bufPrintZ` to its own internal buffer and returns the result. Calling
        /// this function again will override what is in the internal buffer, so previous slices
        /// returned will have their content overriden.
        pub fn format(buf: *@This(), args: Tuple) [:0]const u8 {
            const res = fmt.bufPrintZ(buf.buf[buf.start..], &fmt_str, args) catch unreachable;
            return buf.buf[0 .. buf.start + res.len :0];
        }

        /// Get a new `FmtBuf` where some of the arguments are already printed into the internal
        /// buffer. This new `FmtBuf` only requires arguments that has not yet been printed when
        /// formatting to it, and will return the fully formatting string, including the partially
        /// printed content.
        /// ```
        /// const Buf = FmtBuf("{} {} {}", meta.Tuple(&.{u16, u16, u16}));
        /// const buf = Buf{};
        /// var part1 = buf.partialFormat(1, .{3});
        /// testing.expectEqualStrings("3 2 1", part1.format(.{2, 1}));
        /// ```
        pub fn partialFormat(
            buf: @This(),
            comptime n: usize,
            args: FormatPartialArg(Tuple, n),
        ) FormatPartialResult(fmt_len, fmt_str, max_print_size, Tuple, n) {
            const Res = FormatPartialResult(fmt_len, fmt_str, max_print_size, Tuple, n);
            var res = Res{ .start = buf.start, .buf = buf.buf };

            const split = comptime splitFmtString(&fmt_str, n);
            const printed = fmt.bufPrint(res.buf[res.start..], split[0], args) catch unreachable;
            res.start += printed.len;

            return res;
        }
    };
}

fn FormatPartialArg(comptime Tuple: type, comptime n: usize) type {
    var info = @typeInfo(Tuple);
    info.Struct.fields = info.Struct.fields[0..n];
    return @Type(info);
}

fn FormatPartialResult(
    comptime fmt_len: usize,
    comptime fmt_str: [fmt_len]u8,
    comptime max_print_size: usize,
    comptime Tuple: type,
    comptime n: usize,
) type {
    const types = tupleFields(Tuple);
    const NewTuple = meta.Tuple(types[n..]);
    const new_fmt_str = splitFmtString(&fmt_str, n)[1];

    return FmtBufSized(new_fmt_str, max_print_size, NewTuple);
}

fn tupleFields(comptime T: type) []const type {
    const fields = meta.fields(T);
    var res: [fields.len]type = undefined;
    for (&res, fields) |*r, field|
        r.* = field.type;

    return &res;
}

fn splitFmtString(str: []const u8, n: usize) [2][]const u8 {
    var curr: usize = 0;

    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        if (mem.startsWith(u8, str[i..], "{{")) {
            i += 1;
            continue;
        }
        if (!mem.startsWith(u8, str[i..], "{"))
            continue;

        if (curr != n) {
            curr += 1;
            continue;
        }

        return [_][]const u8{
            str[0..i],
            str[i..],
        };
    }
    unreachable;
}

test "splitFmtString" {
    try testing.expectEqualStrings("{} {} ", splitFmtString("{} {} {}", 2)[0]);
    try testing.expectEqualStrings("{}", splitFmtString("{} {} {}", 2)[1]);
    try testing.expectEqualStrings("{} {{}} {} ", splitFmtString("{} {{}} {} {}", 2)[0]);
    try testing.expectEqualStrings("{}", splitFmtString("{} {{}} {} {}", 2)[1]);
}

test "void" {
    const Buf = FmtBuf("a {} a", meta.Tuple(&.{void}));
    var buf = Buf{};
    try testing.expectEqualStrings(
        fmt.comptimePrint("a {} a", .{{}}),
        buf.format(.{{}}),
    );
}

test "bool" {
    const Buf = FmtBuf("{} {}", meta.Tuple(&.{ bool, bool }));
    var buf = Buf{};

    inline for ([_]struct { a: bool, b: bool }{
        .{ .a = false, .b = false },
        .{ .a = true, .b = false },
        .{ .a = false, .b = true },
        .{ .a = true, .b = true },
    }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("{} {}", .{ t.a, t.b }),
            buf.format(.{ t.a, t.b }),
        );
    }
}

test "int" {
    const Buf = FmtBuf("{} {}", meta.Tuple(&.{ u16, i16 }));
    var buf = Buf{};

    inline for ([_]struct { a: u16, b: i16 }{
        .{ .a = math.minInt(u16), .b = math.minInt(i16) },
        .{ .a = math.maxInt(u16), .b = math.minInt(i16) },
        .{ .a = math.minInt(u16), .b = math.maxInt(i16) },
        .{ .a = math.maxInt(u16), .b = math.maxInt(i16) },
    }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("{} {}", .{ t.a, t.b }),
            buf.format(.{ t.a, t.b }),
        );
    }
}

test "array - string" {
    const Buf = FmtBuf("a {s} a", meta.Tuple(&.{[8]u8}));
    var buf = Buf{};

    inline for ([_][8]u8{"abcdefgh".*}) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {s} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "array - int" {
    const Buf = FmtBuf("a {any} a", meta.Tuple(&.{[4]u16}));
    var buf = Buf{};

    inline for ([_][4]u16{
        [_]u16{ math.minInt(u16), math.minInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.maxInt(u16), math.minInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.maxInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.minInt(u16), math.maxInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.minInt(u16), math.minInt(u16), math.maxInt(u16) },
        [_]u16{ math.maxInt(u16), math.maxInt(u16), math.maxInt(u16), math.maxInt(u16) },
    }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {any} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "vector" {
    const V = meta.Vector(4, u16);
    const Buf = FmtBuf("a {any} a", meta.Tuple(&.{V}));
    var buf = Buf{};

    inline for ([_]V{
        [_]u16{ math.minInt(u16), math.minInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.maxInt(u16), math.minInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.maxInt(u16), math.minInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.minInt(u16), math.maxInt(u16), math.minInt(u16) },
        [_]u16{ math.minInt(u16), math.minInt(u16), math.minInt(u16), math.maxInt(u16) },
        [_]u16{ math.maxInt(u16), math.maxInt(u16), math.maxInt(u16), math.maxInt(u16) },
    }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {any} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "ptr - string" {
    const Buf = FmtBuf("a {s} a", meta.Tuple(&.{*const [8]u8}));
    var buf = Buf{};

    inline for ([_]*const [8]u8{"abcdefgh"}) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {s} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "struct" {
    const S = struct { a: u8, b: u16, c: u32 };
    const Buf = FmtBuf("a {} a", meta.Tuple(&.{S}));
    var buf = Buf{};

    inline for ([_]S{
        .{ .a = math.minInt(u8), .b = math.minInt(u16), .c = math.minInt(u32) },
        .{ .a = math.maxInt(u8), .b = math.minInt(u16), .c = math.minInt(u32) },
        .{ .a = math.minInt(u8), .b = math.maxInt(u16), .c = math.minInt(u32) },
        .{ .a = math.minInt(u8), .b = math.minInt(u16), .c = math.maxInt(u32) },
        .{ .a = math.maxInt(u8), .b = math.maxInt(u16), .c = math.maxInt(u32) },
    }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "enum" {
    const E = enum { a, bb, ccc, dddd };
    const Buf = FmtBuf("a {} a", meta.Tuple(&.{E}));
    var buf = Buf{};

    inline for ([_]E{ .a, .bb, .ccc, .dddd }) |t| {
        try testing.expectEqualStrings(
            fmt.comptimePrint("a {} a", .{t}),
            buf.format(.{t}),
        );
    }
}

test "partial" {
    const S = struct { a: u8, b: u16, c: u32 };
    const Buf = FmtBuf("{} {} {}", meta.Tuple(&.{ u8, u16, u32 }));
    var buf = Buf{};

    inline for ([_]S{
        .{ .a = math.minInt(u8), .b = math.minInt(u16), .c = math.minInt(u32) },
        .{ .a = math.maxInt(u8), .b = math.minInt(u16), .c = math.minInt(u32) },
        .{ .a = math.minInt(u8), .b = math.maxInt(u16), .c = math.minInt(u32) },
        .{ .a = math.minInt(u8), .b = math.minInt(u16), .c = math.maxInt(u32) },
        .{ .a = math.maxInt(u8), .b = math.maxInt(u16), .c = math.maxInt(u32) },
    }) |t| {
        const part1 = buf.partialFormat(1, .{t.a});
        var part2 = part1.partialFormat(1, .{t.b});
        try testing.expectEqualStrings(
            fmt.comptimePrint("{} {} {}", .{ t.a, t.b, t.c }),
            part2.format(.{t.c}),
        );
    }
}
