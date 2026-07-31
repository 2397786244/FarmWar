extends Node

signal storage_changed(team: String, item_name: String, new_amount: float)
signal team_money_changed(team: String, delta: float, new_amount: float)
signal team_score_changed(team: String, delta: float, new_score: float)

const INITIAL_MONEY := 1000

var gameworld: Node3D = null

# 商品价格以每 kg 计；非食材设备以每件计。
var shop_products: Array[Dictionary] = [
	{"id": "tomato", "name": "西红柿", "unit": "kg", "buy_price": 6, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "corn", "name": "玉米", "unit": "kg", "buy_price": 5, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "wheat", "name": "小麦", "unit": "kg", "buy_price": 3, "sell_price": 2, "can_buy": true, "can_sell": true},
	{"id": "pepper", "name": "辣椒", "unit": "kg", "buy_price": 10, "sell_price": 7, "can_buy": true, "can_sell": true},
	{"id": "strawberry", "name": "草莓", "unit": "kg", "buy_price": 26, "sell_price": 18, "can_buy": true, "can_sell": true},
	{"id": "eggplant", "name": "茄子", "unit": "kg", "buy_price": 7, "sell_price": 5, "can_buy": true, "can_sell": true},
	{"id": "pumpkin", "name": "南瓜", "unit": "kg", "buy_price": 5, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "watermelon", "name": "西瓜", "unit": "kg", "buy_price": 4, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "beet", "name": "甜菜", "unit": "kg", "buy_price": 6, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "cabbage", "name": "卷心菜", "unit": "kg", "buy_price": 4, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "cotton", "name": "棉花", "unit": "kg", "buy_price": 14, "sell_price": 10, "can_buy": true, "can_sell": true},
	{"id": "lettuce", "name": "生菜", "unit": "kg", "buy_price": 6, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "mint", "name": "薄荷", "unit": "kg", "buy_price": 20, "sell_price": 14, "can_buy": true, "can_sell": true},
	{"id": "peanut", "name": "花生", "unit": "kg", "buy_price": 12, "sell_price": 8, "can_buy": true, "can_sell": true},
	{"id": "sugarcane", "name": "甘蔗", "unit": "kg", "buy_price": 4, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "tobacco", "name": "烟草", "unit": "kg", "buy_price": 18, "sell_price": 13, "can_buy": true, "can_sell": true},
	{"id": "grape", "name": "葡萄", "unit": "kg", "buy_price": 16, "sell_price": 11, "can_buy": true, "can_sell": true},
	{"id": "kiwi", "name": "猕猴桃", "unit": "kg", "buy_price": 20, "sell_price": 14, "can_buy": true, "can_sell": true},
	{"id": "hazelnut", "name": "榛子", "unit": "kg", "buy_price": 45, "sell_price": 32, "can_buy": true, "can_sell": true},
	{"id": "pistachio", "name": "开心果", "unit": "kg", "buy_price": 65, "sell_price": 46, "can_buy": true, "can_sell": true},
	{"id": "walnut", "name": "核桃", "unit": "kg", "buy_price": 38, "sell_price": 27, "can_buy": true, "can_sell": true},
	{"id": "soybean", "name": "大豆", "unit": "kg", "buy_price": 5, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "blackpepper", "name": "黑胡椒", "unit": "kg", "buy_price": 80, "sell_price": 56, "can_buy": true, "can_sell": true},
	{"id": "potato", "name": "土豆", "unit": "kg", "buy_price": 4, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "chicken", "name": "鸡肉", "unit": "kg", "buy_price": 16, "sell_price": 11, "can_buy": true, "can_sell": true},
	{"id": "egg", "name": "鸡蛋", "unit": "kg", "buy_price": 6, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "golden_egg", "name": "大金蛋", "unit": "kg", "buy_price": 600, "sell_price": 400, "can_buy": true, "can_sell": true},
	{"id": "pork", "name": "猪肉", "unit": "kg", "buy_price": 24, "sell_price": 17, "can_buy": true, "can_sell": true},
	{"id": "beef", "name": "牛肉", "unit": "kg", "buy_price": 54, "sell_price": 38, "can_buy": true, "can_sell": true},
	{"id": "animal_chicken", "name": "活鸡", "kind": "livestock", "shop_category": "livestock_market", "unit": "item", "buy_price": 200, "sell_price": 100, "can_buy": true, "can_sell": true},
	{"id": "animal_pig", "name": "活猪", "kind": "livestock", "shop_category": "livestock_market", "unit": "item", "buy_price": 450, "sell_price": 220, "can_buy": true, "can_sell": true},
	{"id": "animal_angus_cow", "name": "活安格斯牛", "kind": "livestock", "shop_category": "livestock_market", "unit": "item", "buy_price": 900, "sell_price": 450, "can_buy": true, "can_sell": true},
	{"id": "wheat_flour", "name": "小麦粉", "unit": "kg", "buy_price": 8, "sell_price": 5, "can_buy": true, "can_sell": true},
	{"id": "sugar", "name": "糖", "unit": "kg", "buy_price": 12, "sell_price": 8, "can_buy": true, "can_sell": true},
	{"id": "oil", "name": "油", "unit": "kg", "buy_price": 20, "sell_price": 14, "can_buy": true, "can_sell": true},
	{"id": "yeast", "name": "酵母粉", "unit": "kg", "buy_price": 60, "sell_price": 42, "can_buy": true, "can_sell": true},
	{"id": "water", "name": "水", "unit": "kg", "buy_price": 1, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "log", "name": "原木", "unit": "kg", "buy_price": 18, "sell_price": 12, "can_buy": true, "can_sell": true},
	{"id": "coal", "name": "煤矿", "unit": "kg", "buy_price": 14, "sell_price": 9, "can_buy": true, "can_sell": true},
	{"id": "iron", "name": "铁矿", "unit": "kg", "buy_price": 28, "sell_price": 20, "can_buy": true, "can_sell": true},
	{"id": "copper", "name": "铜矿", "unit": "kg", "buy_price": 36, "sell_price": 25, "can_buy": true, "can_sell": true},
	{"id": "limestone", "name": "石灰石", "unit": "kg", "buy_price": 10, "sell_price": 7, "can_buy": true, "can_sell": true},
	{"id": "shield_door", "name": "能量护盾", "unit": "item", "buy_price": 200, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "auto_shooter", "name": "自动射手", "unit": "item", "buy_price": 100, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "burger", "name": "汉堡", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 25, "sell_price": 12, "can_buy": true, "can_sell": true},
	{"id": "fries", "name": "薯条", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 12, "sell_price": 5, "can_buy": true, "can_sell": true},
	{"id": "taco", "name": "塔可", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 18, "sell_price": 8, "can_buy": true, "can_sell": true},
	{"id": "soda", "name": "汽水", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 8, "sell_price": 3, "can_buy": true, "can_sell": true},
	{"id": "ice_cream", "name": "冰淇淋", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 10, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "egg_tart", "name": "蛋挞", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 9, "sell_price": 4, "can_buy": true, "can_sell": true},
	{"id": "fried_chicken_nuggets", "name": "炸鸡块", "kind": "dish", "shop_category": "food_car", "unit": "item", "buy_price": 16, "sell_price": 7, "can_buy": true, "can_sell": true},
	{"id": "m4", "name": "M4卡宾枪", "kind": "weapon", "shop_category": "gun_store", "unit": "item", "buy_price": 3000, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "ar15", "name": "AR15步枪", "kind": "weapon", "shop_category": "gun_store", "unit": "item", "buy_price": 4000, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "suppressed_pistol", "name": "消音手枪", "kind": "weapon", "shop_category": "gun_store", "unit": "item", "buy_price": 800, "sell_price": 0, "can_buy": true, "can_sell": false},
	{"id": "grenade", "name": "手雷", "kind": "weapon", "shop_category": "gun_store", "unit": "item", "buy_price": 200, "sell_price": 0, "can_buy": true, "can_sell": false},
]

