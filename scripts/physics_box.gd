@tool
extends RigidBody3D

@export var size := Vector3(1.0, 1.0, 1.0):
	set(value):
		size = value
		update_box()

func _ready():
	update_box()
	# Fricción realista: las cajas no se deslizan eternamente
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.8      # Fricción alta
	physics_material_override.bounce = 0.1        # Casi sin rebote

func update_box():
	if has_node("MeshInstance3D"):
		$MeshInstance3D.scale = size
	
	if has_node("CollisionShape3D"):
		var box_shape = BoxShape3D.new()
		box_shape.size = size
		$CollisionShape3D.shape = box_shape
		
		# Ajustar masa proporcional al tamaño (opcional pero recomendado)
		mass = size.x * size.y * size.z * 10.0  # 10kg por unidad cúbica
