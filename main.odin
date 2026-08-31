package main

import "core:fmt"
import "core:strings"
import "core:math/linalg"
import "core:math/rand"
import "core:math"
import rl "vendor:raylib"

LANE1 :: rl.Vector2{0, 416}
LANE2 :: rl.Vector2{0, 480}
LANE3 :: rl.Vector2{0, 544}
LANE4 :: rl.Vector2{0, 608}
WATER_LANE1 :: rl.Vector2{0, 96}
WATER_LANE2 :: rl.Vector2{0, 160}
WATER_LANE3 :: rl.Vector2{0, 224}
WATER_LANE4 :: rl.Vector2{0, 288}

O_SIZE :: rl.Vector2{64, 64}

Window :: struct {
	name:          cstring,
	width:         i32,
	height:        i32,
}

Cell :: struct {
	x, y:    i32,
	width:   i32,
	height:  i32,
	texture: rl.Texture2D
}

G_state :: enum{open, closed}
//Getting into goal will reward a base amount of points
//Goal can have a bonus inside of it
Goal :: struct {
	pos:         rl.Vector2,
	size:        rl.Vector2,
	state:       G_state,
	has_bonus:   bool,
	cell:        ^Cell
}
bonus_timer: f32 = 0

//change types to player, enemy, float
//and add subtypes of slow and fast or none
E_type :: enum{none, player, car, float}
E_state :: enum{idle, moving, dead}

Entity :: struct {
	type:     E_type,
	state:    E_state,
	pos:      rl.Vector2,
	size:     rl.Vector2,
	rotation: f32,
	velocity: rl.Vector2,
}

target_pos: rl.Vector2 // for player movement
entities: [41]Entity
player: ^Entity

Points_Table :: struct{
	round_points: u32,
	bonus_multiplier: u32
}

tables: [5]Points_Table = {
	{1000, 5},
	{2000, 6},
	{3000, 8},
	{5000, 10},
	{10000, 10}
}

GAME_STATE :: enum{alive, gameover, menu, quit}
Game :: struct {
	points:       u32,
	lives:        u8,
	time:         f32,
	state:        GAME_STATE,
	goals:        [6]Goal,
	closed_goals: u8,
	points_table: Points_Table,
	round: u32,
}
game: Game

water_collision_box: rl.Rectangle = {0, 64, 1280, 256}
grass_collision_boxes: [7]rl.Rectangle = {
	{0, 0, 128, 64},
	{192, 0, 128, 64},
	{384, 0, 128, 64},
	{576, 0, 128, 64},
	{768, 0, 128, 64},
	{960, 0, 128, 64},
	{1152, 0, 128, 64}
}

DEBUG_STATE :: enum{
	none,
	bonus_time,
	position,
	hitbox,
	goal_state,
	closed_goals,
	size,
}
debug_state: DEBUG_STATE = .none

debug_draw_hitboxes :: proc()
{
	hitbox: rl.Rectangle
	for entity, index in entities{
		hitbox = {entity.pos.x - 32, entity.pos.y - 32, entity.size.x, entity.size.y}
		if entity.type == .player{
			hitbox = {player.pos.x - 32.0 + 21.0, player.pos.y - 32.0 + 10.0, 23.0, 40.0}
		}
		rl.DrawRectangleLinesEx(hitbox, 1, rl.WHITE)
	}
}

debug :: proc()
{
	switch debug_state{
	case .none:
		break
	case .bonus_time:
		rl.DrawText(fmt.ctprintf("bonus time: %0.f", bonus_timer), 300, 720, 32, rl.WHITE)
	case .position:
		rl.DrawText(fmt.ctprintf("pos: %0.f %0.f", player.pos.x-32, player.pos.y-32), 300, 720, 32, rl.WHITE)
	case .hitbox:
		debug_draw_hitboxes()
	case .goal_state:
		rl.DrawText(fmt.ctprintf("goal state: "), 300, 720, 32, rl.WHITE)
	case .closed_goals:
		rl.DrawText(fmt.ctprintf("closed goals: %d", game.closed_goals), 300, 720, 32, rl.WHITE)
	case .size:
		break
	}
}

