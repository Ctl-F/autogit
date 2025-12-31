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

    pub fn get_current_branch(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "rev-parse", "--abbbrev-ref", "HEAD" },
            .cwd = cwd,
        });

        if (result.stderr.len > 0) {
            std.debug.print("Error stream was populated: {s}\n", .{result.stderr});
        }

        allocator.free(result.stderr);
        return result.stdout;
    }
};
