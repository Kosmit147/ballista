package ballista

import rl "vendor:raylib"
import b2 "vendor:box2d"

import "core:container/handle_map"
import "core:log"
import "core:math"
import "core:math/linalg"

RENDER_SCALE           :: 20
PROJECTILE_RADIUS      :: 0.5
PROJECTILE_DENSITY     :: 2.5
ANCHOR_POSITION        :: Vec2{ -50, 20 }
MAX_DISTANCE_TO_ANCHOR :: 8
PHYSICS_ENABLED        :: true
PHYSICS_THREADS        :: 4
PHYSICS_SLEEP_ENABLED  :: true
DRAW_ORIGIN_POINTS     :: true

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

MAX_ENTITIES :: 20000

Entity_Handle :: handle_map.Handle32

Entity_Kind :: enum {
  Ground,
  Block,
  Projectile,
}

@(rodata) entity_colors := [Entity_Kind]rl.Color{
  .Ground     = { 0, 255, 0, 255 },
  .Block      = { 255, 0, 0, 255 },
  .Projectile = { 0, 0, 255, 255 },
}

Entity :: struct {
  handle: Entity_Handle,
  kind: Entity_Kind,
  body_id: b2.BodyId,
  shape_id: b2.ShapeId,
  box_size: Vec2,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  camera: rl.Camera2D,
  world: b2.WorldId,
  entity_map: ^Entity_Map,
  projectile_position: Vec2,
}

game_init :: proc(game: ^Game) {
  game.entity_map = new(Entity_Map, g_static_lifetime_allocator)

  game.camera.target = { 0, 0 }
  game.camera.offset = { f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2 }
  game.camera.rotation = 0
  game.camera.zoom = 1

  world_def := b2.DefaultWorldDef()
  world_def.gravity = { 0, 10 }
  world_def.enableSleep = PHYSICS_SLEEP_ENABLED
  world_def.workerCount = PHYSICS_THREADS
  game.world = b2.CreateWorld(world_def)

  game.projectile_position = ANCHOR_POSITION

  {
    ground_body_def := b2.DefaultBodyDef()
    ground_body_def.position = { 0, 35 }
    ground_body_id := b2.CreateBody(game.world, ground_body_def)
    ground_box := b2.MakeBox(halfWidth = 150.0 / 2.0, halfHeight = 10.0 / 2.0)
    ground_shape_def := b2.DefaultShapeDef()
    ground_shape_id := b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

    _ = handle_map.add(game.entity_map, Entity{
      kind = .Ground,
      body_id = ground_body_id,
      shape_id = ground_shape_id,
      box_size = { 150, 10 },
    })
  }

  _game_add_block(game, {    0,   25 }, {    1,   10 })
  _game_add_block(game, {   10,   25 }, {    1,   10 })
  _game_add_block(game, {    5, 19.5 }, {   11,    1 })

  _game_add_block(game, {    0,   14 }, {    1,   10 })
  _game_add_block(game, {   10,   14 }, {    1,   10 })
  _game_add_block(game, {    5,  8.5 }, {   11,   1  })

  _game_add_block(game, {    0,     3 }, {    1,   10 })
  _game_add_block(game, {   10,     3 }, {    1,   10 })
  _game_add_block(game, {    5,  -2.5 }, {   11,   1  })

  _game_add_block(game, { 2.5, -7.8 }, { 1, 10 }, math.to_radians_f32(24))
  _game_add_block(game, { 7.5, -7.8 }, { 1, 10 }, math.to_radians_f32(-24))

  // for i in 0..<75 {
  //   position := Vec2{ -75, 0 } + Vec2{ 2 * f32(i), 2 }
  //   _game_add_block(game, position, size = { 1, 1 })
  // }
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

  pointer_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera) / RENDER_SCALE

  if rl.IsMouseButtonDown(.LEFT) {
    projectile_offset := linalg.clamp_length(pointer_position - ANCHOR_POSITION, MAX_DISTANCE_TO_ANCHOR)
    game.projectile_position = ANCHOR_POSITION + projectile_offset
  } else if rl.IsMouseButtonReleased(.LEFT) {
    projectile_offset := linalg.clamp_length(pointer_position - ANCHOR_POSITION, MAX_DISTANCE_TO_ANCHOR)
    projectile_velocity := -projectile_offset
    _game_add_projectile(game, ANCHOR_POSITION + projectile_offset, projectile_velocity * 5)
    game.projectile_position = ANCHOR_POSITION
  }

  if rl.IsMouseButtonPressed(.RIGHT) {
    _game_add_projectile(game, pointer_position)
  }

  TIME_STEP     :: 1.0 / TARGET_FPS
  SUBSTEP_COUNT :: 4

  when PHYSICS_ENABLED { b2.World_Step(game.world, TIME_STEP, SUBSTEP_COUNT) }
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
      case .Ground, .Block:
        transform := b2.Body_GetTransform(entity.body_id)
        position := transform.p
        rotation := transform.q
        size := entity.box_size
        rl.DrawRectanglePro(
          rec = rl.Rectangle{
            x = position.x * RENDER_SCALE,
            y = position.y * RENDER_SCALE,
            width = size.x * RENDER_SCALE,
            height = size.y * RENDER_SCALE,
          },
          origin = size / 2 * RENDER_SCALE,
          rotation = linalg.to_degrees(b2.Rot_GetAngle(rotation)),
          color = entity_color,
        )
        when DRAW_ORIGIN_POINTS { _draw_debug_point(position) }
      case .Projectile:
        position := b2.Body_GetPosition(entity.body_id)
        rl.DrawCircleV(
          center = position * RENDER_SCALE,
          radius = PROJECTILE_RADIUS * RENDER_SCALE,
          color = entity_color,
        )
        when DRAW_ORIGIN_POINTS { _draw_debug_point(position) }
      }
    }

    rl.DrawCircleV(
      center = ANCHOR_POSITION * RENDER_SCALE,
      radius = 0.15 * RENDER_SCALE,
      color = rl.BLACK,
    )

    rl.DrawCircleV(
      center = game.projectile_position * RENDER_SCALE,
      radius = PROJECTILE_RADIUS * RENDER_SCALE,
      color = entity_colors[.Projectile],
    )

    // {
    //   test_position := Vec2{ 10, 10 }
    //   test_size := Vec2{ 10, 3 }
    //   @(static) rotation: f32 = 0
    //   rotation += 1

    //   rl.DrawRectanglePro(
    //     rec = rl.Rectangle{
    //       x = test_position.x * RENDER_SCALE,
    //       y = test_position.y * RENDER_SCALE,
    //       width = test_size.x * RENDER_SCALE,
    //       height = test_size.y * RENDER_SCALE,
    //     },
    //     origin = test_size / 2 * RENDER_SCALE,
    //     rotation = rotation,
    //     color = rl.BLUE,
    //   )
    //   rl.DrawCircleV(
    //     center = test_position * RENDER_SCALE,
    //     radius = 0.2 * RENDER_SCALE,
    //     color = rl.BLACK,
    //   )
    // }

    defer rl.EndMode2D()
  }
}

