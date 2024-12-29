package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import rl "vendor:raylib"

GiftType :: enum {
	RED,
	GREEN,
	BLUE,
	YELLOW,
	ORANGE,
	WHITE,
}

GiftTemplate :: struct {
	id:    int,
	name:  string,
	color: rl.Color,
}

GiftTemplateManager :: struct {
	gifts: map[GiftType]GiftTemplate,
}

Gift :: struct {
	position:        [2]f32,
	velocity:        [2]f32,
	width:           f32,
	height:          f32,
	type:            GiftType,
	can_move:        bool,
	chosen:          int,
	off_screen:      bool,
	bottom_shake:    bool,
	collision_shake: bool,
}

FadeCallback :: proc(gm: ^GameManager)

GameState :: enum {
	prepare_round,
	on_round,
	check_round_result,
	game_over,
	show_round_result,
	initial_screen,
}

Round :: struct {
	gifts:              [dynamic]Gift,
	chosen:             [dynamic]Gift,
	ignored:            [dynamic]Gift,
	needed_gifts:       [5]GiftType,
	particles:          [dynamic]Particle,
	all_gifts_selected: bool,
}

Particle :: struct {
	position: [2]f32,
	velocity: [2]f32,
	lifetime: f32,
	size:     f32,
}

GameCamera :: struct {
	camera:      ^rl.Camera2D,
	shake_timer: f32,
	intensity:   f32,
}

FadeType :: enum {
	fadein,
	fadeout,
	inout,
	outin,
}

FadePhase :: enum {
	fadein,
	fadeout,
}

ScreenFade :: struct {
	color:            [4]u8,
	lifetime:         f32,
	current_lifetime: f32,
	alpha:            f32,
	type:             FadeType,
	phase:            FadePhase,
	callback:         FadeCallback,
}

TopPipe :: struct {
	frame_time:    f32,
	total_frames:  f32,
	current_frame: f32,
	current_time:  f32,
	active:        bool,
}

GameManager :: struct {
	round_number:                 int,
	round:                        Round,
	gift_templates:               GiftTemplateManager,
	spawn_interval:               f32,
	initial_spawn_interval:       f32,
	last_spawn_time:              f32,
	spawn_interval_growth_factor: f32,
	dt:                           f32,
	screen_width:                 f32,
	screen_height:                f32,
	fall_speed_incr:              f32,
	max_fall_speed:               f32,
	fall_speed_growth_factor:     f32,
	initial_max_fall_speed:       f32,
	initial_fall_speed_incr:      f32,
	lifes:                        int,
	game_state:                   GameState,
	camera:                       GameCamera,
	fade:                         ScreenFade,
	assets:                       map[string]rl.Texture,
	font:                         rl.Font,
	top_pipe:                     TopPipe,
}

GIFT_WIDTH :: 64
GIFT_HEIGHT :: 64


start_round :: proc(gm: ^GameManager) {
	next_round := gm.round_number + 1
	fall_speed_incr :=
		gm.initial_fall_speed_incr +
		(gm.fall_speed_growth_factor * math.log_f32(f32(next_round), math.E))
	spawn_interval :=
		gm.initial_spawn_interval -
		(gm.spawn_interval_growth_factor * math.log_f32(f32(next_round), math.E))
	gm.round_number = next_round
	gm.fall_speed_incr = clamp(fall_speed_incr, 7, 25)
	gm.spawn_interval = clamp(spawn_interval, 0.5, 5)

	for i in 0 ..< 5 {
		gm.round.needed_gifts[i] = rand.choice_enum(GiftType)
	}
	gm.round.all_gifts_selected = false
	gm.round.chosen = nil
	gm.round.ignored = nil
	gm.round.gifts = nil
	gm.game_state = .on_round
	fmt.println(gm.fall_speed_incr, gm.spawn_interval)
}


