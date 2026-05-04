extends CharacterBody3D

# --- ESTADÍSTICAS (Próximamente conectaremos el Resource) ---
@export var speed_base = 5.0
@export var speed_sprint = 8.0
@export var crouch_speed = 2.5
@export var mouse_sensitivity = 0.002

# --- CONFIGURACIÓN DEL DASH ---
@export var dash_speed = 25.0       # Velocidad explosiva del dash
@export var dash_duration = 0.2    # Cuánto dura el impulso (en segundos)
@export var dash_cooldown_max = 1.0 # Tiempo para volver a usarlo
@export var double_tap_window = 0.3 # Tiempo máximo entre toques para detectar doble shift

# --- NODOS ---
@onready var collision_shape = $CollisionShape3D
@onready var visuals = $visuals
@onready var camera_mount = $camera_mount

@export var jump_base_force = 4.5
@export var air_control = 0.3
@export var long_jump_boost = 10.0  # Fuerza horizontal del salto largo
@export var bunny_hop_boost = 2.0   # Pequeño empujón al encadenar saltos
@export var push_force = 1.0 # Ajusta este valor para empujar más fuerte o más suave

var jump_charge = 0.0
var jump_cooldown = 0.0
var max_jump_charge = 1.0 # 1.0 extra (doble de salto)
var is_charging = false

# --- VARIABLES DE ESTADO ---
var is_sprinting = false
var is_crouching = false
var default_height = 2.0
var crouch_height = 1.0

var dash_timer = 0.0          # Cronómetro de la duración del dash
var dash_cooldown = 0.0       # Cronómetro del enfriamiento
var last_sprint_tap = 0.0     # Cuándo fue la última vez que tocamos Shift
var is_dashing = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	default_height = collision_shape.shape.height

func _input(event):
	# Rotación de cámara tipo Jedi Academy/Warzone
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity) # Gira el cuerpo (Eje Y)
		camera_mount.rotate_x(-event.relative.y * mouse_sensitivity) # Gira la cámara (Eje X)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -1.2, 1.2) # Límite de mirada
		
	# DASH: Usamos event.is_action_pressed para detectar el clic inicial
	if event.is_action_pressed("sprint"):
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if current_time - last_sprint_tap < double_tap_window and dash_cooldown <= 0:
			start_dash()
		
		last_sprint_tap = current_time

func _physics_process(delta):
	# Reducir cronómetros
	if dash_timer > 0: 
		dash_timer -= delta
	else: 
		is_dashing = false
	
	if dash_cooldown > 0: 
		dash_cooldown -= delta

	# 1. GRAVEDAD
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. PROCESAR ESTADOS (¡Esto es lo que faltaba!)
	handle_states()

	# 3. PROCESAR SALTO
	handle_jump_logic(delta)

	# 4. PROCESAR MOVIMIENTO
	if not is_dashing:
		handle_movement_logic(delta)

	# 5. EJECUTAR FÍSICAS
	move_and_slide()
	
	# 6. EMPUJAR OBJETOS (¡Añade esto!)
	handle_box_pushing()

func handle_states():
	# Sprint frontal
	is_sprinting = Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward") and not is_crouching
	
	# Agachado (Crouch)
	if Input.is_action_just_pressed("crouch"):
		is_crouching = !is_crouching
		toggle_crouch_logic()

func toggle_crouch_logic():
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	
	if is_crouching:
		# En lugar de mover el nodo, solo encogemos la forma
		# y ajustamos la posición de visuales y cámara
		tween.tween_property(collision_shape.shape, "height", crouch_height, 0.1)
		# Bajamos la posición de la colisión para que los pies se queden en el suelo (y=0.5 si la altura es 1)
		tween.tween_property(collision_shape, "position:y", 0.5, 0.1) 
		tween.tween_property(camera_mount, "position:y", 0.8, 0.1)
	else:
		# Para levantarse, primero verificamos si hay algo arriba (opcional pero recomendado)
		tween.tween_property(collision_shape.shape, "height", default_height, 0.1)
		tween.tween_property(collision_shape, "position:y", 1.0, 0.1) # Centro a 1.0 si altura es 2.0
		tween.tween_property(camera_mount, "position:y", 1.5, 0.1)

