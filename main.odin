package ballista

import rl "vendor:raylib"

import "base:runtime"
import "core:log"
import "core:debug/trace"
import "core:mem/virtual"

GAME_NAME     :: "Ballista"
WINDOW_WIDTH  :: 2560
WINDOW_HEIGHT :: 1440

g_context: runtime.Context
g_static_lifetime_arena: virtual.Arena
g_static_lifetime_allocator: runtime.Allocator

main :: proc() {
  context.assertion_failure_proc = trace.assertion_failure_proc

  when ODIN_DEBUG {
    tracking_allocator: trace.Tracking_Allocator
    trace.tracking_allocator_init(&tracking_allocator, context.allocator)
    context.allocator = trace.tracking_allocator(&tracking_allocator)
    defer {
      trace.tracking_allocator_print_results(&tracking_allocator)
      trace.tracking_allocator_destroy(&tracking_allocator)
    }
  }

  context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
  defer log.destroy_console_logger(context.logger)

  g_context = context

  _ = virtual.arena_init_growing(&g_static_lifetime_arena)
  g_static_lifetime_allocator = virtual.arena_allocator(&g_static_lifetime_arena)
  defer virtual.arena_destroy(&g_static_lifetime_arena)

  rl.InitWindow(width = WINDOW_WIDTH, height = WINDOW_HEIGHT, title = GAME_NAME)
  defer rl.CloseWindow()
  rl.SetTargetFPS(60)

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()

    rl.ClearBackground(rl.RAYWHITE)
    rl.DrawFPS(10, 10)
    hello_world := cstring("Hello World!")
    font_size := i32(40)
    text_width := rl.MeasureText(hello_world, font_size)
    rl.DrawText(
      text = hello_world,
      posX = WINDOW_WIDTH / 2 - text_width / 2,
      posY = WINDOW_HEIGHT / 2 - font_size / 2,
      fontSize = font_size,
      color = rl.BLACK,
    )

    rl.EndDrawing()
  }
}
