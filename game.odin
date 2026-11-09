package ballista

import rl "vendor:raylib"
import b2 "vendor:box2d"

import "core:container/handle_map"
import "core:log"
import "core:math"
import "core:math/linalg"

TEXTURES_DIR :: "assets/textures/"

PIXELS_PER_METER             :: 20
PROJECTILE_RADIUS            :: 10
PROJECTILE_DENSITY           :: 2.5
PROJECTILE_COLOR             :: rl.BLUE
ANCHOR_POSITION              :: Vec2{ -1000, 400 }
MAX_DISTANCE_TO_ANCHOR       :: 160
DRAW_ORIGIN_POINTS           :: true
PROJECTILE_TRAJECTORY_POINTS :: 20
PROJECTILE_TRAJECTORY_STEP   :: 10

PHYSICS_GRAVITY        :: Vec2{ 0, 10 * PIXELS_PER_METER }
PHYSICS_TIME_STEP      :: 1.0 / TARGET_FPS
PHYSICS_SUBSTEP_COUNT  :: 4
PHYSICS_ENABLED        :: true
PHYSICS_THREADS        :: 4
PHYSICS_SLEEP_ENABLED  :: true

MIN_PROJECTILE_DAMAGE :: 0
MAX_PROJECTILE_DAMAGE :: 80

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
  material: Material,
}

Entity_Map :: handle_map.Static_Handle_Map(MAX_ENTITIES, Entity, Entity_Handle)

Game :: struct {
  world: b2.WorldId,
  entity_map: ^Entity_Map,
  camera: rl.Camera2D,

  aiming: bool,
  aimed_projectile_position: Vec2,
  aimed_projectile_velocity: Vec2,

  white_texture: rl.Texture2D,
  magenta_texture: rl.Texture2D,
  background_texture: rl.Texture2D,
  block_textures: [Material][Damage_Level]rl.Texture2D,
}

@(rodata) texture_paths := [Material][Damage_Level]cstring{
  .Wood = {
    .No_Damage = TEXTURES_DIR + "physics_elements/Wood elements/elementWood017.png",
    .Low_Damage = TEXTURES_DIR + "physics_elements/Wood elements/elementWood022.png",
    .High_Damage = TEXTURES_DIR + "physics_elements/Wood elements/elementWood049.png",
  },
  .Stone = {
    .No_Damage = TEXTURES_DIR + "physics_elements/Stone elements/elementStone017.png",
    .Low_Damage = TEXTURES_DIR + "physics_elements/Stone elements/elementStone022.png",
    .High_Damage = TEXTURES_DIR + "physics_elements/Stone elements/elementStone049.png",
  },
  .Metal = {
    .No_Damage = TEXTURES_DIR + "physics_elements/Metal elements/elementMetal017.png",
    .Low_Damage = TEXTURES_DIR + "physics_elements/Metal elements/elementMetal022.png",
    .High_Damage = TEXTURES_DIR + "physics_elements/Metal elements/elementMetal049.png",
  },
}

BLOCK_TEXTURE_NPATCH :: rl.NPatchInfo {
  source = rl.Rectangle { 0, 0, 140, 140 },
  left = 12,
  top = 12,
  right = 12,
  bottom = 12,
  layout = .NINE_PATCH,
}

