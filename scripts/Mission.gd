# scripts/core/Mission.gd
extends Resource
class_name Mission

@export var unit: Unit
@export var region: Region
@export var mission_key: String = ""

func _init(u: Unit = null, r: Region = null, key: String = ""):
	unit = u
	region = r
	mission_key = key
