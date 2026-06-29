class_name Affix
extends Resource

@export var affix_name: String = ""
@export var affix_description: String = ""
@export var affix_icon: Texture2D

@export var stat_modifiers: Array[StatModifier] = []
@export var trigger_effects: Array[TriggerEffect] = []
@export var conditional_bonuses: Array[ConditionalBonus] = []