create_collision_particle :: proc(gm: ^GameManager, position: [2]f32) {
	left_position: [2]f32 = {position.x + 8, position.y + GIFT_HEIGHT - 5}
	right_position: [2]f32 = {(position.x + GIFT_WIDTH) - 8, position.y + GIFT_HEIGHT - 5}
	for i in 0 ..< 30 {
		particle := Particle {
			position = left_position,
			velocity = {rand.float32_range(-180, 180) / 150, rand.float32_range(-200, 0) / 150},
			lifetime = rand.float32_range(0.3, 0.8),
			size     = rand.float32_range(1.6, 2.8),
		}
		append(&gm.round.particles, particle)
	}
	for i in 0 ..< 30 {
		particle := Particle {
			position = right_position,
			velocity = {rand.float32_range(-180, 180) / 150, rand.float32_range(-200, 0) / 150},
			lifetime = rand.float32_range(0.3, 0.8),
			size     = rand.float32_range(1.6, 2.8),
		}
		append(&gm.round.particles, particle)
	}
}

draw_top_pipe :: proc(gm: ^GameManager) {
	width: f32 = f32(gm.assets["toppipe"].width) / gm.top_pipe.total_frames
	height: f32 = f32(gm.assets["toppipe"].height)

	if gm.top_pipe.active {
		gm.top_pipe.current_time += gm.dt
		if gm.top_pipe.current_time >= gm.top_pipe.frame_time {
			gm.top_pipe.current_time = 0
			gm.top_pipe.current_frame += 1
			if gm.top_pipe.current_frame >= gm.top_pipe.total_frames {
				gm.top_pipe.current_frame = 0
				gm.top_pipe.active = false
			}
		}
	}
	source := rl.Rectangle{gm.top_pipe.current_frame * width, 0, width, height}
	x_pos := (gm.screen_width / 2) - (width / 2)
	dest := rl.Rectangle{x_pos, -5, width, height}
	rl.DrawTexturePro(gm.assets["toppipe"], source, dest, {0, 0}, 0, rl.WHITE)

}

update_particles :: proc(gm: ^GameManager) {
	for &particle, i in gm.round.particles {
		particle.lifetime -= gm.dt
		if particle.lifetime <= 0 {
			ordered_remove(&gm.round.particles, i)
			continue
		}
		particle.position += {particle.velocity.x, particle.velocity.y}
		particle.velocity.y += 3 * gm.dt
	}
}

particles_draw :: proc(gm: ^GameManager) {
	for particle in gm.round.particles {
		alpha := u8(clamp(particle.lifetime * 255, 0, 255))
		rl.DrawCircleV(particle.position, particle.size, {255, 255, 255, u8(alpha)})
	}
}

init_gift_template :: proc(gm: ^GameManager) {
	gift_template_manager := GiftTemplateManager {
		gifts = make(map[GiftType]GiftTemplate, 0),
	}
	if template_file, ok := os.read_entire_file(
		"./src/gifts.json",
		allocator = context.temp_allocator,
	); ok {
		gift_template := make([dynamic]GiftTemplate)
		if err := json.unmarshal(template_file, &gift_template); err == nil {
			for template in gift_template {
				gift_type_enum := GiftType(template.id)
				gift_template_manager.gifts[gift_type_enum] = template
			}
		}
	}
	gm.gift_templates = gift_template_manager
}

create_gift :: proc(gm: ^GameManager) {
	gift_type := rand.choice_enum(GiftType)
	y_pos: f32 = f32(gm.assets["toppipe"].height) - (GIFT_HEIGHT + 35)
	gift := Gift {
		position = {(gm.screen_width / 2) - (GIFT_WIDTH / 2), y_pos},
		velocity = {0, 0},
		width    = GIFT_WIDTH,
		height   = GIFT_WIDTH,
		can_move = false,
		chosen   = -1,
		type     = gift_type,
	}
	gm.top_pipe.active = true
	append(&gm.round.gifts, gift)
}


reset_game :: proc(gm: ^GameManager) {
	gm.spawn_interval = gm.initial_spawn_interval
	gm.fall_speed_incr = gm.initial_fall_speed_incr
	gm.round_number = 0
	gm.last_spawn_time = 0
	gm.lifes = 5
	gm.game_state = .initial_screen
}

