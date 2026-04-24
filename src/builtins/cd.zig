const std = @import("std");

pub fn cd(io: std.Io, environ: *std.process.Environ.Map, argv: [][]const u8) !void {
    var stdout_buf: [1024]u8 = undefined;

    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);

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
            const home_dir = environ.get("OLDPWD") orelse {
                return;
            };
            target = home_dir;
            try stdout.interface.print("{s}\n", .{target});
            try stdout.interface.flush();
        }

        if (std.Io.Threaded.chdir(target)) {} else |err| {
            switch (err) {
                error.NotDir => {
                    try stdout.interface.print("pash: cd: '{s}'  No such file or directory \n", .{target});
                },
                error.SymLinkLoop => {
                    try stdout.interface.print("pash: cd: '{s}' Too many levels of symbolic links \n", .{target});
                },
                error.SystemResources => {
                    try stdout.interface.print("pash: cd: '{s}' Cannot allocate memory to process \n", .{target});
                },
                error.NameTooLong => {
                    try stdout.interface.print("pash: cd: '{s}' File name is too long \n", .{target});
                },
                error.FileNotFound => {
                    try stdout.interface.print("pash: cd: '{s}' File or directory not found \n", .{target});
                },
                error.FileSystem => {
                    try stdout.interface.print("pash: cd: '{s}' I/O operation failed \n", .{target});
                },
                error.BadPathName => {
                    try stdout.interface.print("pash: cd: '{s}' Illegal byte sequence encountered \n", .{target});
                },
                error.Canceled => {
                    try stdout.interface.print("pash: cd: Process has been cancelled \n", .{});
                },
                error.AccessDenied => {
                    try stdout.interface.print("pash: cd: '{s}' Permission denied \n", .{target});
                },
                error.Unexpected => {
                    try stdout.interface.print("pash: cd: Unknown error encountered \n", .{});
                },
            }
            try stdout.interface.flush();
        }
    }
}
