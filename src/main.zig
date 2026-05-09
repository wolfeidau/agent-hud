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

const Cost = struct {
    total_cost_usd: ?f64 = null,
};

const StatusInput = struct {
    cwd: ?[]const u8 = null,
    model: ?Model = null,
    context_window: ?ContextWindow = null,
    rate_limits: ?RateLimits = null,
    cost: ?Cost = null,

    fn modelName(self: StatusInput) []const u8 {
        return if (self.model) |m| m.display_name orelse "?" else "?";
    }

    fn workDir(self: StatusInput) []const u8 {
        const cwd = self.cwd orelse return "?";
        return if (cwd.len > 0) std.fs.path.basename(cwd) else "?";
    }

    fn ctxPct(self: StatusInput) f64 {
        return if (self.context_window) |cw| cw.used_percentage orelse 0.0 else 0.0;
    }

    fn sessionPct(self: StatusInput) ?f64 {
        return if (self.rate_limits) |rl|
            if (rl.five_hour) |fh| fh.used_percentage else null
        else
            null;
    }

    fn costUsd(self: StatusInput) f64 {
        return if (self.cost) |c| c.total_cost_usd orelse 0.0 else 0.0;
    }
};

const cyan = "\x1b[36m";
const green = "\x1b[32m";
const yellow = "\x1b[33m";
const red = "\x1b[31m";
const reset = "\x1b[0m";

fn pctColor(pct: f64) []const u8 {
    if (pct >= 80.0) return red;
    if (pct >= 50.0) return yellow;
    return green;
}

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

fn writeStatusLine(writer: *std.Io.Writer, data: StatusInput, branch: []const u8) !void {
    const ctx = data.ctxPct();
    try writer.print("{s}[{s}]{s} {s} ({s}{s}{s}) | {s}{d:.0}%{s} context | ", .{
        cyan, data.modelName(), reset,
        data.workDir(),
        yellow, branch, reset,
        pctColor(ctx), ctx, reset,
    });
    if (data.sessionPct()) |pct| {
        try writer.print("{s}{d:.0}%{s} limit\n", .{ pctColor(pct), pct, reset });
    } else {
        try writer.print("${d:.2}\n", .{data.costUsd()});
    }
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

    const branch = gitBranch(gpa, io, data.cwd orelse "");
    defer if (branch) |b| gpa.free(b);

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    try writeStatusLine(&stdout_writer.interface, data, branch orelse "?");
    try stdout_writer.interface.flush();
}

test "writeStatusLine subscriber shows rate limit" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const data = StatusInput{
        .model = .{ .display_name = "claude-opus-4-7" },
        .cwd = "/home/user/agent-hud",
        .context_window = .{ .used_percentage = 45.0 },
        .rate_limits = .{ .five_hour = .{ .used_percentage = 30.0 } },
        .cost = .{ .total_cost_usd = 1.23 },
    };
    try writeStatusLine(&w, data, "main");
    try std.testing.expectEqualStrings(
        "\x1b[36m[claude-opus-4-7]\x1b[0m agent-hud (\x1b[33mmain\x1b[0m) | \x1b[32m45%\x1b[0m context | \x1b[32m30%\x1b[0m limit\n",
        w.buffered(),
    );
}

test "writeStatusLine team/enterprise shows cost" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const data = StatusInput{
        .model = .{ .display_name = "claude-opus-4-7" },
        .cwd = "/home/user/agent-hud",
        .context_window = .{ .used_percentage = 45.0 },
        .cost = .{ .total_cost_usd = 1.23 },
    };
    try writeStatusLine(&w, data, "main");
    try std.testing.expectEqualStrings(
        "\x1b[36m[claude-opus-4-7]\x1b[0m agent-hud (\x1b[33mmain\x1b[0m) | \x1b[32m45%\x1b[0m context | $1.23\n",
        w.buffered(),
    );
}

test "writeStatusLine all unknowns shows cost zero" {
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeStatusLine(&w, .{}, "?");
    try std.testing.expectEqualStrings(
        "\x1b[36m[?]\x1b[0m ? (\x1b[33m?\x1b[0m) | \x1b[32m0%\x1b[0m context | $0.00\n",
        w.buffered(),
    );
}

test "StatusInput methods derive correct values" {
    const data = StatusInput{
        .model = .{ .display_name = "Opus" },
        .cwd = "/home/user/agent-hud",
        .context_window = .{ .used_percentage = 50.0 },
        .rate_limits = .{ .five_hour = .{ .used_percentage = 20.0 } },
        .cost = .{ .total_cost_usd = 0.42 },
    };
    try std.testing.expectEqualStrings("Opus", data.modelName());
    try std.testing.expectEqualStrings("agent-hud", data.workDir());
    try std.testing.expectEqual(50.0, data.ctxPct());
    try std.testing.expectEqual(20.0, data.sessionPct().?);
    try std.testing.expectEqual(0.42, data.costUsd());
}

test "StatusInput methods handle missing fields" {
    const data = StatusInput{};
    try std.testing.expectEqualStrings("?", data.modelName());
    try std.testing.expectEqualStrings("?", data.workDir());
    try std.testing.expectEqual(0.0, data.ctxPct());
    try std.testing.expect(data.sessionPct() == null);
    try std.testing.expectEqual(0.0, data.costUsd());
}

test "StatusInput parses full JSON payload" {
    const json =
        \\{"cwd":"/home/user/agent-hud","model":{"display_name":"claude-opus-4-7"},"context_window":{"used_percentage":45.0},"rate_limits":{"five_hour":{"used_percentage":30.0}},"cost":{"total_cost_usd":1.23}}
    ;
    const parsed = try std.json.parseFromSlice(StatusInput, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const d = parsed.value;
    try std.testing.expectEqualStrings("/home/user/agent-hud", d.cwd.?);
    try std.testing.expectEqualStrings("claude-opus-4-7", d.model.?.display_name.?);
    try std.testing.expectEqual(45.0, d.context_window.?.used_percentage.?);
    try std.testing.expectEqual(30.0, d.rate_limits.?.five_hour.?.used_percentage.?);
    try std.testing.expectEqual(1.23, d.cost.?.total_cost_usd.?);
}

test "StatusInput with empty JSON gives all-null fields" {
    const parsed = try std.json.parseFromSlice(StatusInput, std.testing.allocator, "{}", .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const d = parsed.value;
    try std.testing.expect(d.cwd == null);
    try std.testing.expect(d.model == null);
    try std.testing.expect(d.context_window == null);
    try std.testing.expect(d.rate_limits == null);
    try std.testing.expect(d.cost == null);
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
