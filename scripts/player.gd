extends CharacterBody3D

# --- PERFIL DEL PERSONAJE ---
@export var profile: CharacterProfile

# --- ESTADÍSTICAS BASE ---
@export var speed_base = 2.5
@export var speed_run = 5.0
@export var crouch_speed = 1.5
@export var mouse_sensitivity: float = 0.002

# --- DASH ---
@export var dash_speed = 25.0
@export var dash_duration = 0.2
@export var dash_cooldown_max = 1.0
@export var double_tap_window = 0.3

# --- SALTO PROTOTYPE ---
@export var jump_base_force = 2.0
@export var air_control = 0.3
@export var long_jump_boost = 5.0
@export var bunny_hop_boost = 2.0
@export var push_force = 1.0

# --- BUNNY HOP SYSTEM (UT99 Style) ---
@export var bhop_enabled: bool = true
@export var bhop_window_perfect: float = 0.12   # Timing perfecto al aterrizar
@export var bhop_window_good: float = 0.22      # Timing aceptable
@export var bhop_speed_increment: float = 1.5   # Cuánto suma cada hop exitoso
@export var bhop_max_speed: float = 18.0        # Velocidad tope (evita volverse loco)
@export var bhop_stamina_cost: float = 12.0     # Stamina consumida por hop
@export var bhop_momentum_decay: float = 4.0    # Pérdida de velocidad extra por segundo en suelo
@export var bhop_min_chain_for_boost: int = 2   # Saltos seguidos necesarios para sentir el boost

# --- STAMINA ---
@export var max_stamina: float = 100.0
@export var stamina_recover_rate: float = 8.0   # Por segundo
@export var stamina_recover_delay: float = 1.0  # Segundos tras dejar de gastar

# --- NODOS ---
@onready var collision_shape = $CollisionShape3D
@onready var visuals = $visuals
@onready var camera_mount = $camera_mount

# --- VARIABLES DE ESTADO ---
var is_crouching = false
var default_height = 2.0
var crouch_height = 1.0

var dash_timer = 0.0
var dash_cooldown = 0.0
var last_sprint_tap = 0.0
var is_dashing = false

# Salto Prototype
var jump_charge = 0.0
var max_jump_charge = 1.0
var is_charging = false
var jump_cooldown = 0.0

# Bunny Hop
var bhop_speed_bonus: float = 0.0           # Velocidad extra acumulada
var bhop_chain_count: int = 0               # Cuántos hops llevamos seguidos
var time_since_landed: float = 0.0          # Cronómetro desde que tocamos suelo
var was_in_air: bool = false                # Para detectar aterrizaje
var bhop_window_active: bool = false        # Estamos en la ventana de timing
var last_bhop_time: float = 0.0             # Para evitar spam

# Stamina
var stamina: float = 100.0
var stamina_recover_timer: float = 0.0

# Crouch Jump
var is_crouch_jumping = false
var wants_uncrouch = false
@export var crouch_jump_boost = 2.5
@export var uncrouch_check_distance = 2.1

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	default_height = collision_shape.shape.height
	
	# DEBUG: Ver qué valores tiene REALMENTE al iniciar
	print("=== VALORES INICIALES ===")
	print("speed_base (script): ", speed_base)
	print("speed_run (script): ", speed_run)
	print("crouch_speed: ", crouch_speed)
	print("=========================")
	
	if profile:
		speed_base = profile.walk_speed
		print("PROFILE ACTIVO: walk_speed = ", profile.walk_speed)
		max_stamina = profile.max_stamina if "max_stamina" in profile else 100.0
		stamina = max_stamina

func _input(event):
	# --- CÁMARA ---
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_mount.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -1.2, 1.2)
	
	# --- DASH (doble Shift) ---
	if event.is_action_pressed("sprint"):
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if current_time - last_sprint_tap < double_tap_window and dash_cooldown <= 0:
			if is_on_floor():
				start_dash()
		
		last_sprint_tap = current_time
	
	# --- CROUCH ---
	if event.is_action_pressed("crouch"):
		is_crouching = true
		apply_crouch(true)
	elif event.is_action_released("crouch"):
		if can_uncrouch():
			is_crouching = false
			apply_crouch(false)
		else:
			wants_uncrouch = true
	
	# --- SALTO / BUNNY HOP ---
	if event.is_action_pressed("jump"):
		try_bunny_hop()

