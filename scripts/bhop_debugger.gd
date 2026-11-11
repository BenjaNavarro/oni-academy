extends CanvasLayer

@onready var player_ref: Node = get_parent()

@onready var timing_bar: ProgressBar = $PanelContainer/MarginContainer/VBoxContainer/TimingBar
@onready var timing_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TimingLabel
@onready var speed_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/SpeedLabel
@onready var stamina_bar: ProgressBar = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/StaminaBar
@onready var state_air: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/StateAir
@onready var state_ground: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/StateGround
@onready var state_window: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/StateWindow
@onready var state_bhop: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/StateBhop
@onready var result_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ResultLabel
@onready var real_speed_label: Label = $PanelContainer/MarginContainer/VBoxContainer/RealSpeedLabel

func _ready():
	if not player_ref:
		push_error("BhopDebugger: No se encontró el player!")
		return

	timing_bar.min_value = 0
	timing_bar.max_value = 100
	timing_bar.value = 0

	stamina_bar.min_value = 0
	stamina_bar.max_value = 100
	stamina_bar.value = 100

	visible = false
	print("BhopDebugger cargado. Presiona F3 para mostrar/ocultar.")

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible

func _process(_delta):
	if not player_ref or not visible:
		return

	# ---------- TIMING BAR ----------
	if player_ref.bhop_window_active:
		var ratio = player_ref.time_since_landed / player_ref.bhop_window_good
		timing_bar.value = ratio * 100

		if player_ref.time_since_landed <= player_ref.bhop_window_perfect:
			timing_bar.modulate = Color(0, 0.83, 0.67)
			timing_label.text = "PERFECT WINDOW"
			timing_label.modulate = Color(0, 0.83, 0.67)
		else:
			timing_bar.modulate = Color(1, 0.8, 0)
			timing_label.text = "GOOD WINDOW"
			timing_label.modulate = Color(1, 0.8, 0)
	else:
		timing_bar.value = 0
		if not player_ref.is_on_floor():
			timing_bar.modulate = Color(0.3, 0.67, 0.97)
			timing_label.text = "IN AIR"
			timing_label.modulate = Color(0.3, 0.67, 0.97)
		else:
			timing_bar.modulate = Color(0.33, 0.33, 0.33)
			timing_label.text = "WAITING..."
			timing_label.modulate = Color(0.5, 0.5, 0.5)

	# ---------- STATS ----------
	speed_label.text = "Speed: +%.1f" % player_ref.bhop_speed_bonus
	stamina_bar.value = player_ref.stamina

	# ---------- ESTADOS ----------
	state_air.modulate = Color(0.3, 0.67, 0.97) if not player_ref.is_on_floor() else Color(0.2, 0.2, 0.2)
	state_ground.modulate = Color(0, 0.83, 0.67) if player_ref.is_on_floor() else Color(0.2, 0.2, 0.2)
	state_window.modulate = Color(1, 0.8, 0) if player_ref.bhop_window_active else Color(0.2, 0.2, 0.2)

	var is_jedi = "is_jedi_sprinting" in player_ref and player_ref.is_jedi_sprinting
	if is_jedi:
		state_bhop.text = "JEDI"
		state_bhop.modulate = Color(0.2, 0.85, 1.0)
	elif player_ref.bhop_speed_bonus > 0:
		state_bhop.text = "BHOP"
		state_bhop.modulate = Color(1, 0.3, 0.3)
	else:
		state_bhop.text = "BHOP"
		state_bhop.modulate = Color(0.2, 0.2, 0.2)

	# ---------- RESULTADO ----------
	real_speed_label.text = "Velocidad: %.1f u/s" % player_ref.get_horizontal_speed()
	# Color según velocidad
	var real_speed = player_ref.get_horizontal_speed()
	if is_jedi:
		real_speed_label.modulate = Color(0.2, 0.85, 1.0)
	elif real_speed > player_ref.speed_run:
		real_speed_label.modulate = Color(1, 0.3, 0.3)  # Rojo = más rápido que sprint
	elif real_speed > player_ref.speed_base:
		real_speed_label.modulate = Color(1, 0.8, 0)    # Amarillo = entre caminar y sprint
	else:
		real_speed_label.modulate = Color(0.5, 0.5, 0.5) # Gris = caminando

	if is_jedi:
		var anim_scale = player_ref.anim_speed_scale if "anim_speed_scale" in player_ref else 1.0
		result_label.text = "JEDI SPRINT! Chain: %d | +%.1f (x%.2f anim)" % [player_ref.bhop_chain_count, player_ref.bhop_speed_bonus, anim_scale]
		result_label.modulate = Color(0.2, 0.85, 1.0)
	elif player_ref.bhop_chain_count > 0:
		result_label.text = "Chain: %d | Bonus: +%.1f" % [player_ref.bhop_chain_count, player_ref.bhop_speed_bonus]
		result_label.modulate = Color(0, 0.83, 0.67)
	else:
		result_label.text = "SHIFT + SPACE with timing..."
		result_label.modulate = Color(0.5, 0.5, 0.5)
