const std = @import("std");

pub fn cd(io: std.Io, gpa: std.mem.Allocator, environ: *std.process.Environ.Map, argv: [][]const u8) !void {
    var stdout_buf: [4096]u8 = undefined;

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
        var target = argv[1];

        if (std.mem.eql(u8, "~", target)) {
            const home_dir = environ.get("HOME") orelse {
                try stdout.interface.print("pash: cd: $HOME not set \n", .{});
                try stdout.interface.flush();
                return;
            };
            target = home_dir;
        }

        if (std.mem.eql(u8, "-", target)) {
            const prev_dir = environ.get("OLDPWD") orelse {
                return;
            };

            target = prev_dir;

            try stdout.interface.print("{s}\n", .{target});
            try stdout.interface.flush();
        }

        // if (std.mem.startsWith(u8, target, "/")) {
        //     try stdout.interface.print("{s}\n", .{target});
        //     try stdout.interface.print("Skipping the CDPATH section\n", .{});
        //     try stdout.interface.flush();
        // }

        if (std.Io.Threaded.chdir(target)) {
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

// 1. split CPATH into strings/accessable directories
// 2. read directory.
// 3. eg. export CPATH="/home/isaac:/usr"
//  - cd bin -> check first path "/home/isaac" for bin and loop through each in CPATH
//  - is bin inside "/home/isaac" steps:
//  -   concat "/" to "/home/isaac" if doesn't end with "/"
//  -   check "/home/isaac/bin" is a directory or no
//  -   if inside, then change dir, else:
//  -   check "./" directory
//  -   if inside, then change dir, else:
//  -   loop through every variable until null or directory is found