gift_update :: proc(gm: ^GameManager) {
	gm.last_spawn_time += gm.dt
	if gm.last_spawn_time >= gm.spawn_interval {
		gm.last_spawn_time = 0
		create_gift(gm)
	}
	//ROUND GIFTS
	for &gift, i in gm.round.gifts {
		gift.velocity.y = rl.Clamp(gift.velocity.y + gm.fall_speed_incr, 0, gm.max_fall_speed)

		if i == len(gm.round.gifts) - 1 &&
		   gm.top_pipe.active == true &&
		   gm.top_pipe.current_frame <= 5 {
			gift.velocity.y = 0
		}
		gift.position.y += gift.velocity.y * gm.dt

		if gift.can_move && rl.IsKeyPressed(.D) && gift.chosen == -1 && len(gm.round.chosen) < 5 {
			gift.chosen = 1
			append(&gm.round.chosen, gift)
			ordered_remove(&gm.round.gifts, i)
		}
		if gift.can_move && rl.IsKeyPressed(.A) && gift.chosen == -1 && len(gm.round.chosen) < 5 {
			gift.chosen = 0
			append(&gm.round.ignored, gift)
			ordered_remove(&gm.round.gifts, i)
		}

		//y collision
		{
			if i > 0 {
				next_gift := gm.round.gifts[i - 1]
				col_result := rl.GetCollisionRec(
					{gift.position.x, gift.position.y, gift.width, gift.height},
					{
						next_gift.position.x,
						next_gift.position.y,
						next_gift.width,
						next_gift.height,
					},
				)
				if col_result.height > 0 {
					if !gift.collision_shake {
						gm.camera.shake_timer = 0.25
						gift.collision_shake = true
						create_collision_particle(gm, gift.position)
					}
					gift.position.y -= col_result.height
				}
			}
			if gift.position.y + gift.height >= gm.screen_height {
				if !gift.bottom_shake {
					gm.camera.shake_timer = 0.25
					gift.bottom_shake = true
					create_collision_particle(gm, gift.position)
				}
				gift.bottom_shake = true
				gift.position.y = gm.screen_height - gift.height
				gift.can_move = true
			}
		}
	}

	//not the best way, but its a way xD
	for &gift in gm.round.gifts {
		for chosen_gift in gm.round.chosen {
			col_result := rl.GetCollisionRec(
				{gift.position.x, gift.position.y, gift.width, gift.height},
				{
					chosen_gift.position.x,
					chosen_gift.position.y,
					chosen_gift.width,
					chosen_gift.height,
				},
			)
			if col_result.height > 0 {
				gift.position.y -= col_result.height
			}
		}
		for chosen_gift in gm.round.ignored {
			col_result := rl.GetCollisionRec(
				{gift.position.x, gift.position.y, gift.width, gift.height},
				{
					chosen_gift.position.x,
					chosen_gift.position.y,
					chosen_gift.width,
					chosen_gift.height,
				},
			)
			if col_result.height > 0 {
				gift.position.y -= col_result.height
			}
		}
	}

	//ROUND CHOSEN GIFTS
	out_off_screen := 0
	for &gift, i in gm.round.chosen {
		gift.velocity.x = 350
		gift.position.y = gm.screen_height - gift.height
		gift.position.x += gift.velocity.x * gm.dt
		if gift.position.x >= gm.screen_width {
			gift.off_screen = true
		}
		if gift.off_screen == true {
			out_off_screen += 1
		}
	}

	if out_off_screen >= 5 {
		gm.round.all_gifts_selected = true
	}

	//ROUND IGNORED GIFTS
	for &gift, i in gm.round.ignored {
		gift.velocity.x = -350
		gift.position.y = gm.screen_height - gift.height
		gift.position.x += gift.velocity.x * gm.dt
	}
}


check_round_result :: proc(gm: ^GameManager) {
	total_success := 0
	for _, i in gm.round.chosen {
		if gm.round.chosen[i].type == gm.round.needed_gifts[i] {
			total_success += 1
		}
	}
	gm.lifes -= 5 - total_success
	gm.game_state = .show_round_result
}

update_game :: proc(gm: ^GameManager) {
	if gm.game_state == .on_round {
		gift_update(gm)
		if gm.round.all_gifts_selected {
			gm.game_state = .check_round_result
			return
		}
	}

	if gm.game_state == .on_round && len(gm.round.gifts) >= 14 {
		gm.game_state = .check_round_result
		return
	}

	if gm.game_state == .prepare_round {
		if gm.lifes <= 0 {
			gm.game_state = .game_over
			return
		}
		start_round(gm)
		return
	}

	if gm.game_state == .check_round_result {
		check_round_result(gm)
		return
	}

	if gm.game_state == .game_over {
		if rl.IsKeyPressed(.SPACE) {
			reset_game(gm)
		}
	}
}