create_entities :: proc()
{
	car_num: i32 = 0
	for &entity, i in entities{
		switch i{
		case 0:
			entity = {.player, .idle,  {672, 672},                                O_SIZE,   0, rl.Vector2(0)}
			car_num = 0
		case 1..<6:
			entity = {.car,   .moving, {128 + f32(car_num * 256), LANE4.y},       O_SIZE,  90, rl.Vector2{150, 0}}
		case 6..<11:
			entity = {.car,   .moving, {128 + f32(car_num * 256), LANE3.y},       O_SIZE, -90, rl.Vector2{-250, 0}}
		case 11..<16:
			entity = {.car,   .moving, {128 + f32(car_num * 256), LANE2.y},       O_SIZE,  90, rl.Vector2{350, 0}}
		case 16..<21:
			entity = {.car,   .moving, {128 + f32(car_num * 256), LANE1.y},       O_SIZE, -90, rl.Vector2{-400, 0}}
		case 21..<26:
			entity = {.float, .moving, {128 + f32(car_num * 256), WATER_LANE4.y}, O_SIZE,  90, rl.Vector2{50, 0}}
		case 26..<31:
			entity = {.float, .moving, {128 + f32(car_num * 256), WATER_LANE3.y}, O_SIZE, -90, rl.Vector2{-100, 0}}
		case 31..<36:
			entity = {.float, .moving, {128 + f32(car_num * 256), WATER_LANE2.y}, O_SIZE,  90, rl.Vector2{125, 0}}
		case 36..<41:
			entity = {.float, .moving, {128 + f32(car_num * 256), WATER_LANE1.y}, O_SIZE, -90, rl.Vector2{-200, 0}}
		}
		car_num += 1
		if(car_num > 4) do car_num = 0
	}
}

update :: proc()
{
	for &entity in entities{
		if entity.type == .player do continue

		entity.pos.x += entity.velocity.x * rl.GetFrameTime()

		if entity.velocity.x > 0 && entity.pos.x > 1312 {
			entity.pos.x = -64
		}
		if entity.velocity.x < 0 && entity.pos.x < -32 {
			entity.pos.x = 1344
		}
	}

	if bonus_timer == 0{
		bonus_timer = game.time - 4
	}
	if bonus_timer >= game.time{
		prev_choice: i32
		closed_goals: [6]b8
		closed_sum: u8 = 0
		for &goal, i in game.goals{
			if goal.state == .closed{
				closed_goals[i] = true
				closed_sum += 1
			}
			if goal.has_bonus{
				prev_choice = i32(i)
			}
			goal.has_bonus = false
		}
		if closed_sum != 6 {
			bonus_timer = game.time - 4
			// All of this is bit weird maybe rewrite
			rand_num := rand.int32_range(0, 6)
			for rand_num == prev_choice || game.goals[rand_num].state == .closed{
				rand_num = rand.int32_range(0, 6)
				if closed_sum == 5{
					for g, i in closed_goals{
						if !g {
							rand_num = i32(i)
						}
					}
					break
				}
			}
			chosen_goal := &game.goals[rand_num]
			chosen_goal.has_bonus = true
		}
	}

}

respawn :: proc()
{
	player.pos = {672, 672}
	player.state = .idle
}

next_round :: proc()
{
	game.round += 1
	game.lives += 2
	game.time += 100
	game.closed_goals = 0
	bonus_timer = game.time - 4
	for &goal in game.goals{
		goal.state = .open
	}
	game.points_table = tables[clamp(game.round, 0, 4)]
}

input :: proc()
{
	if player.state == .idle{
		if rl.IsKeyPressed(.UP){
			target_pos.y = player.pos.y - 64
			target_pos.x = player.pos.x
			player.state = .moving
			player.rotation = 0
		}
		if rl.IsKeyPressed(.DOWN){
			target_pos.y = player.pos.y + 64
			target_pos.x = player.pos.x
			player.state = .moving
			player.rotation = 180
		}
		if rl.IsKeyPressed(.LEFT){
			target_pos.y = player.pos.y
			target_pos.x = player.pos.x - 64
			player.state = .moving
			player.rotation = -90
		}
		if rl.IsKeyPressed(.RIGHT){
			target_pos.y = player.pos.y
			target_pos.x = player.pos.x + 64
			player.state = .moving
			player.rotation = 90
		}
	}

	if rl.IsKeyPressed(.F3){
		for goal in game.goals{
			fmt.println(goal.has_bonus)
		}
	}
	if rl.IsKeyPressed(.F4){
		debug_state = DEBUG_STATE(int(debug_state) + 1)
		if debug_state > .size{
			debug_state = .none
		}
	}
}