_game_add_block :: proc(game: ^Game, position: Vec2, size: Vec2, rotation: f32 = 0) {
  block_body_def := b2.DefaultBodyDef()
  block_body_def.type = .dynamicBody
  block_body_def.position = position
  block_body_def.rotation = b2.MakeRot(rotation)
  block_body_id := b2.CreateBody(game.world, block_body_def)
  dynamic_box := b2.MakeBox(halfWidth = size.x / 2, halfHeight = size.y / 2)
  shape_def := b2.DefaultShapeDef()
  shape_def.material.friction = 0.3
  block_shape_id := b2.CreatePolygonShape(block_body_id, shape_def, dynamic_box)

  _ = handle_map.add(game.entity_map, Entity{
    kind = .Block,
    body_id = block_body_id,
    shape_id = block_shape_id,
    box_size = size,
  })
}

_game_add_projectile :: proc(game: ^Game, position: Vec2, velocity: Vec2 = 0) {
  projectile_body_def := b2.DefaultBodyDef()
  projectile_body_def.type = .dynamicBody
  projectile_body_def.position = position
  projectile_body_def.linearVelocity = velocity
  projectile_body_id := b2.CreateBody(game.world, projectile_body_def)
  circle: b2.Circle
  circle.radius = PROJECTILE_RADIUS
  shape_def := b2.DefaultShapeDef()
  shape_def.density = PROJECTILE_DENSITY
  shape_def.material.friction = 0.3
  projectile_shape_id := b2.CreateCircleShape(projectile_body_id, shape_def, circle)

  _ = handle_map.add(game.entity_map, Entity{
    kind = .Projectile,
    body_id = projectile_body_id,
    shape_id = projectile_shape_id,
  })
}

_draw_debug_point :: proc(point: Vec2, radius: f32 = 0.2, color := rl.MAGENTA) {
  rl.DrawCircleV(
    center = point * RENDER_SCALE,
    radius = radius * RENDER_SCALE,
    color = color,
  )
}
