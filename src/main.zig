const std = @import("std");
const autogit = @import("autogit");

pub fn main() !void {
    const cwd = "/home/ctlf/dev/zig/autogit/";
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    std.debug.print("Init-git\n", .{});
    var git = try autogit.Git.init(gpa.allocator(), cwd);
    defer git.deinit();

    std.debug.print("Get Branch\n", .{});
    const branch = try git.get_current_branch();
    defer gpa.allocator().free(branch);

    std.debug.print("Branch: {s}\n", .{branch});

    var files = try git.get_file_statuses();
    defer files.deinit(gpa.allocator());

    for (files.items) |file| {
        std.debug.print("{}\n", .{file});
    }
}