gift_draw :: proc(gm: ^GameManager) {
	for gift in gm.round.gifts {
		rl.DrawTextureV(gm.assets["box"], gift.position, gm.gift_templates.gifts[gift.type].color)
	}
	for gift in gm.round.chosen {
		rl.DrawTextureV(gm.assets["box"], gift.position, gm.gift_templates.gifts[gift.type].color)
	}
	for gift in gm.round.ignored {
		rl.DrawTextureV(gm.assets["box"], gift.position, gm.gift_templates.gifts[gift.type].color)
	}
}

ui_draw :: proc(gm: ^GameManager) {
	if gm.game_state == .on_round {
		rl.DrawTextEx(gm.font, fmt.ctprintf("LIFES: %v", gm.lifes), {12, 8}, 30, 1, rl.BLACK)
		rl.DrawTextEx(gm.font, fmt.ctprintf("LIFES: %v", gm.lifes), {15, 5}, 30, 1, rl.WHITE)
		rl.DrawTextEx(
			gm.font,
			fmt.ctprintf("ROUND: %v", gm.round_number),
			{(gm.screen_width - 130) + 2, 8},
			30,
			1,
			rl.BLACK,
		)
		rl.DrawTextEx(
			gm.font,
			fmt.ctprintf("ROUND: %v", gm.round_number),
			{(gm.screen_width - 130), 5},
			30,
			1,
			rl.WHITE,
		)

		rl.DrawRectangleRec({gm.screen_width - 80, 370, 70, (38 * 5) + 30}, {15, 15, 15, 200})
		for type, i in gm.round.needed_gifts {
			color := gm.gift_templates.gifts[type].color
			total_gifts := len(gm.round.needed_gifts)
			position: [2]f32 = {gm.screen_width - 64, f32(380 + ((total_gifts - 1 - i) * 40))}
			rl.DrawTextEx(
				gm.font,
				fmt.ctprintf("%v.", i + 1),
				{position.x - 10, position.y + (GIFT_HEIGHT / 2) - 5},
				15,
				1,
				rl.WHITE,
			)
			rl.DrawTextureEx(gm.assets["box"], position, 0, 0.6, color)
		}
	}

	if gm.game_state == .game_over {
		text_width := rl.MeasureTextEx(gm.font, "GAMER OVER!", 45, 0)
		y_pos: f32 = (gm.screen_height / 2) + f32(math.sin(rl.GetTime() * 3) * 15)
		x_pos: f32 = ((gm.screen_width - text_width.x) / 2)
		rl.DrawTextEx(gm.font, fmt.ctprint("GAMER OVER!"), {x_pos + 3, y_pos + 3}, 45, 0, rl.BLACK)
		rl.DrawTextEx(gm.font, fmt.ctprint("GAMER OVER!"), {x_pos, y_pos}, 45, 0, rl.WHITE)

		text_width = rl.MeasureTextEx(gm.font, "PRESS SPACE TO RESET", 30, 0)
		x_pos = (gm.screen_width - text_width.x) / 2
		rl.DrawTextEx(
			gm.font,
			fmt.ctprint("PRESS SPACE TO RESET"),
			{x_pos + 3, 650 + 3},
			30,
			0,
			rl.BLACK,
		)
		rl.DrawTextEx(gm.font, fmt.ctprint("PRESS SPACE TO RESET"), {x_pos, 650}, 30, 0, rl.WHITE)
	}
}