var plant_item_list: Array = IngredientCatalog.get_plantable_ids()

var team_storage: Dictionary = {
	"blue": {"money": INITIAL_MONEY},
	"red": {"money": INITIAL_MONEY},
}

# 胜利分数与可消费的队伍资金分离。分数只在本局奖励/收入结算时增加，
# 购买、建造和其他资金支出不会影响分数。
var team_scores: Dictionary = {
	"blue": 0.0,
	"red": 0.0,
}

var team_match_stats: Dictionary = {
	"blue": _make_empty_match_stats(),
	"red": _make_empty_match_stats(),
}

var pending_player_selection:Dictionary = {}
var open_server_browser_on_main_menu := false
var open_cooperative_worlds_on_main_menu := false
var cooperative_return_notice := ""

func _init() -> void:
	for team: String in team_storage:
		for product: Dictionary in shop_products:
			var item_id := str(product["id"])
			if not team_storage[team].has(item_id):
				team_storage[team][item_id] = 0


func get_shop_products(shop_category := "general") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for product: Dictionary in shop_products:
		if str(product.get("shop_category", "general")) == shop_category:
			result.append(product)
	return result


func get_shop_product(item_name: String) -> Dictionary:
	for product: Dictionary in shop_products:
		if product["id"] == item_name:
			return product
	return {}