func start_dash():
	# Guarda: si no estamos en el suelo, no hacemos nada
	if not is_on_floor():
		return
	
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown = dash_cooldown_max
	
	# Romper bunny hop al dashear
	bhop_speed_bonus = 0.0
	bhop_chain_count = 0
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dir == Vector3.ZERO:
		dir = -transform.basis.z
	
	velocity.x = dir.x * dash_speed
	velocity.z = dir.z * dash_speed
	velocity.y = 0  # Dash puramente horizontal en el suelo

func _physics_process(delta):
	# Timers
	if dash_timer > 0: dash_timer -= delta
	else: is_dashing = false
	if dash_cooldown > 0: dash_cooldown -= delta
	if jump_cooldown > 0: jump_cooldown -= delta
	
	# Stamina recovery
	if stamina_recover_timer > 0:
		stamina_recover_timer -= delta
	else:
		stamina = min(stamina + stamina_recover_rate * delta, max_stamina)
	
	# Gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Detectar aterrizaje para ventana de Bunny Hop
	handle_landing_detection(delta)
	
	# Si queríamos levantarnos y ahora hay espacio
	if wants_uncrouch and is_crouching and can_uncrouch():
		is_crouching = false
		wants_uncrouch = false
		apply_crouch(false)
		if not is_on_floor() and is_crouch_jumping:
			velocity.y += crouch_jump_boost
			is_crouch_jumping = false
	
	# Estados y movimiento
	handle_states(delta)
	handle_jump_charge(delta)
	# handle_movement_logic(delta)
	if not is_dashing:
		handle_movement_logic(delta)
	
	# Físicas
	move_and_slide()
	handle_box_pushing()
	handle_landing_effects()

# =============================================================================
# BUNNY HOP SYSTEM
# =============================================================================

func handle_landing_detection(delta):
	# Detectar transición AIRE → SUELO
	var is_in_air = not is_on_floor()
	
	if was_in_air and not is_in_air:
		# Acabamos de aterrizar → Abrir ventana de Bunny Hop
		time_since_landed = 0.0
		bhop_window_active = true
	
	if is_on_floor():
		time_since_landed += delta
		
		# La ventana se cierra después del timing "good"
		if time_since_landed > bhop_window_good:
			bhop_window_active = false
			
			# Si estamos en el suelo y no hacemos bhop, perdemos momentum
			if bhop_speed_bonus > 0:
				bhop_speed_bonus = move_toward(bhop_speed_bonus, 0.0, bhop_momentum_decay * delta)
				if bhop_speed_bonus < 0.5:
					bhop_speed_bonus = 0.0
					bhop_chain_count = 0
	
	was_in_air = is_in_air

func try_bunny_hop():
	# Bunny Hop requiere: Shift presionado + timing correcto + stamina + no agachado
	var is_sprint_held = Input.is_action_pressed("sprint")
	
	if not bhop_enabled or is_crouching or not is_sprint_held:
		# No intentamos bhop, salto normal/carga
		handle_normal_jump_start()
		return
	
	if stamina < bhop_stamina_cost:
		# Sin stamina: salto normal sin boost
		handle_normal_jump_start()
		return
	
	# Evaluar timing
	var timing = get_bhop_timing()
	
	if timing == "perfect" or timing == "good":
		# ¡BUNNY HOP EXITOSO!
		execute_bunny_hop(timing)
	else:
		# Timing fallido: salto normal, rompemos cadena
		bhop_speed_bonus = 0.0
		bhop_chain_count = 0
		handle_normal_jump_start()

func get_bhop_timing() -> String:
	if not bhop_window_active:
		return "miss"
	if time_since_landed <= bhop_window_perfect:
		return "perfect"
	if time_since_landed <= bhop_window_good:
		return "good"
	return "miss"

