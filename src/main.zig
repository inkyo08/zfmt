const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const Render = @import("Render.zig");
const fatal = process.fatal;

pub fn main(init: std.process.Init) !void {
  const gpa = init.gpa;
  const arena = init.arena.allocator();
  const io = init.io;

  const args = try init.minimal.args.toSlice(arena);
  if (args.len != 2) {
    fatal("usage: {s} <file>", .{args[0]});
  }
  const file_path = args[1];

  const source_file = try Io.Dir.cwd().openFile(io, file_path, .{});
  var file_closed = false;
  errdefer if (!file_closed) source_file.close(io);

  const stat = try source_file.stat(io);
  if (stat.kind == .directory)
    fatal("'{s}' is a directory", .{file_path});

  var read_buffer: [1024]u8 = undefined;
  var file_reader: Io.File.Reader = source_file.reader(io, &read_buffer);
  file_reader.size = stat.size;

  const source_code = std.zig.readSourceFileToEndAlloc(gpa, &file_reader) catch |err| switch (err) {
    error.ReadFailed => return file_reader.err.?,
    else => |e| return e,
  };
  defer gpa.free(source_code);

  source_file.close(io);
  file_closed = true;

  const mode: std.zig.Ast.Mode = if (mem.endsWith(u8, file_path, ".zon")) .zon else .zig;

  var tree = try std.zig.Ast.parse(gpa, source_code, .{ .mode = mode });
  defer tree.deinit(gpa);

  if (tree.errors.len != 0) {
    try std.zig.printAstErrorsToStderr(gpa, io, tree, file_path, .auto);
    process.exit(1);
  }

  var out_buffer: std.Io.Writer.Allocating = .init(gpa);
  defer out_buffer.deinit();
  // As a heuristic, we make enough capacity for the same as the input source.
  try out_buffer.ensureTotalCapacity(source_code.len);

  Render.renderTree(gpa, &out_buffer.writer, tree, .{}) catch |err| switch (err) {
    error.WriteFailed, error.OutOfMemory => return error.OutOfMemory,
  };
  if (mem.eql(u8, out_buffer.written(), source_code))
    return;

  const dir = Io.Dir.cwd();
  var af = try dir.createFileAtomic(io, file_path, .{ .permissions = stat.permissions, .replace = true });
  defer af.deinit(io);

  try af.file.writeStreamingAll(io, out_buffer.written());
  try af.replace(io);
}
