package ballista

import "base:runtime"
import "core:log"
import "core:debug/trace"
import "core:mem/virtual"

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

  log.info("Hello World")
}
