//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zeit = @import("zeit");
const glob = @import("glob");

// RULES: If BRANCH is master or main
//      Generate new branch and commit to it
//          ELSE
//      Push to current branch

pub const Config = struct {
    working_directory: []const u8,
    username: []const u8,
    first_name: []const u8,
    last_name: []const u8,
    email: []const u8,
    auto_add_patterns: []const []const u8,
    branch_gen_pattern: []const u8 = "",
    enable_auto_add: bool = true,
    abort_on_conflicting: bool = true,
};

pub const Git = struct {
    // Branch: git rev-parse --abbrev-ref HEAD
    // NewBranch: git checkout -b NAME
    // Changes: git status --porcelain

    allocator: std.mem.Allocator,
    env: std.process.EnvMap,
    confs: []const Config,

    pub fn init(allocator: std.mem.Allocator, confs: []const Config) !@This() {
        var map = try std.process.getEnvMap(allocator);
        errdefer map.deinit();

        std.debug.assert(map.get("PATH") != null);

        return .{
            .allocator = allocator,
            .env = map,
            .confs = confs,
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

    pub fn process(this: *@This()) !void {
        for (this.confs) |conf| {
            try this.process_repo(conf);
        }
    }

    fn write_commit(buffer: []u8, current: []u8, append: []const u8) ![]u8 {
        const free_space = buffer.len - current.len;
        var to_append = append;
        if (free_space < to_append.len) {
            to_append = append[0..free_space];
        }

        const buffer_start = current.len;
        const buffer_end = buffer_start + to_append.len;
        @memcpy(buffer[buffer_start..buffer_end], to_append);

        if (free_space < append.len) {
            return error.BufferIsFull;
        }

        return buffer[0..buffer_end];
    }

    fn finalize_message(commit_message_buffer: []u8) void {
        commit_message_buffer[commit_message_buffer.len - 3] = '.';
        commit_message_buffer[commit_message_buffer.len - 2] = '.';
        commit_message_buffer[commit_message_buffer.len - 1] = '.';
    }

    fn process_repo(this: *@This(), conf: Config) !void {
        const branch = try this.get_current_branch(conf);
        var buffer: []const u8 = &.{};
        const files = try this.get_file_statuses(conf, &buffer);
        defer this.allocator.free(buffer);
        const commit_message_buffer = try this.allocator.alloc(u8, 4096);
        defer this.allocator.free(commit_message_buffer);

        var commit_message = &.{};

        if (std.mem.eql(u8, branch, "main") or
            std.mem.eql(u8, branch, "master"))
        {
            const new_branch = try this.gen_branch_name(conf);
            defer this.allocator.free(new_branch);

            std.debug.print("Switching branch: {s}\n", .{new_branch});

            try this.set_branch(branch);
        }

        var iter = this.get_files_to_commit(conf, files);
        while (iter.next()) |file| {
            if (commit_message.len < commit_message_buffer.len) {
                commit_message = write_commit(commit_message_buffer, commit_message, file.filename) catch {
                    finalize_message(commit_message_buffer);
                    commit_message = &commit_message_buffer;
                };

                commit_message = write_commit(commit_message_buffer, commit_message, " ") catch {
                    finalize_message(commit_message_buffer);
                    commit_message = &commit_message;
                };

                commit_message = write_commit(commit_message_buffer, commit_message, switch (file.status) {
                    .Added => "added",
                    .Modified => "modified",
                    .Deleted => "deleted",
                    .Renamed => "renamed",
                    .Conflicting => "conflicting",
                    .Untracked => "untracked",
                    .Unchanged => "unchanged",
                    .Unsupported => "unsupported",
                }) catch {
                    finalize_message(commit_message_buffer);
                    commit_message = &commit_message;
                };

                commit_message = write_commit(commit_message_buffer, commit_message, "\n") catch {
                    finalize_message(commit_message_buffer);
                    commit_message = &commit_message;
                };
            }

            const result = try this.exec(conf, &.{ "git", "add", file.filename });
            _ = result; // TODO
        }
    }

    fn get_current_branch(this: *@This(), conf: Config) ![]u8 {
        const result = try this.exec(conf, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" });

        return this.unwrap_result(result);
    }

    fn set_branch(this: *@This(), conf: Config, branch: []const u8) !void {
        const result = try this.exec(conf, &.{ "git", "checkout", "-b", branch });

        const buf = try this.unwrap_result(result);
        this.allocator.free(buf);
    }

    fn exec(this: *@This(), conf: Config, args: []const []const u8) !std.process.Child.RunResult {
        return try std.process.Child.run(.{
            .allocator = this.allocator,
            .argv = args,
            .cwd = conf.working_directory,
            .env_map = &this.env,
        });
    }

    pub fn get_file_statuses(this: *@This(), conf: Config, buffer: *[]const u8) !std.ArrayList(File) {
        var list = std.ArrayList(File).empty;

        // base command: git ls-files --full-name
        // -d deleted
        // -m modified
        // -o (others) untracked

        const args = [_]u8{ "-d", "-m", "-o" };
        const flags: [_]struct { del: bool, other: bool } = .{
            .{ .del = true, .other = false },
            .{ .del = false, .other = false },
            .{ .del = false, .other = true },
        };

        for (args) |arg| {
            var result = try this.exec(conf, &.{ "git", "ls-files", "--full-name", arg });
        }
    }

    // pub fn get_file_statuses(this: *@This(), conf: Config, buffer: *[]const u8) !std.ArrayList(File) {
    //     const result = try this.exec(conf, &.{ "git", "status", "--porcelain", "--untracked-files=all" });

    //     const stdout = this.unwrap_result(result);
    //     buffer.* = stdout;
    //     return try this.parse_files(stdout);
    // }

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

                if (!this.config.enable_auto_add) {
                    continue;
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

    pub fn get_files_to_commit(this: *@This(), conf: Config, files: std.ArrayList(File)) FileIter {
        _ = this;
        return .{
            .files = files.items,
            .cursor = 0,
            .config = conf,
        };
    }

    // fn parse_files(this: *@This(), buffer: []const u8) !std.ArrayList(File) {
    //     var list = try std.ArrayList(File).initCapacity(this.allocator, 128);
    //     errdefer list.deinit(this.allocator);

    //     var iter = std.mem.SplitIterator(u8, .scalar){
    //         .buffer = buffer,
    //         .delimiter = '\n',
    //         .index = 0,
    //     };

    //     while (iter.next()) |line| {
    //         if (line.len < 3) continue;

    //         const X = line[0];
    //         const Y = line[1];

    //         const status = STAT: {
    //             if (X == 'U' or Y == 'U') {
    //                 break :STAT Status.Conflicting;
    //             }

    //             if (X == '?' or Y == '?') {
    //                 break :STAT Status.Untracked;
    //             }

    //             break :STAT switch (Y) {
    //                 'M' => Status.Modified,
    //                 'A' => Status.Added,
    //                 'R' => Status.Renamed,
    //                 'D' => Status.Deleted,
    //                 ' ' => Status.Unchanged,
    //                 else => Status.Unsupported,
    //             };
    //         };

    //         const filename = line[3..];

    //         try list.append(this.allocator, .{
    //             .status = status,
    //             .filename = filename,
    //         });
    //     }

    //     return list;
    // }

    fn unwrap_result(this: *@This(), result: std.process.Child.RunResult) []u8 {
        if (result.stderr.len > 0) {
            std.debug.print("Error stream was populated: {s}\n", .{result.stderr});
        }

        this.allocator.free(result.stderr);
        return result.stdout;
    }

    /// conf tokens:
    /// {{username}}
    /// {{email}}
    /// {{first_name}}
    /// {{last_name}}
    /// {{date}}
    pub fn gen_branch_name(this: *@This(), conf: Config) ![]const u8 {
        const now = try zeit.instant(.{});
        const local = try zeit.local(this.allocator, &this.env);
        defer local.deinit();

        const now_local = now.in(&local);

        const dt = now_local.time();

        const branch_name_buffer = try this.allocator.alloc(u8, 2048);
        errdefer this.allocator.free(branch_name_buffer);

        @memset(branch_name_buffer, 0);

        var writer = std.io.fixedBufferStream(branch_name_buffer);

        var pattern = conf.branch_gen_pattern;
        if (pattern.len == 0) {
            pattern = "[Snapshot]{{username}}-{{date}}";
        }

        while (pattern.len > 0) {
            const cursor = std.mem.indexOf(u8, pattern, "{{");
            if (cursor == null) {
                _ = try writer.write(pattern);
                break;
            }
            const ci = cursor.?;

            const slice = pattern[0..ci];
            if (slice.len > 0) {
                _ = try writer.write(slice);
            }

            pattern = pattern[ci + 2 ..];

            const e = std.mem.indexOf(u8, pattern, "}}");

            if (e == null) {
                _ = try writer.write("{{");
                continue;
            }
            const ei = e.?;

            const token = pattern[0..ei];
            if (std.mem.eql(u8, token, "username")) {
                _ = try writer.write(conf.username);
            } else if (std.mem.eql(u8, token, "first_name")) {
                _ = try writer.write(conf.first_name);
            } else if (std.mem.eql(u8, token, "last_name")) {
                _ = try writer.write(conf.last_name);
            } else if (std.mem.eql(u8, token, "date")) {
                _ = try dt.strftime(writer.writer(), "%d-%m-%Y_T%H-%M");
            } else if (std.mem.eql(u8, token, "email")) {
                _ = try writer.write(conf.email);
            } else {
                _ = try writer.write(token);
            }

            pattern = pattern[ei + 2 ..];
        }

        return branch_name_buffer;
    }
};
