const std = @import("std");

const flags = enum { L_FLAG, P_FLAG };

const CdpathResult = struct {
    path: []u8,
    should_print: bool,
};

const cdOptions = struct {
    flag: flags,
    print_status: bool,

    pub fn init() cdOptions {
        const options = cdOptions{
            .flag = flags.L_FLAG,
            .print_status = false,
        };

        return options;
    }

    fn setFlag(self: *cdOptions, flag: flags) void {
        self.flag = flag;
    }

    fn setPrintingStatus(self: *cdOptions, print_status: bool) void {
        self.print_status = print_status;
    }
};

pub fn cd(io: std.Io, gpa: std.mem.Allocator, environ: *std.process.Environ.Map, argv: [][]const u8) !u8 {
    var options = cdOptions.init();
    var err_buf: [4096]u8 = undefined;
    var arg_index: usize = 1;
    var from_oldpwd = false;
    var target: []const u8 = undefined;
    var curpath: []const u8 = undefined;
    var cdpath_path: ?[]u8 = null;
    defer if (cdpath_path) |path| gpa.free(path);

    var stderr = std.Io.File.stderr().writer(io, &err_buf);
    const pwd = environ.get("PWD");

    if (pwd == null or pwd.?.len == 0 or !std.mem.startsWith(u8, pwd.?, "/")) {
        const cwd = try std.process.currentPathAlloc(io, gpa);
        defer gpa.free(cwd);
        try environ.put("PWD", cwd);
    }

    while (arg_index < argv.len) : (arg_index += 1) {
        const arg = argv[arg_index];

        if (std.mem.eql(u8, arg, "--")) {
            arg_index += 1;
            break;
        }

        if (std.mem.eql(u8, arg, "-")) break;
        if (!std.mem.startsWith(u8, arg, "-") or arg.len == 1) break;

        for (arg[1..]) |option| {
            switch (option) {
                'L' => options.setFlag(flags.L_FLAG),
                'P' => options.setFlag(flags.P_FLAG),
                else => {
                    try stderr.interface.print("pash: cd: invalid option: -{c}\n", .{option});
                    try stderr.interface.flush();
                    return 1;
                },
            }
        }
    }

    if (argv.len - arg_index > 1) {
        try stderr.interface.print("pash: cd: too many arguments\n", .{});
        try stderr.interface.flush();
        return 1;
    }

    if (arg_index >= argv.len) {
        target = environ.get("HOME") orelse {
            try stderr.interface.print("pash: cd: $HOME not set\n", .{});
            try stderr.interface.flush();
            return 1;
        };

        if (target.len == 0) {
            try stderr.interface.print("pash: cd: $HOME not set\n", .{});
            try stderr.interface.flush();
            return 1;
        }

        curpath = target;
    } else if (std.mem.eql(u8, argv[arg_index], "-")) {
        target = environ.get("OLDPWD") orelse {
            try stderr.interface.print("pash: cd: $OLDPWD not set\n", .{});
            try stderr.interface.flush();
            return 1;
        };

        if (target.len == 0) {
            try stderr.interface.print("pash: cd: $OLDPWD not set\n", .{});
            try stderr.interface.flush();
            return 1;
        }

        curpath = target;
        from_oldpwd = true;
        options.setPrintingStatus(true);
    } else {
        target = argv[arg_index];
        curpath = target;
    }
    if (!from_oldpwd) {
        // TODO: remove this when shell expansion is implemented
        if (std.mem.eql(u8, "~", target)) {
            const home_dir = environ.get("HOME") orelse {
                try stderr.interface.print("pash: cd: $HOME not set \n", .{});
                try stderr.interface.flush();
                return 1;
            };
            curpath = home_dir;
        } else if (std.mem.startsWith(u8, target, "/") or startsWithDot(target)) {
            curpath = target;
        } else {
            if (try checkCdpath(io, gpa, environ.get("CDPATH") orelse "", target)) |result| {
                cdpath_path = result.path;
                curpath = result.path;
                if (result.should_print) {
                    options.setPrintingStatus(true);
                }
            } else {
                curpath = target;
            }
        }
    }
    return try runCd(io, gpa, curpath, options, environ);
}