game_init :: proc(game: ^Game) {
  b2.SetLengthUnitsPerMeter(PIXELS_PER_METER)
  world_def := b2.DefaultWorldDef()
  world_def.gravity = PHYSICS_GRAVITY
  world_def.enableSleep = PHYSICS_SLEEP_ENABLED
  world_def.workerCount = PHYSICS_THREADS
  game.world = b2.CreateWorld(world_def)

  game.entity_map = new(Entity_Map)

  game.aimed_projectile_position = ANCHOR_POSITION
  game.aimed_projectile_velocity = 0

  white_image := rl.GenImageColor(1, 1, rl.WHITE)
  defer rl.UnloadImage(white_image)

  magenta_image := rl.GenImageColor(1, 1, rl.MAGENTA)
  defer rl.UnloadImage(magenta_image)

  game.white_texture = rl.LoadTextureFromImage(white_image)
  game.magenta_texture = rl.LoadTextureFromImage(magenta_image)

  game.background_texture = rl.LoadTexture(
    TEXTURES_DIR + "background_elements_remastered/Backgrounds/backgroundCastles.png",
  )

  for material in Material {
    for damage_level in Damage_Level {
      game.block_textures[material][damage_level] = rl.LoadTexture(texture_paths[material][damage_level])
    }
  }

  game.camera.target = { 0, 0 }
  game.camera.offset = { f32(rl.GetRenderWidth()) / 2, f32(rl.GetRenderHeight()) / 2 }
  game.camera.rotation = 0
  game.camera.zoom = 1

  _game_add_ground(game, { 0, 700 }, { 3000, 200 })

  _game_add_block(game, {   0,  500 }, {  20, 200 }, .Metal)
  _game_add_block(game, { 200,  500 }, {  20, 200 }, .Metal)
  _game_add_block(game, { 100,  390 }, { 220,  20 }, .Metal)

  _game_add_block(game, {   0,  280 }, {  20, 200 }, .Stone)
  _game_add_block(game, { 200,  280 }, {  20, 200 }, .Stone)
  _game_add_block(game, { 100,  170 }, { 220,  20 }, .Stone)

  _game_add_block(game, {   0,   60 }, {  20, 200 })
  _game_add_block(game, { 200,   60 }, {  20, 200 })
  _game_add_block(game, { 100,  -50 }, { 220,  20 })

  _game_add_block(game, {  50, -156 }, {  20, 200 }, rotation = math.to_radians_f32(24))
  _game_add_block(game, { 150, -156 }, {  20, 200 }, rotation = math.to_radians_f32(-24))
}

game_deinit :: proc(game: Game) {
  for material in Material {
    for damage_level in Damage_Level {
      rl.UnloadTexture(game.block_textures[material][damage_level])
    }
  }

  rl.UnloadTexture(game.background_texture)
  rl.UnloadTexture(game.magenta_texture)
  rl.UnloadTexture(game.white_texture)

  handle_map.clear(game.entity_map)
  free(game.entity_map)

  b2.DestroyWorld(game.world)
}