draw_result :: proc(gm: ^GameManager) {
	spacing: f32 = 80
	amplitude := 15
	base_y: f32 = 400
	total_width := spacing * (5 - 1)
	start_x := (gm.screen_width - total_width) / 2

	right := 0
	for gift, i in gm.round.chosen {
		x := start_x + spacing * f32(i)
		phase := f32(i) * (2 * math.PI / f32(5))
		y := base_y + f32(amplitude) * math.sin(f32((rl.GetTime()) * 2) * 2 + phase)
		color := gm.gift_templates.gifts[gift.type].color
		position: [2]f32 = {x - (GIFT_WIDTH / 2), y - (GIFT_HEIGHT / 2)}
		rl.DrawTextureEx(gm.assets["box"], position, 0, 1, color)
		check_color := gift.type == gm.round.needed_gifts[i] ? rl.GREEN : rl.RED
		if check_color == rl.GREEN {
			right += 1
		}
		rl.DrawCircle(i32(x), i32(i32(y) + (gm.assets["box"].height + 10)), 15, check_color)
	}
	rl.DrawTextEx(gm.font, fmt.ctprintf("RIGHT: %v", right), {80 + 3, 550 + 3}, 35, 0, rl.BLACK)
	rl.DrawTextEx(gm.font, fmt.ctprintf("RIGHT: %v", right), {80, 550}, 35, 0, rl.WHITE)
	rl.DrawTextEx(
		gm.font,
		fmt.ctprintf("WRONG: %v", 5 - right),
		{230 + 3, 550 + 3},
		35,
		0,
		rl.BLACK,
	)
	rl.DrawTextEx(gm.font, fmt.ctprintf("WRONG: %v", 5 - right), {230, 550}, 35, 0, rl.WHITE)
	if gm.game_state == .show_round_result && rl.IsKeyPressed(.SPACE) {
		gm.game_state = .prepare_round
	}
	rl.DrawTextEx(
		gm.font,
		fmt.ctprint("PRESS SPACE TO START NEXT ROUND"),
		{30 + 3, 650 + 3},
		25,
		0,
		rl.BLACK,
	)
	rl.DrawTextEx(
		gm.font,
		fmt.ctprint("PRESS SPACE TO START NEXT ROUND"),
		{30, 650},
		25,
		0,
		rl.WHITE,
	)

	if gm.game_state == .show_round_result && rl.IsKeyPressed(.SPACE) {
		gm.game_state = .prepare_round
	}
}

update_camera :: proc(gm: ^GameManager) {
	if gm.camera.shake_timer > 0 {
		gm.camera.shake_timer -= gm.dt
		offset_x := gm.screen_width / 2 + rand.float32_range(-0.25, 0.25)
		//shake_intensity_y := gm.camera.intensity + (0.8 * f32(len(gm.round.gifts)))
		offset_y := gm.screen_height / 2 + rand.float32_range(0, gm.camera.intensity)
		gm.camera.camera.offset.x = offset_x
		gm.camera.camera.offset.y = offset_y
	} else {
		gm.camera.camera.offset = {gm.screen_width / 2, gm.screen_height / 2}
	}
}


create_fade :: proc(type: FadeType, gm: ^GameManager, callback: FadeCallback = nil) {
	if type == .fadein || type == .inout {
		gm.fade.phase = .fadein
	}
	if type == .fadeout || type == .outin {
		gm.fade.phase = .fadeout
	}
	gm.fade.lifetime = 1.5
	gm.fade.current_lifetime = 0
	gm.fade.callback = callback
}

draw_fade :: proc(gm: ^GameManager) {
	if gm.fade.current_lifetime <= gm.fade.lifetime {
		gm.fade.current_lifetime += gm.dt
		alpha: f32 = 0.0
		if gm.fade.phase == .fadein {
			alpha = gm.fade.current_lifetime / gm.fade.lifetime
			if alpha > 1.0 {
				alpha = 1.0
			}
		} else if gm.fade.phase == .fadeout {
			alpha = 1.0 - (gm.fade.current_lifetime / gm.fade.lifetime)
			if alpha < 0.0 {
				alpha = 0.0
			}
		}

		rl.DrawRectangleRec({0, 0, gm.screen_width, gm.screen_height}, {0, 0, 0, u8(255 * alpha)})

		if gm.fade.current_lifetime >= gm.fade.lifetime {
			if gm.fade.type == .fadein || gm.fade.type == .fadeout {
				if gm.fade.callback != nil {
					gm.fade.callback(gm)
				}
			}
			if (gm.fade.type == .inout && gm.fade.phase == .fadeout) ||
			   (gm.fade.type == .outin && gm.fade.phase == .fadein) {
				if gm.fade.callback != nil {
					gm.fade.callback(gm)
				}
			}
			if gm.fade.type == .inout || gm.fade.type == .outin {
				if gm.fade.type == .inout && gm.fade.phase == .fadein {
					gm.fade.phase = .fadeout
					gm.fade.current_lifetime = 0
				} else if gm.fade.type == .outin && gm.fade.phase == .fadeout {
					gm.fade.phase = .fadein
					gm.fade.current_lifetime = 0
				}
			}
		}
	}
}

