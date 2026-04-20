const std = @import("std");

pub fn main(init: std.process.Init) void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [1024]u8 = undefined;
    var out_buf: [1024]u8 = undefined;

    // var stdin = std.Io.File.stdin().reader(io, &in_buf);
    var stdout = std.Io.File.stdout().writer(io, &out_buf);

    while (readCommand(io, &in_buf, &out_buf)) |res| {
        const trimmed = std.mem.trim(u8, res, "\r\n");

        if (trimmed.len == 0) continue;
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(gpa);

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        while (it.next()) |tok| argv.append(gpa, tok) catch {};

        if (argv.items.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "exit")) {
            break;
        }

        if (std.process.run(gpa, io, .{ .argv = argv.items })) |result| {
            defer gpa.free(result.stdout);
            defer gpa.free(result.stderr);

            stdout.interface.print("{s}", .{result.stdout}) catch {};
            stdout.interface.flush() catch {};

            if (result.stderr.len != 0) {
                stdout.interface.print("{s}", .{result.stderr}) catch {};
                stdout.interface.flush() catch {};
            }
        } else |err| switch (err) {
            error.FileNotFound => {
                stdout.interface.print("pash: command not found: {s}\n", .{argv.items[0]}) catch {};
                stdout.interface.flush() catch {};
            },
            else => std.log.err("{any}", .{err}),
        }

        // if (std.mem.eql(u8, trimmed, "ls")) {}
    } else |err| {
        std.log.err("{any}", .{err});
    }
}

fn readCommand(io: std.Io, in_buf: *[1024]u8, out_buf: *[1024]u8) ![]u8 {
    var stdin = std.Io.File.stdin().reader(io, in_buf);
    var stdout = std.Io.File.stdout().writer(io, out_buf);

    try stdout.interface.print("> ", .{});
    try stdout.interface.flush();

    const res = try stdin.interface.takeDelimiter('\n');
    return res orelse error.ReadFailed;
}
