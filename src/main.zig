const std = @import("std");
const autogit = @import("autogit");

pub fn main() !void {
    const cwd = "/home/ctlf/dev/zig/autogit/";
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    const config = autogit.Config{
        .username = "sbrough",
        .auto_add_commit_extensions = ".zig,.zon",
    };

    std.debug.print("Init-git\n", .{});
    var git = try autogit.Git.init(gpa.allocator(), cwd, config);
    defer git.deinit();

    std.debug.print("Get Branch\n", .{});
    const branch = try git.get_current_branch();
    defer gpa.allocator().free(branch);

    std.debug.print("Branch: {s}\n", .{branch});

    var buffer: []const u8 = &.{};
    var files = try git.get_file_statuses(&buffer);

    defer gpa.allocator().free(buffer);
    defer files.deinit(gpa.allocator());

    for (files.items) |file| {
        std.debug.print("[{}] '{s}'\n", .{ file.status, file.filename });
    }

    const new_branch = try git.gen_branch_name();
    defer gpa.allocator().free(new_branch);

    std.debug.print("New Branch: [{s}]\n", .{std.mem.sliceTo(new_branch, 0)});
}