func add_item(team: String, item_name: String, amount: float) -> bool:
	if GameAuthority.should_send_network_requests():
		push_warning("Client proxy cannot authoritatively add inventory items.")
		return false
	if amount <= 0 or not team_storage.has(team):
		return false
	var team_data: Dictionary = team_storage[team]
	if not team_data.has(item_name):
		team_data[item_name] = 0
	var previous_amount := float(team_data[item_name])
	team_data[item_name] += amount
	var new_amount := float(team_data[item_name])
	storage_changed.emit(team, item_name, new_amount)
	if item_name == "money":
		team_money_changed.emit(team, new_amount - previous_amount, new_amount)
	return true


func add_team_reward(team: String, amount: float) -> bool:
	# 既有的奖励性收入同时写入资金和胜利分数。
	if amount <= 0.0:
		return false
	if not add_item(team, "money", amount):
		return false
	add_team_score(team, amount)
	return true


func add_team_score(team: String, amount: float) -> bool:
	if GameAuthority.should_send_network_requests():
		push_warning("Client proxy cannot authoritatively add team score.")
		return false
	if amount <= 0.0 or not team_scores.has(team):
		return false
	var previous_score := float(team_scores[team])
	var new_score := previous_score + amount
	team_scores[team] = new_score
	team_score_changed.emit(team, amount, new_score)
	return true


func remove_item(team: String, item_name: String, amount: float) -> bool:
	if GameAuthority.should_send_network_requests():
		push_warning("Client proxy cannot authoritatively remove inventory items.")
		return false
	if amount <= 0 or not team_storage.has(team):
		return false
	var team_data: Dictionary = team_storage[team]
	if not team_data.has(item_name) or float(team_data[item_name]) + 0.0001 < amount:
		return false
	var previous_amount := float(team_data[item_name])
	team_data[item_name] = maxf(0.0, previous_amount - amount)
	var new_amount := float(team_data[item_name])
	storage_changed.emit(team, item_name, new_amount)
	if item_name == "money":
		team_money_changed.emit(team, new_amount - previous_amount, new_amount)
	return true


func check_team_item_amount(team: String, item_name: String) -> float:
	if not team_storage.has(team):
		return 0.0
	return float(team_storage[team].get(item_name, 0.0))


func get_game_stats(team: String, query: StringName):
	if not team_storage.has(team):
		return 0
	return team_storage[team].get(query, 0)


func get_team_score(team: String) -> int:
	if not team_scores.has(team):
		return 0
	return roundi(float(team_scores[team]))


func get_team_scores() -> Dictionary:
	return {
		"red": get_team_score("red"),
		"blue": get_team_score("blue"),
	}


func _make_empty_match_stats() -> Dictionary:
	return {
		"completed_orders": 0,
		"partial_orders": 0,
		"agriculture_livestock": 0,
		"cooking": 0,
		"mining": 0,
		"combat": 0,
	}


func add_match_stat(team: String, category: String, amount: int) -> void:
	if amount <= 0 or not team_match_stats.has(team):
		return
	var stats: Dictionary = team_match_stats[team]
	stats[category] = int(stats.get(category, 0)) + amount
	team_match_stats[team] = stats


func get_team_match_stats(team: String) -> Dictionary:
	return (team_match_stats.get(team, _make_empty_match_stats()) as Dictionary).duplicate(true)


func get_all_team_match_stats() -> Dictionary:
	return {"red": get_team_match_stats("red"), "blue": get_team_match_stats("blue")}


func apply_team_scores(scores: Dictionary, allow_decrease := false) -> void:
	# 客户端低频快照可能晚于可靠加分事件到达；同一局内不得让旧快照回退分数。
	for team: String in team_scores:
		if not scores.has(team):
			continue
		var previous_score := float(team_scores[team])
		var incoming_score := maxf(0.0, float(scores.get(team, previous_score)))
		var new_score := incoming_score if allow_decrease else maxf(previous_score, incoming_score)
		team_scores[team] = new_score
		var delta := new_score - previous_score
		if not is_zero_approx(delta):
			team_score_changed.emit(team, delta, new_score)


func get_public_inventory_state() -> Dictionary:
	return {
		"teams": team_storage.duplicate(true),
		"scores": get_team_scores(),
	}


func reset_team_storage() -> void:
	if GameAuthority.should_send_network_requests():
		push_warning("Client proxy cannot authoritatively reset team storage.")
		return
	for team: String in team_storage:
		for key in team_storage[team]:
			team_storage[team][key] = INITIAL_MONEY if key == "money" else 0
			storage_changed.emit(team, key, float(team_storage[team][key]))
	for team: String in team_scores:
		var previous_score := float(team_scores[team])
		team_scores[team] = 0.0
		if not is_zero_approx(previous_score):
			team_score_changed.emit(team, -previous_score, 0.0)
	for team: String in team_match_stats:
		team_match_stats[team] = _make_empty_match_stats()


	
