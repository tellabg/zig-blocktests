const std = @import("std");
const phant = @import("phant");
const Fixture = phant.spec_tests.Fixture;
const FixtureTest = phant.spec_tests.FixtureTest;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: blocktests <path-to-fixtures-dir-or-file>\n", .{});
        std.process.exit(1);
    }

    const path = args[1];

    var passed: u64 = 0;
    var failed: u64 = 0;
    var skipped: u64 = 0;

    std.debug.print("Running block tests from: {s}\n", .{path});

    const file_stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Path not found: {s}\n", .{path});
            std.process.exit(1);
        },
        else => return err,
    };

    if (file_stat.kind == .directory) {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const result = processTestFile(allocator, dir, entry.name);
                passed += result.passed;
                failed += result.failed;
                skipped += result.skipped;
            }
        }
    } else if (file_stat.kind == .file) {
        const basename = std.fs.path.basename(path);
        const dirname = std.fs.path.dirname(path) orelse ".";

        var parent_dir = try std.fs.cwd().openDir(dirname, .{});
        defer parent_dir.close();

        const result = processTestFile(allocator, parent_dir, basename);
        passed += result.passed;
        failed += result.failed;
        skipped += result.skipped;
    }

    std.debug.print("\n=== Results ===\n", .{});
    std.debug.print("Passed:  {}\n", .{passed});
    std.debug.print("Failed:  {}\n", .{failed});
    std.debug.print("Skipped: {}\n", .{skipped});
    std.debug.print("Total:   {}\n", .{passed + failed + skipped});

    if (failed > 0) {
        std.process.exit(1);
    }
}

const TestResult = struct {
    passed: u64,
    failed: u64,
    skipped: u64,
};

fn processTestFile(allocator: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8) TestResult {
    var result = TestResult{ .passed = 0, .failed = 0, .skipped = 0 };

    std.debug.print("Processing: {s}\n", .{filename});

    const file_content = dir.readFileAlloc(allocator, filename, 1024 * 1024 * 50) catch |err| {
        std.debug.print("  Error reading file: {}\n", .{err});
        result.failed += 1;
        return result;
    };
    defer allocator.free(file_content);

    var fixture = Fixture.fromBytes(allocator, file_content) catch |err| {
        std.debug.print("  Error parsing fixture: {}\n", .{err});
        result.failed += 1;
        return result;
    };
    defer fixture.deinit();

    var it = fixture.tests.value.map.iterator();
    while (it.next()) |entry| {
        const test_name = entry.key_ptr.*;
        const test_case = entry.value_ptr;

        std.debug.print("  Test: {s} (network: {s}) ... ", .{ test_name, test_case.network });

        if (test_case.run(allocator)) |success| {
            if (success) {
                std.debug.print("PASS\n", .{});
                result.passed += 1;
            } else {
                std.debug.print("FAIL (run returned false)\n", .{});
                result.failed += 1;
            }
        } else |err| {
            std.debug.print("FAIL ({s})\n", .{@errorName(err)});
            result.failed += 1;
        }
    }

    return result;
}
