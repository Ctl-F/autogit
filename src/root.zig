//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zeit = @import("zeit");
const glob = @import("glob");

// RULES: If BRANCH is master or main
//      Generate new branch and commit to it
//          ELSE
//      Push to current branch

pub const Config = struct {
    username: []const u8,
    auto_add_patterns: []const []const u8,
    abort_on_conflicting: bool = true,
};

pub const Git = struct {
    // Branch: git rev-parse --abbrev-ref HEAD
    // NewBranch: git checkout -b NAME
    // Changes: git status --porcelain

    allocator: std.mem.Allocator,
    cwd: []const u8,
    env: std.process.EnvMap,
    conf: Config,

    pub fn init(allocator: std.mem.Allocator, cwd: []const u8, conf: Config) !@This() {
        var map = try std.process.getEnvMap(allocator);
        errdefer map.deinit();

        std.debug.assert(map.get("PATH") != null);

        return .{
            .allocator = allocator,
            .cwd = cwd,
            .env = map,
            .conf = conf,
        };
    }

    pub fn deinit(this: *@This()) void {
        this.env.deinit();
    }

    pub const Status = enum {
        Added,
        Modified,
        Deleted,
        Renamed,
        Conflicting,
        Untracked,
        Unchanged,
        Unsupported,
    };

    pub const File = struct {
        status: Status,
        filename: []const u8,
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

    pub fn get_file_statuses(this: *@This(), buffer: *[]const u8) !std.ArrayList(File) {
        const result = try std.process.Child.run(.{
            .allocator = this.allocator,
            .argv = &.{ "git", "status", "--porcelain", "--untracked-files=all" },
            .cwd = this.cwd,
            .env_map = &this.env,
        });

        const stdout = this.unwrap_result(result);
        buffer.* = stdout;
        return try this.parse_files(stdout);
    }

    pub const FileIter = struct {
        files: []File,
        cursor: usize,
        config: Config,

        pub fn next(this: *@This()) ?File {
            while (true) {
                if (this.cursor >= this.files.len) return null;

                const f = this.files[this.cursor];
                this.cursor += 1;

                switch (f.status) {
                    .Conflicting => unreachable,
                    .Unchanged, .Unsupported => continue,
                    .Untracked => {},
                    else => return f,
                }

                // untracked files here
                for (this.config.auto_add_patterns) |pattern| {
                    if (glob.match(pattern, f.filename)) {
                        return f;
                    }
                }
            }
        }
    };

    pub fn get_files_to_commit(this: *@This(), files: std.ArrayList(File)) FileIter {
        return .{
            .files = files.items,
            .cursor = 0,
            .config = this.conf,
        };
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
                    break :STAT Status.Conflicting;
                }

                if (X == '?' or Y == '?') {
                    break :STAT Status.Untracked;
                }

                break :STAT switch (Y) {
                    'M' => Status.Modified,
                    'A' => Status.Added,
                    'R' => Status.Renamed,
                    'D' => Status.Deleted,
                    ' ' => Status.Unchanged,
                    else => Status.Unsupported,
                };
            };

            const filename = line[3..];

            try list.append(this.allocator, .{
                .status = status,
                .filename = filename,
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

    pub fn gen_branch_name(this: *@This()) ![]const u8 {
        const now = try zeit.instant(.{});
        const local = try zeit.local(this.allocator, &this.env);
        defer local.deinit();

        const now_local = now.in(&local);

        const dt = now_local.time();

        const branch_name_buffer = try this.allocator.alloc(u8, 1024);
        errdefer this.allocator.free(branch_name_buffer);

        var writer = std.io.fixedBufferStream(branch_name_buffer);

        _ = try writer.write(this.conf.username);
        _ = try writer.write("-[Snapshot ");
        _ = try dt.strftime(writer.writer(), "%d-%m-%Y_T%H-%M");
        _ = try writer.write("]");
        _ = try writer.write(&.{0});
        return branch_name_buffer;
    }
};