physics :: proc()
{

	//Player boundary check
	if target_pos.x > 1280 || target_pos.x < 0{
		target_pos.x = player.pos.x
		player.state = .idle
	}
	if target_pos.y > 704 || target_pos.y < 0{
		target_pos.y = player.pos.y
		player.state = .idle
	}

	// player movement
	// The state is sometimes not set to idle when jumping from floating object.
	// I believe this is because the jump does not get close enough to the target position
	// That being said setting the magnetic effect too large will lead to janky looking movement
	if (player.state == .moving) && (player.state != .dead){
		//t := 1.0 - math.pow_f32(0.001, 2 * dt)
		player.pos = linalg.lerp(player.pos, target_pos, 0.7)

		if abs(player.pos.y - target_pos.y) < 1 && abs(player.pos.x - target_pos.x) < 1{
			player.pos = target_pos
			player.state = .idle
		}
	}

	//car collision
	player_collision_box := rl.Rectangle{f32(player.pos.x - 32 + 21), f32(player.pos.y - 32 + 10), 23, 40}
	enemy_collision_box: rl.Rectangle
	for enemy, i in entities{
		if enemy.type == .float do continue
		if enemy.type == .player do continue
		enemy_collision_box = {enemy.pos.x - 32, enemy.pos.y - 32, 64, 64}
		if rl.CheckCollisionRecs(player_collision_box, enemy_collision_box){
			player.state = .dead
			game.lives -= 1
		}
	}

	// not sure if all of these should be under this check
	if(player.state != .moving){
		//check if player is on floating object
		can_drown := true
		float_collision_box: rl.Rectangle
		for entity in entities {
			if entity.type != .float do continue
			float_collision_box = {entity.pos.x - 32, entity.pos.y - 32, 64, 64}
			if rl.CheckCollisionRecs(player_collision_box, float_collision_box){
				can_drown = false
				player.pos += entity.velocity * rl.GetFrameTime()
				//check player boundary while moving on floating object
				if player.pos.x > 1280 || player.pos.x < 0{
					player.state = .dead
					game.lives -= 1
				}
				if player.pos.y > 704 || player.pos.y < 0{
					player.state = .dead
					game.lives -= 1
				}
			}
		}

		//Water death check
		if rl.CheckCollisionRecs(player_collision_box, water_collision_box){
			if can_drown{
				player.state = .dead
				game.lives -= 1
			}
		}

		//Missed goal death check
		for grass in grass_collision_boxes{
			if rl.CheckCollisionRecs(player_collision_box, grass){
				player.state = .dead
				game.lives -= 1
			}
		}

		//Goal collision check
		goal_collision_box: rl.Rectangle
		for &goal in game.goals{
			goal_collision_box = {goal.pos.x - 32, goal.pos.y - 32, 64, 64}
			if rl.CheckCollisionRecs(player_collision_box, goal_collision_box){
				if goal.state == .open{
					goal.state = .closed
					game.closed_goals += 1
					if goal.has_bonus{
						game.points += game.points_table.round_points * game.points_table.bonus_multiplier
					}
					else{
						game.points += game.points_table.round_points
					}
					goal.has_bonus = false
					respawn()
				}
			}
		}
	}
}

MENU_OPTIONS :: enum{play, highscore, quit}
NUM_OPTIONS :: 2
Main_Menu :: struct{
	menu_strings: [NUM_OPTIONS]cstring,
	menu_recs: [NUM_OPTIONS]rl.Rectangle,
	font_size: i32,
	title: cstring,
	mouse_hover: int
}
main_menu: Main_Menu

init_main_menu :: proc(window: Window)
{
	item_width:  f32 = 150.0
	item_height: f32 = 30.0
	main_menu.font_size = 16
	main_menu.title = "Frogger"
	main_menu.mouse_hover = -1
	main_menu.menu_strings = {"Play", "Quit"}
	for &rec, index in main_menu.menu_recs{
		rec = {
			f32(window.width) / 2 - item_width / 2,
			f32(200 + 34 * index),
			item_width,
			item_height
		}
	}
}

