const std = @import("std");
const za = @import("zalgebra");
const c = @cImport({
    @cDefine("FAST_OBJ_IMPLEMENTATION", {});
    @cInclude("fast_obj.h");
});

const Mat4 = za.Mat4;
const Vec3 = za.Vec3;

const SQUARE = Mat4
    .identity()
    .scale(Vec3.new(8.0, 4.0, 1.0))
    .translate(Vec3.new(0.4, 0, 0));

const TRIANGLE = [_]Mat4 {
    Mat4.identity().mul(SQUARE).scale(Vec3.set(0.5)),
    Mat4.identity().mul(SQUARE).scale(Vec3.set(0.5)).translate(Vec3.new(0.5, 0, 0)).shear(.{ .yx = -1 }),
    Mat4.identity().mul(SQUARE).scale(Vec3.set(0.5)).translate(Vec3.new(0, 0.5, 0)).shear(.{ .xy = -1 }),
};

const CmdPrinter = struct {
    file:   std.fs.File,
    writer: std.fs.File.Writer,

    pub fn init(file_name: []const u8) !CmdPrinter {
        const file = std.fs.cwd().createFile(file_name, .{}) catch |err| {
            std.log.err("failed to open file '{s}': {}", .{file_name, err});
            return err;
        };

        return .{
            .file = file,
            .writer = file.writer()
        };
    }

    pub fn deinit(self: CmdPrinter) void {
        self.file.close();
    }

    pub fn printTriangleRendering(
        self: CmdPrinter,
        p1: Vec3,
        p2: Vec3,
        p3: Vec3,
        color: i32
    ) !void {
        const vec1 = p2.sub(p1);
        const vec2 = p3.sub(p1);

        const x_axis = vec1.norm();
        const z_axis = vec1.cross(vec2).norm();
        const y_axis = z_axis.cross(x_axis).norm();

        const rot = Mat4{
            .data = .{
                .{ x_axis.x(), x_axis.y(), x_axis.z(), 0 },
                .{ y_axis.x(), y_axis.y(), y_axis.z(), 0 },
                .{ z_axis.x(), z_axis.y(), z_axis.z(), 0 },
                .{ 0,          0,          0,          1 },
            }
        };

        const width = vec1.length();
        const height = vec2.dot(y_axis);
        const vec2_width = vec2.dot(x_axis);
        const shear = vec2_width / width;

        for (TRIANGLE) |part| {
            const t = part
                .shear(.{ .yx = shear })
                .scale(Vec3.new(width, height, 1));

            try self.print(
                "summon minecraft:text_display ~ ~ ~ {{text:{{text:\" \"}},background:{d},transformation:{},brightness:{{block:15,sky:15}}}}",
                .{ color, rot.translate(p1).mul(t) }
            );
        }
    }

    pub fn print(
        self: CmdPrinter,
        comptime format: []const u8,
        args: anytype
    ) !void {
        self.writer.print(format ++ "\n", args) catch |err| {
            std.log.err("failed to print command: {}", .{err});
            return err;
        };
    }
};

const Color = struct {
    a: u8, r: u8, g: u8, b: u8,

    pub fn new(a: u8, r: u8, g: u8, b: u8) Color {
        return .{ .a = a, .r = r, .g = g, .b = b };
    }

    pub fn asARGB(self: Color) i32 {
        var res: i32 = 0;
        res |= @as(i32, self.a) << 24;
        res |= @as(i32, self.r) << 16;
        res |= @as(i32, self.g) << 8;
        res |= @as(i32, self.b) << 0;
        return res;
    }
};

const COLOR = Color.new(255, 255, 255, 255);
const LIGHT = Vec3.new(1, 1, 1).norm();
fn calcColor(normal: Vec3) Color {
    const light_dot = normal.dot(LIGHT);
    const brightness = @max(@min(2*(light_dot + 1)/2 - 1, 1.0), 0.5);

    const r: f32 = @floatFromInt(COLOR.r);
    const g: f32 = @floatFromInt(COLOR.g);
    const b: f32 = @floatFromInt(COLOR.b);

    return Color.new(
        255,
        @intFromFloat(@min(@max(r*brightness, 0), 255)),
        @intFromFloat(@min(@max(g*brightness, 0), 255)),
        @intFromFloat(@min(@max(b*brightness, 0), 255)),
    );
}

pub fn main() !void {
    var args = std.process.argsWithAllocator(std.heap.page_allocator) catch |err| {
        std.log.err("failed to get arguments: {}", err);
        return;
    };
    defer args.deinit();

    const prog_name = args.next().?;
    const input = args.next() orelse {
        std.debug.print("usage: {s} <input.obj> <output.mcfunction>\n", .{prog_name});
        return;
    };
    const output = args.next() orelse {
        std.debug.print("usage: {s} <input.obj> <output.mcfunction>\n", .{prog_name});
        return;
    };

    const meshPtr = c.fast_obj_read(input) orelse {
        std.log.err("failed to read '{s}'", .{input});
        return;
    };
    defer c.fast_obj_destroy(meshPtr);
    const mesh = meshPtr[0];

    const printer = CmdPrinter.init(output) catch return;
    defer printer.deinit();

    // TODO: Summon text displays with specific tag.
    //       It will let us to kill only the specific model
    printer.print("kill @e[type=minecraft:text_display]", .{}) catch return;

    for (0..mesh.face_count) |i| {
        const vertex_count = mesh.face_vertices[i];
        std.debug.assert(vertex_count == 3); // TODO: Handle all possible vertex count?

        const idx1 = mesh.indices[i*3 + 0];
        const idx2 = mesh.indices[i*3 + 1];
        const idx3 = mesh.indices[i*3 + 2];

        const pos1 = Vec3.fromSlice(mesh.positions[idx1.p*3..idx1.p*3+3]);
        const pos2 = Vec3.fromSlice(mesh.positions[idx2.p*3..idx2.p*3+3]);
        const pos3 = Vec3.fromSlice(mesh.positions[idx3.p*3..idx3.p*3+3]);

        const normal = Vec3.fromSlice(mesh.normals[idx1.n*3..idx1.n*3+3]);

        // TODO: Color from .mtl file
        const color = calcColor(normal).asARGB();

        printer.printTriangleRendering(pos1, pos2, pos3, color) catch return;
    }

    // TODO: Report generated command count
}
