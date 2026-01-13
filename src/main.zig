const std = @import("std");
const autogit = @import("autogit");

pub fn main() !void {
    const cwd = "/home/ctlf/dev/zig/autogit/";
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const config = autogit.Config{
        .username = "sbrough",
        .first_name = "Spencer",
        .last_name = "Brough",
        .email = "sbrough@origamirisk.com",
        .branch_gen_pattern = "[SNAPSHOT]{{email}}-{{date}}  {{last_name}}, {{first_name}}",
        .working_directory = cwd,
        .auto_add_patterns = &.{
            "src/*.zig",
            "src/*.zon",
            "foo/*.zon",
            "foo/*.zig",
        },
    };

    var git = try autogit.Git.init(allocator, &.{config});
    defer git.deinit();

    git.process();

    //const branch = try git.get_current_branch();
    //defer allocator.free(branch);

    //std.debug.print("Branch: {s}\n", .{branch});

    //var buffer: []const u8 = &.{};
    //var files = try git.get_file_statuses(&buffer);

    //defer allocator.free(buffer);
    //defer files.deinit(allocator);

    //const new_branch = try git.gen_branch_name(git.confs[0]);
    //defer allocator.free(new_branch);

    //std.debug.print("New Branch: [{s}]\n", .{std.mem.sliceTo(new_branch, 0)});

    //var iter = git.get_files_to_commit(files);
    //var count: usize = 0;
    //while (iter.next()) |file| {
    //    std.debug.print("[{}] {s}\n", .{ file.status, file.filename });
    //    count += 1;
    //}
    //std.debug.print("{}/{} files excluded\n", .{ files.items.len - count, files.items.len });
}