fn checkCdpath(io: std.Io, gpa: std.mem.Allocator, cdpath: []const u8, target_path: []const u8) !?CdpathResult {
    if (cdpath.len == 0) {
        return null;
    }
    var path_iterator = std.mem.splitAny(u8, cdpath, ":");
    var curpath: []u8 = undefined;

    while (path_iterator.next()) |path| {
        const should_print = path.len != 0;

        if (path.len == 0) {
            curpath = try std.mem.concat(gpa, u8, &[_][]const u8{ "./", target_path });
        } else if (std.mem.endsWith(u8, path, "/")) {
            curpath = try std.mem.concat(gpa, u8, &[_][]const u8{ path, target_path });
        } else {
            curpath = try std.mem.concat(gpa, u8, &[_][]const u8{ path, "/", target_path });
        }

        if (checkIfDirectory(io, curpath)) {
            return CdpathResult{ .path = curpath, .should_print = should_print };
        }
        gpa.free(curpath);
    }
    return null;
}

fn runCd(io: std.Io, gpa: std.mem.Allocator, target: []const u8, options: cdOptions, environ: *std.process.Environ.Map) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;

    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    var stderr = std.Io.File.stderr().writer(io, &err_buf);

    const old_pwd = environ.get("PWD").?;

    var chdir_path: []const u8 = target;
    var logical_pwd: ?[]u8 = null;
    defer if (logical_pwd) |pwd| gpa.free(pwd);

    if (options.flag == flags.L_FLAG) {
        logical_pwd = getLogicalPwd(io, gpa, old_pwd, target) catch |err| {
            try printCdError(&stderr, target, err);
            return 1;
        };
        chdir_path = logical_pwd.?;
    }

    if (std.Io.Threaded.chdir(chdir_path)) {
        if (options.flag == flags.P_FLAG) {
            const physical_path = try std.process.currentPathAlloc(io, gpa);
            defer gpa.free(physical_path);
            try setPwd(environ, old_pwd, physical_path);
        } else {
            try setPwd(environ, old_pwd, chdir_path);
        }

        if (options.print_status) {
            try stdout.interface.print("{s}\n", .{environ.get("PWD").?});
            try stdout.interface.flush();
        }

        return 0;
    } else |err| {
        try printCdError(&stderr, target, err);
        return 1;
    }
    return 0;
}

fn printCdError(stderr: anytype, target: []const u8, err: anyerror) !void {
    switch (err) {
        error.NotDir => {
            try stderr.interface.print("pash: cd: '{s}'  Not a directory\n", .{target});
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
        error.AccessDenied, error.PermissionDenied => {
            try stderr.interface.print("pash: cd: '{s}' Permission denied\n", .{target});
        },
        error.Unexpected => {
            try stderr.interface.print("pash: cd: Unexpected error occured\n", .{});
        },
        else => {
            try stderr.interface.print("pash: cd: Unknown error encountered\n", .{});
        },
    }
    try stderr.interface.flush();
}

fn setPwd(environ: *std.process.Environ.Map, old_pwd: []const u8, new_pwd: []const u8) !void {
    try environ.put("OLDPWD", old_pwd);
    try environ.put("PWD", new_pwd);
}

fn getLogicalPwd(io: std.Io, gpa: std.mem.Allocator, old_pwd: []const u8, target: []const u8) ![]u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(gpa);

    if (!std.mem.startsWith(u8, target, "/")) {
        var old_items = std.mem.splitScalar(u8, old_pwd, '/');
        while (old_items.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) continue;
            try parts.append(gpa, part);
        }
    }

    var items = std.mem.splitScalar(u8, target, '/');
    while (items.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;

        if (std.mem.eql(u8, part, "..")) {
            if (parts.items.len > 0) {
                try checkIfPartsDirectory(io, gpa, parts.items);
                _ = parts.pop();
            }
            continue;
        }

        try parts.append(gpa, part);
    }

    return try buildAbsolutePath(gpa, parts.items);
}

fn checkIfDirectory(io: std.Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .directory;
}

fn checkIfPartsDirectory(io: std.Io, gpa: std.mem.Allocator, parts: []const []const u8) !void {
    const path = try buildAbsolutePath(gpa, parts);
    defer gpa.free(path);

    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| return err;
    if (stat.kind != .directory) return error.NotDir;
}

fn buildAbsolutePath(gpa: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    if (parts.len == 0) {
        return try gpa.dupe(u8, "/");
    }

    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(gpa);

    for (parts) |part| {
        try output.append(gpa, '/');
        try output.appendSlice(gpa, part);
    }

    return try output.toOwnedSlice(gpa);
}

fn startsWithDot(path: []const u8) bool {
    return std.mem.eql(u8, path, ".") or
        std.mem.eql(u8, path, "..") or
        std.mem.startsWith(u8, path, "./") or
        std.mem.startsWith(u8, path, "../");
}
