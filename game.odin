package ballista

import rl "vendor:raylib"
import b2 "vendor:box2d"

import "core:container/handle_map"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

MAX_ENTITIES :: 1024

Entity_Handle :: handle_map.Handle32

Entity_Kind :: enum {
  Ground,
  Small_Block,
}

Entity :: struct {
  handle: Entity_Handle,
  kind: Entity_Kind,
  body_id: b2.BodyId,
  shape_id: b2.ShapeId,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  world: b2.WorldId,
  entity_map: ^Entity_Map,
}

game_init :: proc(game: ^Game) {
  world_def := b2.DefaultWorldDef()
  world_def.gravity = { 0, -10 }
  game.world = b2.CreateWorld(world_def)
  game.entity_map = new(Entity_Map, g_static_lifetime_allocator)

  ground_body_def := b2.DefaultBodyDef()
  ground_body_def.position = { 0, -10 }
  ground_body_id := b2.CreateBody(game.world, ground_body_def)
  ground_box := b2.MakeBox(halfWidth = 50.0 / 2.0, halfHeight = 100.0 / 2.0)
  ground_shape_def := b2.DefaultShapeDef()
  ground_shape_id := b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

  _ = handle_map.add(game.entity_map, Entity{
    kind = .Ground,
    body_id = ground_body_id,
    shape_id = ground_shape_id,
  })

  for i in 0..<4 {
    position := Vec2{ 40, 40 } * f32(i)
    size := Vec2{ 20, 20 }

    block_body_def := b2.DefaultBodyDef()
    block_body_def.type = .dynamicBody
    block_body_def.position = position
    block_body_id := b2.CreateBody(game.world, block_body_def)
    dynamic_box := b2.MakeBox(halfWidth = size.x / 2, halfHeight = size.y / 2)
    shape_def := b2.DefaultShapeDef()
    shape_def.material.friction = 0.3
    block_shape_id := b2.CreatePolygonShape(block_body_id, shape_def, dynamic_box)

    _ = handle_map.add(game.entity_map, Entity{
      kind = .Small_Block,
      body_id = block_body_id,
      shape_id = block_shape_id,
    })
  }
}

game_deinit :: proc(game: Game) {
  b2.DestroyWorld(game.world)
}

game_update :: proc(game: ^Game, dt: f32) {
  TIME_STEP     :: 1.0 / TARGET_FPS
  SUBSTEP_COUNT :: 4

  b2.World_Step(game.world, TIME_STEP, SUBSTEP_COUNT)

  iterator := handle_map.iterator_make(game.entity_map)
  for entity, handle in handle_map.iterate(&iterator) {
    // entity.position += { 10, 10 } * dt
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
    bounds := b2.Shape_GetBounds(entity.shape_id)
    lines := [4][2]Vec2{
      { { bounds.lowerBound.x, bounds.upperBound.y }, bounds.upperBound },
      { bounds.upperBound, { bounds.upperBound.x, bounds.lowerBound.y } },
      { { bounds.upperBound.x, bounds.lowerBound.y }, bounds.lowerBound },
      { bounds.lowerBound, { bounds.lowerBound.x, bounds.upperBound.y } },
    }
    color := rl.RED if entity.kind == .Small_Block else rl.GREEN
    for line in lines {
      rl.DrawLineV(
        startPos = line[0],
        endPos = line[1],
        color = color,
      )
    }
  }
}
