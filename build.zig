const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const module = b.addModule("fmtbuf", .{ .source_file = .{ .path = "fmtbuf.zig" } });

    const test_step = b.step("test", "Run all tests in all modes.");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "fmtbuf.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&tests.run().step);

    const example_step = b.step("examples", "Build examples");
    const example = b.addTest(.{
        .root_source_file = .{ .path = "example/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    example.addModule("fmtbuf", module);
    example_step.dependOn(&example.step);

    const readme_step = b.step("readme", "Remake README.");
    const readme = readMeStep(b);
    readme.dependOn(example_step);
    readme_step.dependOn(readme);

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_step);
    all_step.dependOn(example_step);
    all_step.dependOn(readme_step);

    b.default_step.dependOn(all_step);
}

fn readMeStep(b: *std.Build) *std.Build.Step {
    const s = b.allocator.create(std.build.Step) catch unreachable;
    s.* = std.build.Step.init(.{
        .id = .custom,
        .name = "ReadMeStep",
        .owner = b,
        .makeFn = struct {
            fn make(step: *std.build.Step, _: *std.Progress.Node) anyerror!void {
                @setEvalBranchQuota(10000);
                _ = step;
                const file = try std.fs.cwd().createFile("README.md", .{});
                const stream = file.writer();
                try stream.print(@embedFile("example/README.md.template"), .{
                    @embedFile("example/example.zig"),
                });
            }
        }.make,
    });
    return s;
}
