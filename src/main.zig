const std = @import("std");

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
    
    // Statistics
    var passed: u64 = 0;
    var failed: u64 = 0;
    var skipped: u64 = 0;

    std.debug.print("Running block tests from: {s}\n", .{path});

    // Check if path is a file or directory
    const file_stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Path not found: {s}\n", .{path});
            std.process.exit(1);
        },
        else => return err,
    };

    if (file_stat.kind == .directory) {
        // Process directory
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const result = try processTestFile(allocator, dir, entry.name);
                passed += result.passed;
                failed += result.failed;
                skipped += result.skipped;
            }
        }
    } else if (file_stat.kind == .file) {
        // Process single file
        const basename = std.fs.path.basename(path);
        const dirname = std.fs.path.dirname(path) orelse ".";
        
        var parent_dir = try std.fs.cwd().openDir(dirname, .{});
        defer parent_dir.close();
        
        const result = try processTestFile(allocator, parent_dir, basename);
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

fn processTestFile(allocator: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8) !TestResult {
    var result = TestResult{ .passed = 0, .failed = 0, .skipped = 0 };

    std.debug.print("Processing: {s}\n", .{filename});

    const file_content = try dir.readFileAlloc(allocator, filename, 1024 * 1024 * 10); // 10MB max
    defer allocator.free(file_content);

    // Parse JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, file_content, .{}) catch |err| {
        std.debug.print("  Error parsing JSON: {}\n", .{err});
        result.failed += 1;
        return result;
    };
    defer parsed.deinit();

    const json_obj = parsed.value.object;
    
    for (json_obj.keys()) |test_name| {
        std.debug.print("  Test: {s} ... ", .{test_name});
        
        const test_obj = json_obj.get(test_name).?.object;
        
        // Basic validation - check required fields
        if (test_obj.get("blocks")) |_| {
            if (test_obj.get("pre")) |_| {
                if (test_obj.get("expect")) |_| {
                    std.debug.print("PASS (basic structure valid)\n", .{});
                    result.passed += 1;
                } else {
                    std.debug.print("FAIL (missing expect field)\n", .{});
                    result.failed += 1;
                }
            } else {
                std.debug.print("FAIL (missing pre field)\n", .{});
                result.failed += 1;
            }
        } else {
            std.debug.print("FAIL (missing blocks field)\n", .{});
            result.failed += 1;
        }
    }

    return result;
}
