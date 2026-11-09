package ballista

import rl "vendor:raylib"
import b2 "vendor:box2d"

import "core:container/handle_map"
import "core:log"
import "core:math"
import "core:math/linalg"

PIXELS_PER_METER       :: 20
PROJECTILE_RADIUS      :: 10
PROJECTILE_DENSITY     :: 2.5
ANCHOR_POSITION        :: Vec2{ -1000, 400 }
MAX_DISTANCE_TO_ANCHOR :: 160
PHYSICS_ENABLED        :: true
PHYSICS_THREADS        :: 4
PHYSICS_SLEEP_ENABLED  :: true
DRAW_ORIGIN_POINTS     :: true

BLOCK_MAX_HEALTH :: 100
MIN_DAMAGE       :: 0
MAX_DAMAGE       :: 80

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

MAX_ENTITIES :: 20000

Entity_Handle :: handle_map.Handle64

Entity_Kind :: enum {
  Ground,
  Block,
  Projectile,
}

Entity :: struct {
  handle: Entity_Handle,
  kind: Entity_Kind,
  body_id: b2.BodyId,
  shape_id: b2.ShapeId,
  box_size: Vec2,
  health: f32,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  camera: rl.Camera2D,
  world: b2.WorldId,
  entity_map: ^Entity_Map,
  projectile_position: Vec2,
}

game_init :: proc(game: ^Game) {
  b2.SetLengthUnitsPerMeter(PIXELS_PER_METER)

  game.entity_map = new(Entity_Map, g_static_lifetime_allocator)

  game.camera.target = { 0, 0 }
  game.camera.offset = { f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2 }
  game.camera.rotation = 0
  game.camera.zoom = 1

  world_def := b2.DefaultWorldDef()
  world_def.gravity = { 0, 10 * PIXELS_PER_METER }
  world_def.enableSleep = PHYSICS_SLEEP_ENABLED
  world_def.workerCount = PHYSICS_THREADS
  game.world = b2.CreateWorld(world_def)

  game.projectile_position = ANCHOR_POSITION

  _game_add_ground(game, { 0, 700 }, { 3000, 200 })

  _game_add_block(game, {   0,  500 }, {  20, 200 })
  _game_add_block(game, { 200,  500 }, {  20, 200 })
  _game_add_block(game, { 100,  390 }, { 220,  20 })

  _game_add_block(game, {   0,  280 }, {  20, 200 })
  _game_add_block(game, { 200,  280 }, {  20, 200 })
  _game_add_block(game, { 100,  170 }, { 220,  20 })

  _game_add_block(game, {   0,   60 }, {  20, 200 })
  _game_add_block(game, { 200,   60 }, {  20, 200 })
  _game_add_block(game, { 100,  -50 }, { 220,  20 })

  _game_add_block(game, {  50, -156 }, {  20, 200 }, math.to_radians_f32(24))
  _game_add_block(game, { 150, -156 }, {  20, 200 }, math.to_radians_f32(-24))

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

  pointer_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera)

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

  deletion_queue := make([dynamic]Entity_Handle, context.temp_allocator)

  contact_events := b2.World_GetContactEvents(game.world)

  for i in 0..<contact_events.hitCount {
    hit_event := contact_events.hitEvents[i]
    log.debugf("%#v", hit_event)

    entity_handle_a := transmute(Entity_Handle)b2.Shape_GetUserData(hit_event.shapeIdA)
    entity_handle_b := transmute(Entity_Handle)b2.Shape_GetUserData(hit_event.shapeIdB)

    entity_a, _ := handle_map.get(game.entity_map, entity_handle_a)
    entity_b, _ := handle_map.get(game.entity_map, entity_handle_b)

    if entity_a.kind == .Block {
      damage := _calculate_damage(hit_event.approachSpeed)
      entity_a.health -= damage
      if entity_a.health <= 0 {
        append(&deletion_queue, entity_a.handle)
      }
    }

    if entity_b.kind == .Block {
      damage := _calculate_damage(hit_event.approachSpeed)
      entity_b.health -= damage
      if entity_b.health <= 0 {
        append(&deletion_queue, entity_b.handle)
      }
    }
  }

  for entity_handle in deletion_queue {
    _game_remove_entity(game, entity_handle)
  }
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
      entity_color := _get_entity_color(entity^)
      switch entity.kind {
      case .Ground, .Block:
        transform := b2.Body_GetTransform(entity.body_id)
        position := transform.p
        rotation := transform.q
        size := entity.box_size
        rl.DrawRectanglePro(
          rec = rl.Rectangle{
            x = position.x,
            y = position.y,
            width = size.x,
            height = size.y,
          },
          origin = size / 2,
          rotation = linalg.to_degrees(b2.Rot_GetAngle(rotation)),
          color = entity_color,
        )
        when DRAW_ORIGIN_POINTS { _draw_point(position) }
      case .Projectile:
        position := b2.Body_GetPosition(entity.body_id)
        rl.DrawCircleV(
          center = position,
          radius = PROJECTILE_RADIUS,
          color = entity_color,
        )
        when DRAW_ORIGIN_POINTS { _draw_point(position) }
      }
    }

    rl.DrawCircleV(
      center = ANCHOR_POSITION,
      radius = 3,
      color = rl.BLACK,
    )

    rl.DrawCircleV(
      center = game.projectile_position,
      radius = PROJECTILE_RADIUS,
      color = entity_colors[.Projectile],
    )

    defer rl.EndMode2D()
  }
}

