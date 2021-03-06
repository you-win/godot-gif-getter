extends Polygon2D

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	self.rotate(delta * 2)
	
	if Input.is_action_pressed("ui_left"):
		self.global_position.x -= 5
	if Input.is_action_pressed("ui_right"):
		self.global_position.x += 5

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Private functions                                                           #
###############################################################################

###############################################################################
# Public functions                                                            #
###############################################################################