draw_initial_screen :: proc(gm: ^GameManager) {
	if gm.game_state == .initial_screen {
		text := cstring("PRESS SPACE TO START")
		rl.DrawRectangleV({0, 0}, {gm.screen_width, gm.screen_height}, {0, 0, 0, 150})
		size := rl.MeasureTextEx(gm.font, text, 30, 1)
		rl.DrawTextEx(gm.font, text, {(gm.screen_width - size.x) / 2 + 3, 653}, 30, 1, rl.BLACK)
		rl.DrawTextEx(gm.font, text, {(gm.screen_width - size.x) / 2, 650}, 30, 1, rl.WHITE)
		instruction := `
			Help Santa Claus!
			You are Santa's helper, and your job is to 
			stack the boxes in the correct order before 
			loading them onto the sleigh.

			- The correct box order is shown on the right
			side, starting from bottom to top.

			-Your remaining lives are displayed in the top
			left corner.
			
			-The current round is shown in the top right 
			corner.

			Good luck, and let's get to work!
		`


		rl.DrawTextEx(gm.font, fmt.ctprint(instruction), {30 + 3, 250 + 3}, 16, 1, rl.BLACK)
		rl.DrawTextEx(gm.font, fmt.ctprint(instruction), {30, 250}, 16, 1, rl.WHITE)

		if rl.IsKeyPressed(.SPACE) {
			gm.game_state = .prepare_round
		}
	}
}

load_assets :: proc(gm: ^GameManager) {
	assets := make(map[string]rl.Texture)
	assets["background"] = rl.LoadTexture("./assets/background.png")
	assets["toppipe"] = rl.LoadTexture("./assets/top_pipe-Sheet.png")
	assets["box"] = rl.LoadTexture("./assets/box.png")
	gm.assets = assets
}

main :: proc() {
	rl.InitWindow(450, 800, "JAM")
	rl.SetTargetFPS(60)
	round := Round {
		gifts   = make([dynamic]Gift, 0),
		chosen  = make([dynamic]Gift, 0),
		ignored = make([dynamic]Gift, 0),
	}

	top_pipe := TopPipe {
		current_frame = 0,
		current_time  = 0,
		frame_time    = 0.05,
		total_frames  = 7,
	}
	gm := GameManager {
		round                        = round,
		round_number                 = 0,
		spawn_interval               = 1.8,
		initial_spawn_interval       = 1.8,
		max_fall_speed               = 650,
		fall_speed_incr              = 7,
		initial_fall_speed_incr      = 7,
		fall_speed_growth_factor     = 1.1,
		spawn_interval_growth_factor = 0.8,
		lifes                        = 5,
		game_state                   = .initial_screen,
		font                         = rl.LoadFont("./assets/ThaleahFat.ttf"),
		top_pipe                     = top_pipe,
	}
	init_gift_template(&gm)
	load_assets(&gm)
	camera := rl.Camera2D {
		zoom   = 1,
		offset = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
		target = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
	}
	gm.camera = GameCamera {
		camera      = &camera,
		intensity   = 1.5,
		shake_timer = 0,
	}

	// Definir valores uniformes
	for !rl.WindowShouldClose() {
		gm.dt = rl.GetFrameTime()
		gm.screen_height = f32(rl.GetScreenHeight())
		gm.screen_width = f32(rl.GetScreenWidth())
		update_game(&gm)
		update_particles(&gm)
		update_camera(&gm)
		rl.BeginDrawing()
		rl.ClearBackground({109, 58, 39, 255})
		rl.BeginMode2D(camera)
		rl.DrawTextureEx(gm.assets["background"], {0, 0}, 0, 1, rl.WHITE)
		if gm.game_state == .show_round_result {
			draw_result(&gm)
		}
		if gm.game_state == .on_round {
			gift_draw(&gm)
			particles_draw(&gm)
		}
		ui_draw(&gm)
		draw_fade(&gm)
		draw_top_pipe(&gm)
		draw_initial_screen(&gm)
		rl.EndMode2D()
		rl.EndDrawing()
	}

	delete(gm.round.gifts)
	delete(gm.round.chosen)
	delete(gm.round.ignored)
	delete(gm.gift_templates.gifts)
	delete(gm.round.particles)
	rl.CloseWindow()
}