func execute_bunny_hop(timing: String):
	# Consumir stamina
	stamina -= bhop_stamina_cost
	stamina_recover_timer = stamina_recover_delay
	
	# La cadena SIEMPRE sube si el timing fue bueno
	bhop_chain_count += 1
	
	# --- BONUS DE VELOCIDAD: solo hacia adelante ---
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward_amount = -input_dir.y
	
	var boost = bhop_speed_increment
	if timing == "perfect":
		boost *= 1.5
	
	var bonus_to_add = 0.0
	var had_bonus_before = bhop_speed_bonus > 0  # Guardamos si teníamos bonus antes
	
	if forward_amount > 0.7:
		bonus_to_add = boost
	elif forward_amount > 0.3:
		bonus_to_add = boost * 0.4
	else:
		# Lateral o atrás: resetear bonus
		bonus_to_add = 0.0
		bhop_speed_bonus = 0.0
	
	if bonus_to_add > 0:
		bhop_speed_bonus = min(bhop_speed_bonus + bonus_to_add, bhop_max_speed - speed_base)
	
	# --- DIRECCIÓN DEL SALTO ---
	var move_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if move_dir == Vector3.ZERO:
		move_dir = -transform.basis.z
	
	var target_speed = speed_base
	if forward_amount > 0.3:
		target_speed += bhop_speed_bonus
	
	velocity.x = move_dir.x * target_speed
	velocity.z = move_dir.z * target_speed
	velocity.y = jump_base_force * 0.85
	
	# --- FEEDBACK: solo si hay bonus real ---
	# Si acumulamos bonus nuevo O ya teníamos bonus y seguimos yendo adelante/diagonal
	if bonus_to_add > 0 or (had_bonus_before and forward_amount > 0.3):
		play_bhop_feedback(timing)
	
	is_crouch_jumping = false

func play_bhop_feedback(timing: String):
	var cam = $camera_mount/Camera3D
	
	if timing == "perfect" and cam != null:
		var fov_tween = create_tween()
		fov_tween.tween_property(cam, "fov", 85 + (bhop_chain_count * 2), 0.1)
		fov_tween.tween_property(cam, "fov", 75, 0.3)
	
	if camera_mount != null:
		var cam_bump = create_tween()
		var start_y = camera_mount.position.y
		var target_y = 1.5 if not is_crouching else 0.8
		
		cam_bump.tween_property(camera_mount, "position:y", start_y - 0.1, 0.05)
		cam_bump.tween_property(camera_mount, "position:y", target_y, 0.1)  # ← DESCOMENTA ESTA

# =============================================================================
# SALTO NORMAL / CARGA (Prototype)
# =============================================================================

func handle_normal_jump_start():
	# Si estamos en el suelo, iniciar carga (Prototype)
	if is_on_floor():
		if is_crouching:
			# Crouch Jump: saltar agachado
			is_crouch_jumping = true
			velocity.y = jump_base_force * 0.9
			return
		
		is_charging = true
		jump_charge = 0.0
		# Visual: agacharse al cargar
		var charge_tween = create_tween()
		charge_tween.tween_property(visuals, "position:y", -0.15, 0.1)

func handle_jump_charge(delta):
	if not is_charging:
		return
	
	if is_on_floor() and Input.is_action_pressed("jump"):
		jump_charge += delta * 1.5
		jump_charge = min(jump_charge, max_jump_charge)
	elif Input.is_action_just_released("jump") and is_charging:
		release_jump_charge()
	else:
		# Si se cancela (ej: caída, stun)
		is_charging = false
		jump_charge = 0.0
		var reset_tween = create_tween()
		reset_tween.tween_property(visuals, "position:y", 0.0, 0.1)

func release_jump_charge():
	is_charging = false
	var charge_ratio = jump_charge / max_jump_charge
	
	# Calcular fuerza
	var force = jump_base_force + (charge_ratio * 3.0)
	
	# Long jump (si el perfil lo permite)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_moving_forward = input_dir.y < -0.5
	
	if profile and profile.can_long_jump and is_moving_forward and charge_ratio > 0.5:
		var horizontal = profile.long_jump_force * charge_ratio
		var h_vel = Vector3(velocity.x, 0, velocity.z)
		h_vel += -transform.basis.z * horizontal
		h_vel = h_vel.limit_length(speed_base * 2.5)
		velocity.x = h_vel.x
		velocity.z = h_vel.z
		velocity.y = force * 0.6
	else:
		velocity.y = force
	
	jump_charge = 0.0
	var reset_tween = create_tween()
	reset_tween.tween_property(visuals, "position:y", 0.0, 0.1)

# =============================================================================
# MOVIMIENTO
# =============================================================================