_game_add_ground :: proc(game: ^Game, position: Vec2, size: Vec2) -> (ok := false) {
  entity_handle := handle_map.add(game.entity_map, Entity{
    kind = .Ground,
    box_size = { 3000, 200 },
  }) or_return

  entity := handle_map.get(game.entity_map, entity_handle) or_return

  ground_body_def := b2.DefaultBodyDef()
  ground_body_def.userData = transmute(rawptr)entity_handle
  ground_body_def.position = position
  ground_body_id := b2.CreateBody(game.world, ground_body_def)
  ground_box := b2.MakeBox(halfWidth = size.x / 2, halfHeight = size.y / 2)
  ground_shape_def := b2.DefaultShapeDef()
  ground_shape_def.userData = transmute(rawptr)entity_handle
  ground_shape_id := b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

  entity.body_id = ground_body_id
  entity.shape_id = ground_shape_id

  ok = true
  return
}

_game_add_block :: proc(game: ^Game, position: Vec2, size: Vec2, rotation: f32 = 0) -> (ok := false) {
  entity_handle := handle_map.add(game.entity_map, Entity{
    kind = .Block,
    box_size = size,
    health = BLOCK_MAX_HEALTH,
  }) or_return

  entity := handle_map.get(game.entity_map, entity_handle) or_return

  block_body_def := b2.DefaultBodyDef()
  block_body_def.userData = transmute(rawptr)entity_handle
  block_body_def.type = .dynamicBody
  block_body_def.position = position
  block_body_def.rotation = b2.MakeRot(rotation)
  block_body_id := b2.CreateBody(game.world, block_body_def)
  dynamic_box := b2.MakeBox(halfWidth = size.x / 2, halfHeight = size.y / 2)
  shape_def := b2.DefaultShapeDef()
  shape_def.userData = transmute(rawptr)entity_handle
  shape_def.material.friction = 0.3
  shape_def.enableHitEvents = true
  block_shape_id := b2.CreatePolygonShape(block_body_id, shape_def, dynamic_box)

  entity.body_id = block_body_id
  entity.shape_id = block_shape_id

  ok = true
  return
}

_game_add_projectile :: proc(game: ^Game, position: Vec2, velocity: Vec2 = 0) -> (ok := false) {
  entity_handle := handle_map.add(game.entity_map, Entity{
    kind = .Projectile,
  }) or_return

  entity := handle_map.get(game.entity_map, entity_handle) or_return

  projectile_body_def := b2.DefaultBodyDef()
  projectile_body_def.userData = transmute(rawptr)entity_handle
  projectile_body_def.type = .dynamicBody
  projectile_body_def.position = position
  projectile_body_def.linearVelocity = velocity
  projectile_body_id := b2.CreateBody(game.world, projectile_body_def)
  circle: b2.Circle
  circle.radius = PROJECTILE_RADIUS
  shape_def := b2.DefaultShapeDef()
  shape_def.userData = transmute(rawptr)entity_handle
  shape_def.density = PROJECTILE_DENSITY
  shape_def.material.friction = 0.3
  shape_def.enableHitEvents = true
  projectile_shape_id := b2.CreateCircleShape(projectile_body_id, shape_def, circle)

  entity.body_id = projectile_body_id
  entity.shape_id = projectile_shape_id

  ok = true
  return
}

_game_remove_entity :: proc(game: ^Game, entity_handle: Entity_Handle) -> (ok := false) {
  entity := handle_map.get(game.entity_map, entity_handle) or_return
  b2.DestroyShape(entity.shape_id, updateBodyMass = false)
  b2.DestroyBody(entity.body_id)
  return handle_map.remove(game.entity_map, entity_handle)
}

_draw_point :: proc(point: Vec2, radius: f32 = 3, color := rl.MAGENTA) {
  rl.DrawCircleV(
    center = point,
    radius = radius,
    color = color,
  )
}

_calculate_damage :: proc(approach_speed: f32) -> f32 {
  t := approach_speed / 1000
  return math.lerp(f32(MIN_DAMAGE), f32(MAX_DAMAGE), t)
}

@(rodata) entity_colors := [Entity_Kind]rl.Color{
  .Ground     = { 0, 255, 0, 255 },
  .Block      = { 255, 0, 0, 255 },
  .Projectile = { 0, 0, 255, 255 },
}

_get_entity_color :: proc(entity: Entity) -> rl.Color {
  color := entity_colors[entity.kind]
  if entity.kind == .Block {
    f32_color := cast(Vec4)color
    f32_color.rgb *= entity.health / BLOCK_MAX_HEALTH
    color = cast(rl.Color)(f32_color)
  }
  return color
}
