extends CharacterBody3D

# --- ESTADÍSTICAS (Próximamente conectaremos el Resource) ---
@export var speed_base = 5.0
@export var speed_sprint = 8.0
@export var crouch_speed = 2.5
@export var mouse_sensitivity = 0.002

# --- NODOS ---
@onready var collision_shape = $CollisionShape3D
@onready var visuals = $visuals
@onready var camera_mount = $camera_mount

@export var jump_base_force = 4.5
@export var air_control = 0.3
var jump_charge = 0.0
var max_jump_charge = 1.0 # 1.0 extra (doble de salto)
var is_charging = false

# --- VARIABLES DE ESTADO ---
var is_sprinting = false
var is_crouching = false
var default_height = 2.0
var crouch_height = 1.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	default_height = collision_shape.shape.height

func _input(event):
	# Rotación de cámara tipo Jedi Academy/Warzone
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity) # Gira el cuerpo (Eje Y)
		camera_mount.rotate_x(-event.relative.y * mouse_sensitivity) # Gira la cámara (Eje X)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -1.2, 1.2) # Límite de mirada

func _physics_process(delta):
	# 1. GRAVEDAD
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. PROCESAR ESTADOS (¡Esto es lo que faltaba!)
	handle_states()

	# 3. PROCESAR SALTO
	handle_jump_logic(delta)

	# 4. PROCESAR MOVIMIENTO
	handle_movement_logic(delta)

	# 5. EJECUTAR FÍSICAS
	move_and_slide()

func handle_states():
	# Sprint frontal
	is_sprinting = Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward") and not is_crouching
	
	# Agachado (Crouch)
	if Input.is_action_just_pressed("crouch"):
		is_crouching = !is_crouching
		toggle_crouch_logic()

func toggle_crouch_logic():
	var tween = create_tween().set_parallel(true)
	
	if is_crouching:
		# --- ESTADO AGACHADO ---
		tween.tween_property(collision_shape.shape, "height", 1.0, 0.1)
		
		if is_on_floor():
			# Si está en el suelo, se agacha normal (baja la cabeza)
			tween.tween_property(collision_shape, "position:y", 0.5, 0.1)
			tween.tween_property(camera_mount, "position:y", 0.8, 0.1)
		else:
			# SI ESTÁ EN EL AIRE (Estilo Half-Life 2):
			# Mantenemos la cámara arriba, pero subimos la colisión para recoger piernas
			tween.tween_property(collision_shape, "position:y", 1.5, 0.1) 
			# La cámara se queda casi igual para no perder visibilidad
			tween.tween_property(camera_mount, "position:y", 1.5, 0.1)
	else:
		# --- VOLVER A ESTADO NORMAL ---
		tween.tween_property(collision_shape.shape, "height", 2.0, 0.1)
		tween.tween_property(collision_shape, "position:y", 1.0, 0.1)
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
		

func handle_jump_logic(delta):
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and is_crouching:
			is_crouching = false
			toggle_crouch_logic() # Se pone de pie antes de saltar
		# Mientras mantienes ESPACIO, cargas el salto (Prototype)
		if Input.is_action_pressed("jump"):
			is_charging = true
			jump_charge = move_toward(jump_charge, max_jump_charge, delta * 1.5)
			# Opcional: imprimir carga para ver si funciona
			# print("Cargando salto: ", jump_charge) 
		
		# Al soltar ESPACIO, aplicamos la fuerza acumulada
		if Input.is_action_just_released("jump") and is_charging:
			var total_jump = jump_base_force + (jump_charge * 1)
			velocity.y = total_jump
			
			# Reset
			is_charging = false
			jump_charge = 0.0
	else:
		# Si estamos en el aire, cancelamos la carga por si acaso
		is_charging = false