draw_main_menu :: proc(window: Window)
{
	for menu_item, index in main_menu.menu_recs{
		if(rl.CheckCollisionPointRec(rl.GetMousePosition(), menu_item)){
			main_menu.mouse_hover = index
			if(rl.IsMouseButtonPressed(.LEFT)){
				switch main_menu.mouse_hover{
				case 0:
					game.state = .alive
				case 1:
					game.state = .quit
				}
			}
			break
		}
		else do main_menu.mouse_hover = -1
	}

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.DrawText(main_menu.title, i32(f32(window.width)/2 - f32(rl.MeasureText(main_menu.title, 64)/2)), 16, 64, rl.GREEN)

	for menu_item, index in main_menu.menu_recs{
		item_text := main_menu.menu_strings[index]
		rl.DrawRectangleRec(menu_item, (index == main_menu.mouse_hover) ? rl.GREEN : rl.WHITE)
		rl.DrawText(item_text, i32(menu_item.x + menu_item.width / 2 - f32(rl.MeasureText(item_text, main_menu.font_size)/2)), i32(menu_item.y + 8), main_menu.font_size, rl.BLACK)
	}
	rl.EndDrawing()
}

game_reset :: proc()
{
	game.points = 0
	game.lives = 3
	game.time = 300.0
	game.closed_goals = 0
	game.points_table = tables[0]
	game.round = 0
	for &goal in game.goals{
		goal.state = .open
	}
}