game_update :: proc(game: ^Game, dt: f32) {
  CAMERA_MOVE_SPEED :: 200
  CAMERA_ZOOM_SPEED :: 0.3

  if rl.IsKeyDown(.W) do game.camera.target.y -= CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.S) do game.camera.target.y += CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.A) do game.camera.target.x -= CAMERA_MOVE_SPEED * dt
  if rl.IsKeyDown(.D) do game.camera.target.x += CAMERA_MOVE_SPEED * dt

  if rl.IsKeyDown(.UP)   do game.camera.zoom *= 1 + (CAMERA_ZOOM_SPEED * dt)
  if rl.IsKeyDown(.DOWN) do game.camera.zoom *= 1 - (CAMERA_ZOOM_SPEED * dt)

  pointer_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera)

  {
    projectile_offset := linalg.clamp_length(pointer_position - ANCHOR_POSITION, MAX_DISTANCE_TO_ANCHOR)
    projectile_position := ANCHOR_POSITION + projectile_offset
    projectile_velocity := -projectile_offset * 5

    if rl.IsMouseButtonDown(.LEFT) {
      game.aiming = true
      game.aimed_projectile_position = projectile_position
      game.aimed_projectile_velocity = projectile_velocity
    } else if rl.IsMouseButtonReleased(.LEFT) {
      game.aiming = false
      game.aimed_projectile_position = ANCHOR_POSITION
      game.aimed_projectile_velocity = 0
      _game_add_projectile(game, projectile_position, projectile_velocity)
    }

    if rl.IsMouseButtonPressed(.RIGHT) {
      _game_add_projectile(game, pointer_position)
    }
  }

  when PHYSICS_ENABLED { b2.World_Step(game.world, PHYSICS_TIME_STEP, PHYSICS_SUBSTEP_COUNT) }

  deletion_queue := make([dynamic]Entity_Handle, context.temp_allocator)

  contact_events := b2.World_GetContactEvents(game.world)

  for i in 0..<contact_events.hitCount {
    hit_event := contact_events.hitEvents[i]

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

game_draw :: proc(game: ^Game) {
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

    rl.DrawTextureEx(
      texture = game.background_texture,
      position = { -1500, -1500 },
      rotation = 0,
      scale = 3,
      tint = rl.WHITE,
    )

    if game.aiming {
      _draw_trajectory(
        origin = game.aimed_projectile_position,
        velocity = game.aimed_projectile_velocity,
        points = PROJECTILE_TRAJECTORY_POINTS,
        step = PROJECTILE_TRAJECTORY_STEP,
      )
    }

    iterator := handle_map.iterator_make(game.entity_map)
    for entity, handle in handle_map.iterate(&iterator) {
      _game_draw_entity(game, entity)
    }

    _draw_anchor()
    _draw_projectile(game.aimed_projectile_position)

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

_game_add_block :: proc(
  game: ^Game,
  position: Vec2,
  size: Vec2,
  material: Material = .Wood,
  rotation: f32 = 0,
) -> (ok := false) {
  entity_handle := handle_map.add(game.entity_map, Entity{
    kind = .Block,
    box_size = size,
    health = max_health_by_material[material],
    material = material,
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

_game_draw_entity :: proc(game: ^Game, entity: ^Entity) {
  texture, color := _game_get_entity_texture_and_color(game, entity^)
  switch entity.kind {
  case .Ground:
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
      color = color,
    )
    when DRAW_ORIGIN_POINTS { _draw_point(position) }
  case .Block:
    transform := b2.Body_GetTransform(entity.body_id)
    position := transform.p
    rotation := transform.q
    size := entity.box_size
    rl.DrawTextureNPatch(
      texture = texture,
      nPatchInfo = BLOCK_TEXTURE_NPATCH,
      dstrec = rl.Rectangle{
        x = position.x,
        y = position.y,
        width = size.x,
        height = size.y,
      },
      origin = size / 2,
      rotation = linalg.to_degrees(b2.Rot_GetAngle(rotation)),
      tint = color,
    )
    when DRAW_ORIGIN_POINTS { _draw_point(position) }
  case .Projectile:
    position := b2.Body_GetPosition(entity.body_id)
    rl.DrawCircleV(
      center = position,
      radius = PROJECTILE_RADIUS,
      color = color,
    )
    when DRAW_ORIGIN_POINTS { _draw_point(position) }
  }
}

_game_get_entity_texture_and_color :: proc(game: ^Game, entity: Entity) -> (rl.Texture2D, rl.Color) {
  switch entity.kind {
  case .Ground:
    return game.white_texture, rl.GREEN
  case .Block:
    damage_level := _get_block_damage_level(entity)
    return game.block_textures[entity.material][damage_level], rl.WHITE
  case .Projectile:
    return game.white_texture, PROJECTILE_COLOR
  }

  return game.magenta_texture, rl.WHITE
}

_draw_trajectory :: proc(origin: Vec2, velocity: Vec2, points: uint, step: uint) {
  for i in 1..=points {
    time := f32(i * step) * PHYSICS_TIME_STEP
    position := origin + velocity * time + 0.5 * PHYSICS_GRAVITY * time * time
    alpha := f32(points - i) / f32(points) * 255
    _draw_point(position, color = { 0, 0, 0, u8(alpha) })
  }
}

_draw_point :: proc(point: Vec2, radius: f32 = 3, color := rl.MAGENTA) {
  rl.DrawCircleV(
    center = point,
    radius = radius,
    color = color,
  )
}

_draw_anchor :: proc() {
  rl.DrawCircleV(
    center = ANCHOR_POSITION,
    radius = 3,
    color = rl.BLACK,
  )
}

_draw_projectile :: proc(position: Vec2) {
  rl.DrawCircleV(
    center = position,
    radius = PROJECTILE_RADIUS,
    color = PROJECTILE_COLOR,
  )
}

_calculate_damage :: proc(approach_speed: f32) -> f32 {
  t := approach_speed / 1000
  return math.lerp(f32(MIN_PROJECTILE_DAMAGE), f32(MAX_PROJECTILE_DAMAGE), t)
}

_get_block_damage_level :: proc(entity: Entity) -> Damage_Level {
  health_factor := entity.health / max_health_by_material[entity.material]
  switch health_factor {
  case 0.75..=1000.0:
    return .No_Damage
  case 0.3..<0.75:
    return .Low_Damage
  case:
    return .High_Damage
  }
}

Material :: enum {
  Wood,
  Stone,
  Metal,
}

@(rodata) max_health_by_material := [Material]f32 {
  .Wood = 100,
  .Stone = 200,
  .Metal = 300,
}

Damage_Level :: enum {
  No_Damage,
  Low_Damage,
  High_Damage,
}
