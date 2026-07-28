extends StaticBody3D
class_name Shop

signal transaction_completed(team: String, item_name: String, amount: float, is_buy: bool)

@export var npc_interaction_distance := 3.5
@export var shop_category := "general"
@export var shop_display_name := "田野交易站"
@export var interaction_hint := "[E] 打开商店"


func get_shop_list() -> Array[Dictionary]:
	return GlobalVar.get_shop_products(shop_category)


func get_shop_title() -> String:
	return shop_display_name


func get_interaction_hint(_player: GamePlayer = null) -> String:
	return interaction_hint


func uses_personal_dish_inventory() -> bool:
	return shop_category == "food_car"


func uses_personal_weapon_inventory() -> bool:
	return shop_category == "gun_store"


func allows_product(item_name: String) -> bool:
	var product := GlobalVar.get_shop_product(item_name)
	return not product.is_empty() \
		and str(product.get("shop_category", "general")) == shop_category


func buy(team: String, item_name: String, amount: float = 1.0) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_shop_transaction({
			"is_buy": true,
			"item_id": item_name,
			"amount": amount,
			"shop_category": shop_category,
		})
		return false
	if amount <= 0:
		return false
	var product: Dictionary = GlobalVar.get_shop_product(item_name)
	if product.is_empty() or not allows_product(item_name) or not bool(product.get("can_buy", false)):
		return false

	var total_price := roundi(float(product["buy_price"]) * amount)
	if GlobalVar.check_team_item_amount(team, "money") < total_price:
		return false
	if not GlobalVar.remove_item(team, "money", total_price):
		return false
	if not GlobalVar.add_item(team, item_name, amount):
		GlobalVar.add_item(team, "money", total_price)
		return false

	transaction_completed.emit(team, item_name, amount, true)
	return true


func sell(team: String, item_name: String, amount: float = 1.0) -> bool:
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_shop_transaction({
			"is_buy": false,
			"item_id": item_name,
			"amount": amount,
			"shop_category": shop_category,
		})
		return false
	if amount <= 0:
		return false
	var product: Dictionary = GlobalVar.get_shop_product(item_name)
	if product.is_empty() or not allows_product(item_name) or not bool(product.get("can_sell", false)):
		return false
	if GlobalVar.check_team_item_amount(team, item_name) < amount:
		return false

	var total_price := roundi(float(product["sell_price"]) * amount)
	if not GlobalVar.remove_item(team, item_name, amount):
		return false
	GlobalVar.add_team_reward(team, total_price)
	transaction_completed.emit(team, item_name, amount, false)
	return true


# NPC 走到商店附近后可直接调用，不需要打开 UI。
func can_npc_interact(npc: Node3D) -> bool:
	return is_instance_valid(npc) and \
		npc.global_position.distance_to(global_position) <= npc_interaction_distance


func npc_buy(npc: Node3D, team: String, item_name: String, amount: float = 1.0) -> bool:
	if not can_npc_interact(npc):
		return false
	return buy(team, item_name, amount)


func npc_sell(npc: Node3D, team: String, item_name: String, amount: float = 1.0) -> bool:
	if not can_npc_interact(npc):
		return false
	return sell(team, item_name, amount)
