package ballista

import rl "vendor:raylib"

import "core:container/handle_map"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

MAX_ENTITIES :: 1024

Entity_Handle :: handle_map.Handle32

Entity_Kind :: enum {
  Small_Block,
}

Entity :: struct {
  handle: Entity_Handle,
  kind: Entity_Kind,
  position: Vec2,
  size: Vec2,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  entity_map: ^Entity_Map,
}

game_init :: proc(game: ^Game) {
  game.entity_map = new(Entity_Map, g_static_lifetime_allocator)

  for i in 0..<4 {
    _ = handle_map.add(game.entity_map, Entity{
      kind = .Small_Block,
      position = f32(i) * Vec2{ 40, 40 },
      size = { 20, 20 } },
    )
  }
}

game_deinit :: proc(game: Game) {}

game_update :: proc(game: ^Game, dt: f32) {
  iterator := handle_map.iterator_make(game.entity_map)
  for entity, handle in handle_map.iterate(&iterator) {
    entity.position += { 10, 10 } * dt
  }
}

game_draw :: proc(game: Game) {
  rl.BeginDrawing()
  defer rl.EndDrawing()

  rl.ClearBackground(rl.WHITE)
  rl.DrawFPS(10, 10)

  text: cstring
  if rl.IsKeyDown(.SPACE) {
    text = "Ballista"
  } else {
    text = "Hello World!"
  }

  font_size := i32(40)
  text_width := rl.MeasureText(text, font_size)
  rl.DrawText(
    text = text,
    posX = WINDOW_WIDTH / 2 - text_width / 2,
    posY = WINDOW_HEIGHT / 2 - font_size / 2,
    fontSize = font_size,
    color = rl.BLACK,
  )

  iterator := handle_map.iterator_make(game.entity_map)
  for entity, handle in handle_map.iterate(&iterator) {
    rl.DrawRectangle(
      posX = i32(entity.position.x),
      posY = i32(entity.position.y),
      width = i32(entity.size.x),
      height = i32(entity.size.y),
      color = rl.RED,
    )
  }
}