main :: proc()
{
	window := Window{"Odin Frogger", 1280, 768}
	rl.InitWindow(window.width, window.height, window.name);
	rl.SetTargetFPS(60)

	game_reset()
	game.state = .menu

	cells: [220]Cell

	green_tex := rl.LoadTexture("green.png")
	defer rl.UnloadTexture(green_tex)

	gray_tex := rl.LoadTexture("gray.png")
	defer rl.UnloadTexture(gray_tex)

	dgray_tex := rl.LoadTexture("dgray.png")
	defer rl.UnloadTexture(dgray_tex)

	dgray_nl_tex := rl.LoadTexture("dgray_noline.png")
	defer rl.UnloadTexture(dgray_nl_tex)

	blue_tex := rl.LoadTexture("blue.png")
	defer rl.UnloadTexture(blue_tex)

	lily_tex := rl.LoadTexture("lily.png")
	defer rl.UnloadTexture(lily_tex)

	closed_tex := rl.LoadTexture("lily_closed.png")
	defer rl.UnloadTexture(closed_tex)

	frog_tex := rl.LoadTexture("frog.png")
	defer rl.UnloadTexture(frog_tex)

	redcar_tex := rl.LoadTexture("redcar.png")
	defer rl.UnloadTexture(redcar_tex)

	float_tex := rl.LoadTexture("float.png")
	defer rl.UnloadTexture(float_tex)

	bonus_tex := rl.LoadTexture("bonus.png")
	defer rl.UnloadTexture(bonus_tex)


	frog_tex_width: f32 = f32(frog_tex.width)
	frog_tex_height: f32 = f32(frog_tex.height)

	source_rec: rl.Rectangle = {0.0, 0.0, frog_tex_width, frog_tex_height}
	origin: rl.Vector2 = {frog_tex_width / 2, frog_tex_height / 2}

	goal_index := 0
	for &cell, index in cells {

		cell.width = 64
		cell.height = cell.width
		cell.x = cell.width * i32(index % 20)
		cell.y = cell.width * i32(index / 20)

		row := cell.y / cell.width
		col := i32(index) % 20

		switch row {
		case 0:
			if col == 2 || col == 5 || col == 8 || col == 11 || col == 14 || col == 17 {
				cell.texture = lily_tex
				game.goals[goal_index] = {
					pos         = {f32(cell.x), f32(cell.y)},
					size        = {64, 64},
					state       = .open,
					has_bonus   = false,
					cell        = &cell
				}
				goal_index += 1
			} else {
				cell.texture = green_tex
			}
		case 10, 5:
			cell.texture = gray_tex
		case 6:
			cell.texture = dgray_nl_tex
		case 7..=9:
			cell.texture = dgray_tex
		case 1..=4:
			cell.texture = blue_tex
		}
	}

	//create entities
	create_entities()
	//initialize main menu
	init_main_menu(window)
	player = &entities[0]

	saved_time := rl.GetTime()

	//main game loop
	for game.state != .quit {

		if rl.WindowShouldClose(){
			game.state = .quit
		}

		if game.state == .gameover{
			for game.state == .gameover{

				if rl.IsKeyPressed(.ENTER){
					game.state = .menu
				}
				if rl.WindowShouldClose(){
					game.state = .quit
				}

				rl.BeginDrawing()
				rl.ClearBackground(rl.BLACK)

				rl.DrawText("Game Over", i32(f32(window.width)/2 - f32(rl.MeasureText("Game Over", 64)/2)), 16, 64, rl.RED)
				rl.DrawText("Score", i32(f32(window.width)/2 - f32(rl.MeasureText("Score", 32)/2)), 128, 32, rl.WHITE)
				rl.DrawText(fmt.ctprintf("%08d", game.points), i32(f32(window.width)/2 - f32(rl.MeasureText(fmt.ctprintf("%08d", game.points), 32)/2)), 192, 32, rl.WHITE)
				rl.DrawText("Press ENTER to continue", i32(f32(window.width)/2 - f32(rl.MeasureText("Press ENTER to continue", 16)/2)), 512, 16, rl.WHITE)
				rl.DrawText("Press ESCAPE to quit", i32(f32(window.width)/2 - f32(rl.MeasureText("Press ESCAPE to quit", 16)/2)), 544, 16, rl.WHITE)

				rl.EndDrawing()
			}
			game_reset()
		}

		if game.state == .menu{
			draw_main_menu(window)
			continue
		}

		dt: f32 = rl.GetFrameTime()

		current_time := rl.GetTime()
		if (current_time - saved_time) >= 1{
			saved_time = current_time
			game.time -= 1
		}
		if(game.time <= 0){
			game.state = .gameover
		}

		if player.state == .dead{
			respawn()
		}
		if game.lives == 0{
			game.state = .gameover
		}

		if game.closed_goals == 6{
			next_round()
		}

		update()
		input()
		physics()

		dest_rec: rl.Rectangle = {f32(player.pos.x), f32(player.pos.y), frog_tex_width, frog_tex_height}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		for cell in cells {
			rl.DrawTexture(cell.texture, cell.x, cell.y, rl.WHITE)
		}

		for &goal in game.goals{
			if goal.state == .closed{
				goal.cell.texture = closed_tex
			}
			if goal.state == .open{
				goal.cell.texture = lily_tex
			}
			if goal.has_bonus{
				offset := rl.Vector2{0, 10}
				rl.DrawTextureV(bonus_tex, goal.pos + offset, rl.WHITE)
			}
		}

		rl.DrawText(fmt.ctprintf("lives: %d", game.lives), 16, 720, 32, rl.WHITE)
		rl.DrawText(fmt.ctprintf("%08d", game.points), 600, 720, 32, rl.WHITE)
		rl.DrawText(fmt.ctprintf("time: %0.f", game.time), 1000, 720, 32, rl.WHITE)
		debug()

		//can be strealined to just go through the whole entity array
		for entity, i in entities{
			if entity.type == .none do continue
			if entity.type == .player do continue
			if entity.type == .car{
				rl.DrawTexturePro(redcar_tex, rl.Rectangle{0, 0, 64, 64}, {entity.pos.x, entity.pos.y, 64, 64}, rl.Vector2{32, 32}, entity.rotation, rl.WHITE)
			}
			if entity.type == .float{
				rl.DrawTexturePro(float_tex, rl.Rectangle{0, 0, 64, 64}, {entity.pos.x, entity.pos.y, 64, 64}, rl.Vector2{32, 32}, entity.rotation, rl.WHITE)
			}
		}
		rl.DrawTexturePro(frog_tex, source_rec, dest_rec, origin, player.rotation, rl.WHITE)

//		player_topleft := player.pos - 32
		//		rl.DrawRectangleLinesEx({player_topleft.x, player_topleft.y, player.size.x, player.size.y }, 1, rl.WHITE)
		grass_rect: rl.Rectangle
		// for grass in grass_collision_boxes{
		// 	grass_rect = {grass.x, grass.y, grass.width, grass.height}
		// 	rl.DrawRectangleLinesEx(grass_rect, 1, rl.WHITE)
		// }

		rl.EndDrawing()
	}
	rl.CloseWindow()
	return
}
