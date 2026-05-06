const std = @import("std");

pub fn cd(io: std.Io, gpa: std.mem.Allocator, environ: *std.process.Environ.Map, argv: [][]const u8) !void {
    var stdout_buf: [4096]u8 = undefined;
    var cdpath_path: ?[]u8 = null;
    defer if (cdpath_path) |path| gpa.free(path);

    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    const current_dir = environ.get("PWD") orelse return;

    if (argv.len < 2) {
        const home_dir = environ.get("HOME") orelse {
            try stdout.interface.print("pash: cd: $HOME not set \n", .{});
            try stdout.interface.flush();
            return;
        };

        if (std.Io.Threaded.chdir(home_dir)) {} else |err| {
            try stdout.interface.print("cd: {s}: {any}\n", .{ home_dir, err });
            try stdout.interface.flush();
        }
    } else {
        const target = argv[1];
        var curpath = target;

        if (std.mem.eql(u8, "~", target)) {
            const home_dir = environ.get("HOME") orelse {
                try stdout.interface.print("pash: cd: $HOME not set \n", .{});
                try stdout.interface.flush();
                return;
            };
            curpath = home_dir;
        } else if (std.mem.eql(u8, "-", target)) {
            const prev_dir = environ.get("OLDPWD") orelse {
                return;
            };

            curpath = prev_dir;

            try stdout.interface.print("{s}\n", .{curpath});
            try stdout.interface.flush();
        } else if (std.mem.startsWith(u8, target, "/")) {
            try stdout.interface.print("{s}\n", .{target});
            try stdout.interface.print("Skipping the CDPATH section\n", .{});
            try stdout.interface.flush();
            curpath = target;
        } else if (std.mem.startsWith(u8, target, ".")) {} else {
            cdpath_path = try check_cdpath(io, gpa, environ.get("CDPATH") orelse "", target);
            if (cdpath_path) |path| {
                curpath = path;
                try stdout.interface.print("{s}\n", .{curpath});
                try stdout.interface.flush();
            }
        }

        // use std.Io.Dir.openDir to check if directories exist for CDPATH
        // std.mem.endsWith(u8, target, "/")
        // std.mem.concat(allocator: Allocator, comptime T: type, slices: []const []const T)

        if (std.Io.Threaded.chdir(curpath)) {
            try environ.put("OLDPWD", current_dir);

            const path = try std.process.currentPathAlloc(io, gpa);
            defer gpa.free(path);

            try environ.put("PWD", path);
        } else |err| {
            switch (err) {
                error.NotDir => {
                    try stdout.interface.print("pash: cd: '{s}'  No such file or directory\n", .{target});
                },
                error.SymLinkLoop => {
                    try stdout.interface.print("pash: cd: '{s}' Too many levels of symbolic links\n", .{target});
                },
                error.SystemResources => {
                    try stdout.interface.print("pash: cd: '{s}' Cannot allocate memory to process\n", .{target});
                },
                error.NameTooLong => {
                    try stdout.interface.print("pash: cd: '{s}' File name is too long\n", .{target});
                },
                error.FileNotFound => {
                    try stdout.interface.print("pash: cd: '{s}' File or directory not found\n", .{target});
                },
                error.FileSystem => {
                    try stdout.interface.print("pash: cd: '{s}' I/O operation failed\n", .{target});
                },
                error.BadPathName => {
                    try stdout.interface.print("pash: cd: '{s}' Illegal byte sequence encountered\n", .{target});
                },
                error.Canceled => {
                    try stdout.interface.print("pash: cd: Process has been cancelled\n", .{});
                },
                error.AccessDenied => {
                    try stdout.interface.print("pash: cd: '{s}' Permission denied\n", .{target});
                },
                error.Unexpected => {
                    try stdout.interface.print("pash: cd: Unknown error encountered\n", .{});
                },
            }
            try stdout.interface.flush();
        }
    }
}

fn check_cdpath(io: std.Io, gpa: std.mem.Allocator, cdpath: []const u8, target_path: []const u8) !?[]u8 {
    var path_iterator = std.mem.splitAny(u8, cdpath, ":");
    var cd_path: []u8 = undefined;

    while (path_iterator.next()) |path| {
        if (path.len == 0) {
            cd_path = try gpa.dupe(u8, target_path);
        } else if (std.mem.endsWith(u8, path, "/")) {
            cd_path = try std.mem.concat(gpa, u8, &[_][]const u8{ path, target_path });
        } else {
            cd_path = try std.mem.concat(gpa, u8, &[_][]const u8{ path, "/", target_path });
        }

        if (std.Io.Dir.openDir(std.Io.Dir.cwd(), io, cd_path, .{})) |dir| {
            std.Io.Dir.close(dir, io);
            return cd_path;
        } else |err| {
            gpa.free(cd_path);
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

// 1. split CDPATH into strings/accessable directories
// 2. read directory.
// 3. eg. export CDPATH="/home/isaac:/usr"
//  - cd bin -> check first path "/home/isaac" for bin and loop through each in CPATH
//  - is bin inside "/home/isaac" steps:
//  -   concat "/" to "/home/isaac" if doesn't end with "/"
//  -   check "/home/isaac/bin" is a directory or no
//  -   if inside, then change dir, else:
//  -   check "./" directory
//  -   if inside, then change dir, else:
//  -   loop through every variable until null or directory is found
