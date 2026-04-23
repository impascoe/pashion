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

        if (std.mem.eql(u8, argv.items[0], "exit")) {
            break;
        }

        if (std.mem.eql(u8, argv.items[0], "cd")) {
            if (argv.items.len < 2) {
                // TODO:
                // // use juicy main to get env vars
                // const home_dir = std.process.getEnvVarOwned(gpa, "HOME") catch |env_err| {
                //     stdout.interface.print("cd: HOME not set: {any}\n", .{env_err}) catch {};
                //     stdout.interface.flush() catch {};
                //     continue;
                // };
                // defer gpa.free(home_dir);

                // // change to std.Io.threaded.chdir
                // if (std.posix.chdir(home_dir)) |_| {} else |err| {
                //     stdout.interface.print("cd: {s}: {any}\n", .{ home_dir, err }) catch {};
                //     stdout.interface.flush() catch {};
                // }
            } else {
                const target = argv.items[1];

                if (std.Io.Threaded.chdir(target)) {} else |err| {
                    switch (err) {
                        error.NotDir => {
                            stdout.interface.print("pash: cd: '{s}' is not a directory \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.SymLinkLoop => {
                            stdout.interface.print("pash: cd: '{s}' Too many levels of symbolic links \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.SystemResources => {
                            stdout.interface.print("pash: cd: '{s}' Cannot allocate memory to process \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.NameTooLong => {
                            stdout.interface.print("pash: cd: '{s}' File name is too long \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.FileNotFound => {
                            stdout.interface.print("pash: cd: '{s}' File or directory not found \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.FileSystem => {
                            stdout.interface.print("pash: cd: '{s}' I/O operation failed \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.BadPathName => {
                            stdout.interface.print("pash: cd: '{s}' Illegal byte sequence encountered \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.Canceled => {
                            stdout.interface.print("pash: cd: Process has been cancelled \n", .{}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.AccessDenied => {
                            stdout.interface.print("pash: cd: '{s}' Permission denied \n", .{target}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                        error.Unexpected => {
                            stdout.interface.print("pash: cd: Unknown error encountered \n", .{}) catch {};
                            std.log.warn("cd: {s}: {any} \n", .{ target, err });
                        },
                    }
                    stdout.interface.flush() catch {};
                }
            }

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
            else => std.log.err("{any}", .{err}),
        }
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
