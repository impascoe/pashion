const std = @import("std");
const cd = @import("builtins/cd.zig").cd;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const io = init.io;

    var in_buf: [4096]u8 = undefined;
    var out_buf: [4096]u8 = undefined;

    var environ_map = try init.minimal.environ.createMap(gpa);
    defer environ_map.deinit();

    // var stdin = std.Io.File.stdin().reader(io, &in_buf);
    var stdout = std.Io.File.stdout().writer(io, &out_buf);

    for (environ_map.keys(), environ_map.values()) |key, value| {
        try stdout.interface.print("env: {s}={s}\n", .{ key, value });
        stdout.interface.flush() catch {};
    }

    var args = init.minimal.args.iterate();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            stdout.interface.print("pash 0.0.1\n", .{}) catch {};
            stdout.interface.flush() catch {};
            return;
        } else {
            // std.log.info("arg: {s}", .{arg});
        }
    }
    while (true) {
        const res = readCommand(io, &in_buf, &out_buf) catch |err| switch (err) {
            error.StreamTooLong => {
                stdout.interface.print("pash: input line too long\n", .{}) catch {};
                stdout.interface.flush() catch {};
                continue;
            },
            else => {
                stdout.interface.print("{any}", .{err}) catch {};
                stdout.interface.flush() catch {};
                break;
            },
        };
        const trimmed = std.mem.trim(u8, res, "\r\n");

        if (trimmed.len == 0) continue;
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(gpa);

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        while (it.next()) |tok| argv.append(gpa, tok) catch {
            stdout.interface.print("pash: out of memory\n", .{}) catch {};
            stdout.interface.flush() catch {};
            continue;
        };

        if (argv.items.len == 0) continue;

        if (std.mem.eql(u8, argv.items[0], "exit")) {
            std.process.cleanExit(io);
            return;
        }

        if (std.mem.eql(u8, argv.items[0], "cd")) {
            cd(io, &environ_map, argv.items) catch {};
            continue;
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
            else => stdout.interface.print("{any}", .{err}) catch {},
        }
    }
    stdout.interface.flush() catch {};
}

fn readCommand(io: std.Io, in_buf: *[4096]u8, out_buf: *[4096]u8) ![]u8 {
    var stdin = std.Io.File.stdin().reader(io, in_buf);
    var stdout = std.Io.File.stdout().writer(io, out_buf);

    try stdout.interface.print("#> ", .{});
    try stdout.interface.flush();

    const result = stdin.interface.takeDelimiter('\n') catch |err| switch (err) {
        error.StreamTooLong => {
            _ = stdin.interface.discardDelimiterInclusive('\n') catch |erro| switch (erro) {
                error.EndOfStream => {
                    return erro;
                },
                else => {
                    return erro;
                },
            };
            return error.StreamTooLong;
        },
        else => return err,
    };

    return result orelse error.ReadFailed;
}
