const std = @import("std");

const RateLimit = struct {
    used_percentage: ?f64 = null,
};

const RateLimits = struct {
    five_hour: ?RateLimit = null,
};

const ContextWindow = struct {
    used_percentage: ?f64 = null,
};

const Model = struct {
    display_name: ?[]const u8 = null,
};

const StatusInput = struct {
    cwd: ?[]const u8 = null,
    model: ?Model = null,
    context_window: ?ContextWindow = null,
    rate_limits: ?RateLimits = null,
};

fn gitBranch(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8) ?[]const u8 {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD" },
    }) catch return null;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }

    const trimmed = std.mem.trimEnd(u8, result.stdout, "\n\r ");
    return gpa.dupe(u8, trimmed) catch null;
}

fn writeStatusLine(writer: *std.Io.Writer, model: []const u8, work_dir: []const u8, branch: []const u8, ctx_pct: f64, session_pct: f64) !void {
    try writer.print("[{s}] {s} ({s}) | {d:.0}% context | {d:.0}% limit\n", .{
        model, work_dir, branch, ctx_pct, session_pct,
    });
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(gpa, .limited(1024 * 1024));
    defer gpa.free(input);

    const parsed = std.json.parseFromSlice(
        StatusInput,
        gpa,
        input,
        .{ .ignore_unknown_fields = true },
    ) catch null;
    defer if (parsed) |p| p.deinit();
    const data: StatusInput = if (parsed) |p| p.value else .{};

    const model = if (data.model) |m| m.display_name orelse "?" else "?";
    const cwd = data.cwd orelse "";
    const work_dir = if (cwd.len > 0) std.fs.path.basename(cwd) else "?";

    const ctx_pct: f64 = if (data.context_window) |cw| cw.used_percentage orelse 0.0 else 0.0;
    const session_pct: f64 = if (data.rate_limits) |rl|
        if (rl.five_hour) |fh| fh.used_percentage orelse 0.0 else 0.0
    else
        0.0;

    const branch = gitBranch(gpa, io, cwd);
    defer if (branch) |b| gpa.free(b);

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    try writeStatusLine(&stdout_writer.interface, model, work_dir, branch orelse "?", ctx_pct, session_pct);
    try stdout_writer.interface.flush();
}

test "writeStatusLine produces correct output" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeStatusLine(&w, "claude-opus-4-7", "agent-hud", "main", 45.0, 30.0);
    try std.testing.expectEqualStrings(
        "[claude-opus-4-7] agent-hud (main) | 45% context | 30% limit\n",
        w.buffered(),
    );
}

test "writeStatusLine with all unknowns" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeStatusLine(&w, "?", "?", "?", 0.0, 0.0);
    try std.testing.expectEqualStrings(
        "[?] ? (?) | 0% context | 0% limit\n",
        w.buffered(),
    );
}

test "StatusInput parses full JSON payload" {
    const json =
        \\{"cwd":"/home/user/agent-hud","model":{"display_name":"claude-opus-4-7"},"context_window":{"used_percentage":45.0},"rate_limits":{"five_hour":{"used_percentage":30.0}}}
    ;
    const parsed = try std.json.parseFromSlice(StatusInput, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const d = parsed.value;
    try std.testing.expectEqualStrings("/home/user/agent-hud", d.cwd.?);
    try std.testing.expectEqualStrings("claude-opus-4-7", d.model.?.display_name.?);
    try std.testing.expectEqual(45.0, d.context_window.?.used_percentage.?);
    try std.testing.expectEqual(30.0, d.rate_limits.?.five_hour.?.used_percentage.?);
}

test "StatusInput with empty JSON gives all-null fields" {
    const parsed = try std.json.parseFromSlice(StatusInput, std.testing.allocator, "{}", .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const d = parsed.value;
    try std.testing.expect(d.cwd == null);
    try std.testing.expect(d.model == null);
    try std.testing.expect(d.context_window == null);
    try std.testing.expect(d.rate_limits == null);
}

test "StatusInput ignores unknown fields" {
    const json =
        \\{"cwd":"/tmp","unknown_key":"ignored","model":{"display_name":"x","extra":99}}
    ;
    const parsed = try std.json.parseFromSlice(StatusInput, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("/tmp", parsed.value.cwd.?);
    try std.testing.expectEqualStrings("x", parsed.value.model.?.display_name.?);
}
