const std = @import("std");
const autogit = @import("autogit");

pub fn main() !void {
    //const cwd = "/home/ctlf/dev/zig/autogit/";
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    //defer std.debug.assert(gpa.deinit() == .ok); // I know we are leaking memory currently. The os will clean up until we do

    const allocator = gpa.allocator();

    const config = get_config();

    var git = try autogit.Git.init(allocator, &.{config});
    defer git.deinit();

    git.process();
}

fn get_config() autogit.Config {
    const stat = std.fs.cwd().statFile("config.zon") catch {
        gen_config() catch {
            std.debug.print("Unable to load and generate default config file\n", .{});
            return defaultConfig;
        };
        return get_config();
    };

    const file = std.fs.cwd().openFile("config.zon", .{}) catch {
        std.debug.print("Unable to load and generate default config file\n", .{});
        return defaultConfig;
    };
    defer file.close();

    const buffer = file.readToEndAllocOptions(std.heap.page_allocator, @intCast(stat.size), @intCast(stat.size), std.mem.Alignment.fromByteUnits(1), 0) catch {
        std.debug.print("Unable to load config file\n", .{});
        return defaultConfig;
    };
    defer std.heap.page_allocator.free(buffer);

    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const config = std.zon.parse.fromSlice(autogit.Config, std.heap.page_allocator, buffer, &diagnostics, .{}) catch {
        std.debug.print("Unable to parse config file:\n", .{});

        var iter = diagnostics.iterateErrors();
        while (iter.next()) |err| {
            std.debug.print("    {f}\n", .{err.fmtMessage(&diagnostics)});
        }

        diagnostics.deinit(std.heap.page_allocator);

        return defaultConfig;
    };

    return config;
}

fn gen_config() !void {
    const file = try std.fs.cwd().openFile("config.zon", .{ .mode = .write_only });
    defer {
        file.close();
    }

    errdefer {
        std.fs.cwd().deleteFile("config.zon") catch {};
    }

    try file.writeAll(".{\r\n  .{\r\n");

    try file.writeAll("    .username = \"sbrough\",\r\n");
    try file.writeAll("    .first_name = \"Spencer\",\r\n");
    try file.writeAll("    .last_name = \"Brough\",\r\n");
    try file.writeAll("    .email = \"sbrough@origamirisk.com\",\r\n");
    try file.writeAll("    // allowed tokens: {{username}} {{first_name}} {{last_name}} {{date}} {{email}}\r\n");
    try file.writeAll("    // if not on main we will switch automatically to the branch using this pattern.\r\n");
    try file.writeAll("    // that said it's highly recommended that date is included somewhere so that branch names are distinct\r\n");
    try file.writeAll("    .branch_gen_pattern = \"Snapshot_{{username}}-{{date}}\",\r\n");
    try file.writeAll("    .working_directory = \"C:\\code\\Origami\\\",\r\n");
    try file.writeAll("    .auto_add_patterns = .{\r\n");

    // TODO:
    try file.writeAll("      \"Origami\\Origami.Core\\Models\\*.cs\",\r\n");

    try file.writeAll("    },\r\n");
    try file.writeAll("  },\r\n}\r\n");
}

const defaultConfig = autogit.Config{
    .username = "sbrough",
    .first_name = "Spencer",
    .last_name = "Brough",
    .email = "sbrough@origamirisk.com",
    .branch_gen_pattern = "Snapshot_{{username}}-{{date}}",
    .working_directory = "C:\\code\\Origami\\",
    .auto_add_patterns = &.{
        "\"Origami\\Origami.Core\\Models\\*.cs\",\r\n",
    },
};
