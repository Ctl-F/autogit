//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// RULES: If BRANCH is master or main
//      Generate new branch and commit to it
//          ELSE
//      Push to current branch

pub const Git = struct {
    // Branch: git rev-parse --abbrev-ref HEAD
    // NewBranch: git checkout -b NAME
    // Changes: git status --porcelain

    allocator: std.mem.Allocator,
    cwd: []const u8,
    env: std.process.EnvMap,

    pub fn init(allocator: std.mem.Allocator, cwd: []const u8) !@This() {
        var map = try std.process.getEnvMap(allocator);
        errdefer map.deinit();

        std.debug.assert(map.get("PATH") != null);

        std.debug.print("{s}\n", .{cwd});
        const dir = try std.fs.cwd().openDir(cwd, .{});
        std.debug.print("{}\n", .{dir});

        return .{
            .allocator = allocator,
            .cwd = cwd,
            .env = map,
        };
    }

    pub fn deinit(this: *@This()) void {
        this.env.deinit();
    }

    pub const Status = enum {
        Add,
        Modify,
        Delete,
        Rename,
        Conflict,
        Untracked,
        Unchanged,
        Unsupported,
    };

    pub const File = struct {
        status: Status,
        filename: []const u8,
        ext: []const u8,
    };

    pub fn get_current_branch(this: *@This()) ![]u8 {
        const result = try std.process.Child.run(.{
            .allocator = this.allocator,
            .argv = &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
            .cwd = this.cwd,
            .env_map = &this.env,
        });

        return this.unwrap_result(result);
    }

    pub fn get_file_statuses(this: *@This()) !std.ArrayList(File) {
        const result = try std.process.Child.run(.{
            .allocator = this.allocator,
            .argv = &.{ "git", "status", "--porcelain", "--untracked-files=all" },
            .cwd = this.cwd,
            .env_map = &this.env,
        });

        const stdout = this.unwrap_result(result);

        defer this.allocator.free(stdout);
        return try this.parse_files(stdout);
    }

    fn parse_files(this: *@This(), buffer: []const u8) !std.ArrayList(File) {
        var list = try std.ArrayList(File).initCapacity(this.allocator, 128);
        errdefer list.deinit(this.allocator);

        var iter = std.mem.SplitIterator(u8, .scalar){
            .buffer = buffer,
            .delimiter = '\n',
            .index = 0,
        };

        while (iter.next()) |line| {
            if (line.len < 3) continue;

            const X = line[0];
            const Y = line[1];

            const status = STAT: {
                if (X == 'U' or Y == 'U') {
                    break :STAT Status.Conflict;
                }

                if (X == '?' or Y == '?') {
                    break :STAT Status.Untracked;
                }

                break :STAT switch (Y) {
                    'M' => Status.Modify,
                    'A' => Status.Add,
                    'R' => Status.Rename,
                    'D' => Status.Delete,
                    ' ' => Status.Unchanged,
                    else => Status.Unsupported,
                };
            };

            const filename = buffer[3..];
            const extPos = std.mem.lastIndexOfScalar(u8, filename, '.');
            const ext = if (extPos) |ep|
                buffer[ep + 1 ..]
            else
                "";

            try list.append(this.allocator, .{
                .status = status,
                .filename = filename,
                .ext = ext,
            });
        }

        return list;
    }

    fn unwrap_result(this: *@This(), result: std.process.Child.RunResult) []u8 {
        if (result.stderr.len > 0) {
            std.debug.print("Error stream was populated: {s}\n", .{result.stderr});
        }

        this.allocator.free(result.stderr);
        return result.stdout;
    }
};
