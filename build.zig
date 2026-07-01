const std = @import("std");

pub fn build(b: *std.Build) void {
  const exe = b.addExecutable(.{
    .name = "zfmt",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = b.graph.host,
      .optimize = .ReleaseFast,
    }),
  });

  b.installArtifact(exe);
}