func handle_movement_logic(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = speed_base
	if is_sprinting: current_speed = speed_sprint
	if is_crouching: current_speed = crouch_speed

	if is_on_floor():
		# En el suelo el control es total
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)
	else:
		# EN EL AIRE (Jedi Academy): No sobrescribimos velocity, la influenciamos suavemente
		if direction:
			# El lerp permite que mantengas la inercia pero corrijas un poco
			velocity.x = lerp(velocity.x, direction.x * current_speed, air_control * delta * 5.0)
			velocity.z = lerp(velocity.z, direction.z * current_speed, air_control * delta * 5.0)
		
	if is_sprinting:
		# Si el input es hacia adelante (y < 0 en get_vector), permitimos velocidad máxima
		if input_dir.y < -0.5: 
			current_speed = speed_sprint
		else:
			# Penalización por correr de lado o atrás (ej: 70% del sprint)
			current_speed = speed_sprint * 0.7

func handle_jump_logic(delta):
	# Reducimos el cooldown cada frame
	if jump_cooldown > 0:
		jump_cooldown -= delta

	if is_on_floor():
		# Lógica existente: Levantarse al saltar si estás agachado
		if Input.is_action_just_pressed("jump") and is_crouching:
			is_crouching = false
			toggle_crouch_logic()

		# --- FASE DE CARGA ---
		if Input.is_action_pressed("jump"):
			is_charging = true
			jump_charge = move_toward(jump_charge, max_jump_charge, delta * 1.5)
		
		# --- FASE DE LANZAMIENTO (Al soltar Espacio) ---
		if Input.is_action_just_released("jump") and is_charging:
			# Detectamos si el jugador está pulsando "adelante" (W o Joystick arriba)
			var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var is_moving_forward = input_dir.y < -0.5 # -1 es hacia adelante puro
			
			# Caso 1: SALTO LARGO (Sprint + Carga alta + Adelante + Sin Cooldown)
			if is_sprinting and is_moving_forward and jump_charge > 0.5 and jump_cooldown <= 0:
				# Impulso horizontal fuerte basado en la carga
				var horizontal_force = long_jump_boost * jump_charge
				velocity += -transform.basis.z * horizontal_force
				
				# Salto vertical más bajo (salto parabólico)
				velocity.y = jump_base_force * 0.7 
				jump_cooldown = 1.2 # Penalización de tiempo por el esfuerzo
				
			# Caso 2: BUNNY HOP (Sprint + Carga mínima + Adelante)
			elif is_sprinting and is_moving_forward and jump_charge < 0.2:
				velocity.y = jump_base_force
				# Pequeño boost de inercia acumulativo
				velocity += -transform.basis.z * bunny_hop_boost
				
			# Caso 3: SALTO NORMAL / PROTOTYPE (Cualquier otra dirección o sin sprint)
			else:
				var total_jump = jump_base_force + (jump_charge * 1.5)
				velocity.y = total_jump
			
			# Reset de estado
			is_charging = false
			jump_charge = 0.0
			
	else:
		# En el aire cancelamos la carga para evitar bugs
		is_charging = false

func handle_box_pushing():
	# Revisamos colisiones después del move_and_slide
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		# Si es una de tus cajas RigidBody3D
		if collider is RigidBody3D:
			# Empujamos en dirección opuesta al choque
			var direction = -collision.get_normal()
			
			# Calculamos la fuerza (nuestra velocidad + la fuerza base)
			# Dividimos por la masa para que la de 50kg sea más difícil de mover
			var impulse = direction * push_force * velocity.length()
			
			# Aplicamos el impulso en la posición del choque para que pueda rotar
			collider.apply_impulse(impulse, collision.get_position() - collider.global_position)
			
func start_dash():
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown = dash_cooldown_max
	
	# Obtenemos la dirección actual o vamos hacia adelante si no hay input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dir == Vector3.ZERO:
		dir = -transform.basis.z # Hacia adelante por defecto
	
	# Aplicamos la velocidad de golpe
	velocity.x = dir.x * dash_speed
	velocity.z = dir.z * dash_speed
	velocity.y = 0 # Opcional: Descomenta esto si quieres que el dash sea puramente horizontal
