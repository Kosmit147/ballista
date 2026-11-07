package ballista

import rl "vendor:raylib"
import b2 "vendor:box2d"

import "core:container/handle_map"
import "core:log"

RENDER_SCALE :: 20
PROJECTILE_RADIUS :: 0.5

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

MAX_ENTITIES :: 20000

Entity_Handle :: handle_map.Handle32

Entity_Kind :: enum {
  Ground,
  Small_Block,
  Projectile,
}

@(rodata) entity_colors := [Entity_Kind]rl.Color{
  .Ground = rl.GREEN,
  .Small_Block = rl.RED,
  .Projectile = rl.BLUE,
}

Entity :: struct {
  handle: Entity_Handle,
  kind: Entity_Kind,
  body_id: b2.BodyId,
  shape_id: b2.ShapeId,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  camera: rl.Camera2D,
  world: b2.WorldId,
  entity_map: ^Entity_Map,
}

game_init :: proc(game: ^Game) {
  game.entity_map = new(Entity_Map, g_static_lifetime_allocator)

  game.camera.target = { 0, 0 }
  game.camera.offset = { f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2 }
  game.camera.rotation = 0
  game.camera.zoom = 1

  world_def := b2.DefaultWorldDef()
  world_def.gravity = { 0, 10 }
  game.world = b2.CreateWorld(world_def)

  ground_body_def := b2.DefaultBodyDef()
  ground_body_def.position = { 0, 35 }
  ground_body_id := b2.CreateBody(game.world, ground_body_def)
  ground_box := b2.MakeBox(halfWidth = 150.0 / 2.0, halfHeight = 10 / 2.0)
  ground_shape_def := b2.DefaultShapeDef()
  ground_shape_id := b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

  _ = handle_map.add(game.entity_map, Entity{
    kind = .Ground,
    body_id = ground_body_id,
    shape_id = ground_shape_id,
  })

  for i in 0..<75 {
    position := Vec2{ -75, 0 } + Vec2{ 2 * f32(i), 2 }

    block_body_def := b2.DefaultBodyDef()
    block_body_def.type = .dynamicBody
    block_body_def.position = position
    block_body_id := b2.CreateBody(game.world, block_body_def)
    dynamic_box := b2.MakeBox(halfWidth = 1.0 / 2, halfHeight = 1.0 / 2)
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
  CAMERA_MOVE_SPEED :: 100
  CAMERA_ZOOM_SPEED :: 0.1

  if rl.IsKeyDown(.W) do game.camera.target.y -= CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.S) do game.camera.target.y += CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.A) do game.camera.target.x -= CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.D) do game.camera.target.x += CAMERA_MOVE_SPEED * dt

  if rl.IsKeyDown(.UP)   do game.camera.zoom *= 1 + (CAMERA_ZOOM_SPEED * dt)
  if rl.IsKeyDown(.DOWN) do game.camera.zoom *= 1 - (CAMERA_ZOOM_SPEED * dt)

  mouse_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera) / RENDER_SCALE

  if rl.IsMouseButtonDown(.LEFT) {
    projectile_body_def := b2.DefaultBodyDef()
    projectile_body_def.type = .dynamicBody
    projectile_body_def.position = mouse_position
    projectile_body_id := b2.CreateBody(game.world, projectile_body_def)
    circle: b2.Circle
    circle.radius = PROJECTILE_RADIUS
    shape_def := b2.DefaultShapeDef()
    shape_def.material.friction = 0.3
    projectile_shape_id := b2.CreateCircleShape(projectile_body_id, shape_def, circle)

    _ = handle_map.add(game.entity_map, Entity{
      kind = .Projectile,
      body_id = projectile_body_id,
      shape_id = projectile_shape_id,
    })
  }

  TIME_STEP     :: 1.0 / TARGET_FPS
  SUBSTEP_COUNT :: 4

  b2.World_Step(game.world, TIME_STEP, SUBSTEP_COUNT)
}

game_draw :: proc(game: Game) {
  rl.BeginDrawing()
  defer rl.EndDrawing()

  rl.ClearBackground(rl.WHITE)
  rl.DrawFPS(10, 10)

  {
    rl.BeginMode2D(game.camera)

    font_size := i32(40)
    text_width := rl.MeasureText(GAME_NAME, font_size)

    rl.DrawText(
      text = GAME_NAME,
      posX = -text_width / 2,
      posY = -font_size / 2,
      fontSize = font_size,
      color = rl.BLACK,
    )

    iterator := handle_map.iterator_make(game.entity_map)
    for entity, handle in handle_map.iterate(&iterator) {
      entity_color := entity_colors[entity.kind]
      switch entity.kind {
      case .Ground, .Small_Block:
        bounds := b2.Shape_GetBounds(entity.shape_id)
        rl.DrawRectangleV(
          position = bounds.lowerBound * RENDER_SCALE,
          size = (bounds.upperBound - bounds.lowerBound) * RENDER_SCALE,
          color = entity_color,
        )
      case .Projectile:
        position := b2.Body_GetPosition(entity.body_id)
        rl.DrawCircleV(
          center = position * RENDER_SCALE,
          radius = PROJECTILE_RADIUS * RENDER_SCALE,
          color = entity_color,
        )
      }
    }

    defer rl.EndMode2D()
  }
}
