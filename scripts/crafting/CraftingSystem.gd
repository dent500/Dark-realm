## CraftingSystem.gd
## Recipe-based crafting. Checks inventory for ingredients and produces output item.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal item_crafted(item_id: String, quantity: int)
signal crafting_failed(reason: String)

# ─── Recipe Database ──────────────────────────────────────────────────────────
const RECIPES = [
	{
		"id": "health_potion",
		"result": "health_potion",
		"result_qty": 2,
		"label": "Health Potion x2",
		"ingredients": [{"id": "herbs", "qty": 3}],
		"description": "Brew healing herbs into a restorative draught."
	},
	{
		"id": "mana_crystal",
		"result": "mana_crystal",
		"result_qty": 1,
		"label": "Mana Crystal",
		"ingredients": [{"id": "dark_essence", "qty": 1}, {"id": "herbs", "qty": 2}],
		"description": "Infuse dark essence with herbs to condense magical energy."
	},
	{
		"id": "iron_sword",
		"result": "iron_sword",
		"result_qty": 1,
		"label": "Iron Sword",
		"ingredients": [{"id": "iron_ore", "qty": 3}, {"id": "wood", "qty": 1}],
		"description": "Forge a serviceable sword from raw iron ore and a wooden handle."
	},
	{
		"id": "iron_axe",
		"result": "iron_axe",
		"result_qty": 1,
		"label": "Iron Axe",
		"ingredients": [{"id": "iron_ore", "qty": 4}, {"id": "wood", "qty": 2}],
		"description": "A heavy axe, good for both woodcutting and combat."
	},
	{
		"id": "leather_armor",
		"result": "leather_armor",
		"result_qty": 1,
		"label": "Leather Armor",
		"ingredients": [{"id": "wolf_pelt", "qty": 3}, {"id": "herbs", "qty": 1}],
		"description": "Cured wolf pelt stitched into basic protective armor."
	},
	{
		"id": "campfire_kit",
		"result": "campfire_kit",
		"result_qty": 1,
		"label": "Campfire Kit",
		"ingredients": [{"id": "wood", "qty": 3}],
		"description": "Enough wood to start a campfire and rest through the night."
	},
	{
		"id": "iron_shield",
		"result": "iron_shield",
		"result_qty": 1,
		"label": "Iron Shield",
		"ingredients": [{"id": "iron_ore", "qty": 4}, {"id": "wood", "qty": 2}],
		"description": "A round iron shield for blocking incoming blows."
	}
]

var _inventory = null

func _ready() -> void:
	pass

func set_inventory(inv) -> void:
	_inventory = inv

# ─── Can Craft ────────────────────────────────────────────────────────────────
func can_craft(recipe_id: String) -> bool:
	var recipe = get_recipe(recipe_id)
	if recipe.is_empty() or _inventory == null:
		return false
	for ingredient in recipe["ingredients"]:
		if not _inventory.has_item(ingredient["id"], ingredient["qty"]):
			return false
	return true

func get_craftable_recipes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe in RECIPES:
		var r = recipe.duplicate()
		r["can_craft"] = can_craft(recipe["id"])
		result.append(r)
	return result

# ─── Craft ────────────────────────────────────────────────────────────────────
func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		emit_signal("crafting_failed", "Missing ingredients.")
		return false
	var recipe = get_recipe(recipe_id)
	# Consume ingredients
	for ingredient in recipe["ingredients"]:
		_inventory.remove_item(ingredient["id"], ingredient["qty"])
	# Add result
	_inventory.add_item(recipe["result"], recipe["result_qty"])
	emit_signal("item_crafted", recipe["result"], recipe["result_qty"])
	AIDungeonMaster.narrate_custom("You craft a " + recipe["label"] + " with practiced hands.")
	print("[Crafting] Crafted: ", recipe["label"])
	return true

# ─── Helpers ──────────────────────────────────────────────────────────────────
func get_recipe(recipe_id: String) -> Dictionary:
	for recipe in RECIPES:
		if recipe["id"] == recipe_id:
			return recipe
	return {}

func get_all_recipes() -> Array:
	return RECIPES
