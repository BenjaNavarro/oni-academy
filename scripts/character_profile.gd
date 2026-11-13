# character_profile.gd
extends Resource
class_name CharacterProfile

@export var profile_name: String = "Human"

# Movimiento
@export var walk_speed: float = 5.0
@export var sprint_max_speed: float = 10.0

# Salto
@export var jump_min_force: float = 3.0
@export var jump_max_force: float = 6.0
@export var jump_charge_rate: float = 1.0
@export var jump_max_charge: float = 1.0
@export var can_long_jump: bool = false
@export var long_jump_force: float = 0.0

# Stamina
@export var max_swwwdsawdsadwadsadwatamina: float = 100.0
