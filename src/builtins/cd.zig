const std = @import("std");

const flags = enum { L_FLAG, P_FLAG };

pub fn cd(io: std.Io, gpa: std.mem.Allocator, environ: *std.process.Environ.Map, argv: [][]const u8) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;

    var print_path: bool = false;

    var cdpath_path: ?[]u8 = null;
    defer if (cdpath_path) |path| gpa.free(path);

    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    var stderr = std.Io.File.stderr().writer(io, &err_buf);

    if (environ.get("PWD") == null) {
        const cwd = try std.process.currentPathAlloc(io, gpa);
        defer gpa.free(cwd);
        try environ.put("PWD", cwd);
    }

    const current_dir = environ.get("PWD").?;

    if (argv.len < 2) {
        const home_dir = environ.get("HOME") orelse {
            try stderr.interface.print("pash: cd: $HOME not set \n", .{});
            try stderr.interface.flush();
            return 1;
        };

        if (std.Io.Threaded.chdir(home_dir)) {
            return 0;
        } else |err| {
            try stderr.interface.print("cd: {s}: {any}\n", .{ home_dir, err });
            try stderr.interface.flush();
            return 1;
        }
    } else {
        var flag = flags.L_FLAG;
        var target = argv[1];
        var curpath = target;

        if (std.mem.startsWith(u8, target, "-")) {
            if (std.mem.eql(u8, "-", target)) {
                const prev_dir = environ.get("OLDPWD") orelse {
                    return 1;
                };

                curpath = prev_dir;
                print_path = true;
            } else if (!(argv.len < 3)) {
                if (std.mem.endsWith(u8, target, "P")) {
                    flag = flags.P_FLAG;
                    target = argv[2];
                    curpath = target;
                } else if (std.mem.endsWith(u8, target, "L")) {
                    flag = flags.L_FLAG;
                    target = argv[2];
                    curpath = target;
                }
            } else {
                try stderr.interface.print("pash: cd: No file or directory specified\n", .{});
                try stderr.interface.flush();
                return 1;
            }
        }

        if (std.mem.eql(u8, "~", target)) {
            const home_dir = environ.get("HOME") orelse {
                try stderr.interface.print("pash: cd: $HOME not set \n", .{});
                try stderr.interface.flush();
                return 1;
            };
            curpath = home_dir;
        } else if (std.mem.startsWith(u8, target, "/")) {
            curpath = target;
        } else if (std.mem.startsWith(u8, target, ".") or std.mem.startsWith(u8, target, "..")) {} else {
            cdpath_path = try check_cdpath(io, gpa, environ.get("CDPATH") orelse "", target);

            if (cdpath_path) |path| {
                curpath = path;
                print_path = true;
                // try stdout.interface.print("{s}\n", .{curpath});
                // try stdout.interface.flush();
            }
        }

        if (flag == flags.P_FLAG) {
            try stdout.interface.print("P flag has been set\n", .{});
            try stdout.interface.flush();
        }

        if (std.Io.Threaded.chdir(curpath)) {
            if (print_path) {
                try stdout.interface.print("{s}\n", .{curpath});
                try stdout.interface.flush();
            }

            try environ.put("OLDPWD", current_dir);

            const path = try std.process.currentPathAlloc(io, gpa);
            defer gpa.free(path);

            try environ.put("PWD", path);
            return 0;
        } else |err| {
            switch (err) {
                error.NotDir => {
                    try stderr.interface.print("pash: cd: '{s}'  No such file or directory\n", .{target});
                },
                error.SymLinkLoop => {
                    try stderr.interface.print("pash: cd: '{s}' Too many levels of symbolic links\n", .{target});
                },
                error.SystemResources => {
                    try stderr.interface.print("pash: cd: '{s}' Cannot allocate memory to process\n", .{target});
                },
                error.NameTooLong => {
                    try stderr.interface.print("pash: cd: '{s}' File name is too long\n", .{target});
                },
                error.FileNotFound => {
                    try stderr.interface.print("pash: cd: '{s}' File or directory not found\n", .{target});
                },
                error.FileSystem => {
                    try stderr.interface.print("pash: cd: '{s}' I/O operation failed\n", .{target});
                },
                error.BadPathName => {
                    try stderr.interface.print("pash: cd: '{s}' Illegal byte sequence encountered\n", .{target});
                },
                error.Canceled => {
                    try stderr.interface.print("pash: cd: Process has been cancelled\n", .{});
                },
                error.AccessDenied => {
                    try stderr.interface.print("pash: cd: '{s}' Permission denied\n", .{target});
                },
                error.Unexpected => {
                    try stderr.interface.print("pash: cd: Unknown error encountered\n", .{});
                },
            }
            try stderr.interface.flush();
            return 1;
        }
    }
}

fn check_cdpath(io: std.Io, gpa: std.mem.Allocator, cdpath: []const u8, target_path: []const u8) !?[]u8 {
    var path_iterator = std.mem.splitAny(u8, cdpath, ":");
    var curpath: []u8 = undefined;

    while (path_iterator.next()) |path| {
        if (path.len == 0) {
            curpath = try gpa.dupe(u8, target_path);
        } else if (std.mem.endsWith(u8, path, "/")) {
            curpath = try std.mem.concat(gpa, u8, &[_][]const u8{ path, target_path });
        } else {
            curpath = try std.mem.concat(gpa, u8, &[_][]const u8{ path, "/", target_path });
        }

        if (std.Io.Dir.openDir(std.Io.Dir.cwd(), io, curpath, .{})) |dir| {
            std.Io.Dir.close(dir, io);
            return curpath;
        } else |err| {
            gpa.free(curpath);
            switch (err) {
                error.FileNotFound,
                error.NotDir,
                error.AccessDenied,
                error.PermissionDenied,
                error.SymLinkLoop,
                error.BadPathName,
                error.NameTooLong,
                error.NetworkNotFound,
                => continue,
                else => return err,
            }
        }
    }
    return null;
}
