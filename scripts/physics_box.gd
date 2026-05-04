@tool # <--- Esto permite ver los cambios en el editor en tiempo real
extends RigidBody3D

@export var size := Vector3(1.0, 1.0, 1.0):
	set(value):
		size = value
		update_box() # Se ejecuta cada vez que cambias el valor en el Inspector

func _ready():
	update_box()

func update_box():
	# 1. Ajustamos el tamaño visual (Nodo MeshInstance3D)
	if has_node("MeshInstance3D"):
		$MeshInstance3D.scale = size
	
	# 2. Ajustamos la colisión de forma única
	if has_node("CollisionShape3D"):
		var box_shape = BoxShape3D.new()
		box_shape.size = size
		$CollisionShape3D.shape = box_shape