func handle_states(delta):
	# Sprint "clásico" solo si no estamos en bunny hop
	# (El bhop reemplaza al sprint normal)
	if bhop_speed_bonus <= 0 and not is_crouching:
		# Sprint simple manteniendo Shift + adelante (para movimiento base)
		pass  # Opcional: mantener sprint clásico para no-bhop

func handle_movement_logic(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var forward_amount = -input_dir.y
	
	# --- PENALIZACIÓN DE BONUS BHOP ---
	if bhop_speed_bonus > 0:
		if forward_amount < -0.2:
			bhop_speed_bonus = move_toward(bhop_speed_bonus, 0.0, bhop_momentum_decay * delta * 5.0)
			if bhop_speed_bonus < 0.5:
				bhop_speed_bonus = 0.0
		elif forward_amount < 0.3:
			bhop_speed_bonus = move_toward(bhop_speed_bonus, 0.0, bhop_momentum_decay * delta * 5.0)
			if bhop_speed_bonus < 0.5:
				bhop_speed_bonus = 0.0
		elif forward_amount < 0.7:
			var target_bonus = bhop_speed_bonus * 0.6
			bhop_speed_bonus = move_toward(bhop_speed_bonus, target_bonus, bhop_momentum_decay * delta * 2.0)
	
	# --- BHOP EN EL AIRE ---
	if bhop_speed_bonus > 0 and not is_on_floor():
		var target_speed = speed_base
		if forward_amount > 0.3:
			target_speed += bhop_speed_bonus
		
		if direction != Vector3.ZERO:
			velocity.x = direction.x * target_speed
			velocity.z = direction.z * target_speed
		else:
			velocity.x = move_toward(velocity.x, 0, bhop_momentum_decay * delta)
			velocity.z = move_toward(velocity.z, 0, bhop_momentum_decay * delta)
		return
	
	# --- MOVIMIENTO EN EL SUELO ---
	var current_speed = speed_base
	
	if is_crouching:
		current_speed = crouch_speed
	elif Input.is_action_pressed("sprint") and is_on_floor():
		current_speed = speed_run
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed * 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0, current_speed * 2.0 * delta)
	else:
		# Air control normal
		if direction:
			velocity.x = lerp(velocity.x, direction.x * current_speed, air_control * delta * 5.0)
			velocity.z = lerp(velocity.z, direction.z * current_speed, air_control * delta * 5.0)

# =============================================================================
# CROUCH & CROUCH JUMP
# =============================================================================

func apply_crouch(crouched: bool):
	var target_height = crouch_height if crouched else default_height
	var target_pos = 0.5 if crouched else 1.0
	var cam_y = 0.8 if crouched else 1.5
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.tween_property(collision_shape.shape, "height", target_height, 0.1)
	tween.tween_property(collision_shape, "position:y", target_pos, 0.1)
	tween.tween_property(camera_mount, "position:y", cam_y, 0.1)

func can_uncrouch() -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = global_position
	query.to = global_position + Vector3.UP * uncrouch_check_distance
	query.exclude = [self]
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	return result.is_empty()

# =============================================================================
# FÍSICAS & EFECTOS
# =============================================================================

func handle_box_pushing():
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is RigidBody3D:
			# 1. Solo empujar con velocidad horizontal (ignorar caídas verticales)
			var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
			var speed = horizontal_vel.length()
			
			# 2. Si no hay movimiento horizontal, no empujar
			if speed < 0.5:
				continue
			
			# 3. Dirección del empuje: la normal de la colisión
			var direction = -collision.get_normal()
			
			# 4. Factor de masa: cajas ligeras reciben menos impulso bruto
			# (evita que una caja de 1kg se vaya al infinito)
			var mass = collider.mass
			var mass_factor = clamp(mass / 10.0, 0.2, 3.0)  # Entre 0.2 y 3.0
			
			# 5. Calcular impulso con límite máximo
			var raw_impulse = direction * push_force * speed * mass_factor
			var max_impulse = 8.0  # Límite máximo de fuerza
			var impulse = raw_impulse.limit_length(max_impulse)
			
			# 6. Punto de aplicación: ligeramente arriba del centro para que no se atasque
			var push_point = collider.global_position + Vector3.UP * 0.3
			
			collider.apply_impulse(impulse, push_point - collider.global_position)

func handle_landing_effects():
	# Efectos de aterrizaje (cámara, partículas)
	pass

func get_horizontal_speed() -> float:
	return Vector3(velocity.x, 0, velocity.z).length()
