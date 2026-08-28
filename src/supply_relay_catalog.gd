extends RefCounted
class_name SupplyRelayCatalog

# 两个网页使用同一份奖池。网站本身是游戏内的虚拟页面，不访问真实网络。
const DRAW_COST := 500
const SUPPLY_RELAY_SITE := "supplyrelay"
const FAKE_SUPPLY_SITE := "fakesupply"

# 权重总和为 100。弹药盒和手雷代表低价值结果；其余结果有机会超过
# 抽取成本，形成“可能亏损，也可能获得更高回报”的供给箱体验。
const REWARD_POOL := [
	{"item_id": "ammo_supply_box", "amount": 1, "weight": 55},
	{"item_id": "grenade", "amount": 1, "weight": 10},
	{"item_id": "suppressed_pistol", "amount": 1, "weight": 10},
	{"item_id": "shotgun", "amount": 1, "weight": 7},
	{"item_id": "chest_armor_military_vest", "amount": 1, "weight": 5},
	{"item_id": "backpack_military", "amount": 1, "weight": 4},
	{"item_id": "m4", "amount": 1, "weight": 4},
	{"item_id": "ar15", "amount": 1, "weight": 5},
]


static func is_known_site(site_id: String) -> bool:
	return site_id in [SUPPLY_RELAY_SITE, FAKE_SUPPLY_SITE]


static func is_real_site(site_id: String) -> bool:
	return site_id == SUPPLY_RELAY_SITE


static func get_reward_pool() -> Array:
	return REWARD_POOL.duplicate(true)


static func draw_reward() -> Dictionary:
	var total_weight := 0
	for entry: Dictionary in REWARD_POOL:
		total_weight += maxi(0, int(entry.get("weight", 0)))
	if total_weight <= 0:
		return {}
	var roll := randi_range(1, total_weight)
	var accumulated := 0
	for entry: Dictionary in REWARD_POOL:
		accumulated += maxi(0, int(entry.get("weight", 0)))
		if roll <= accumulated:
			return entry.duplicate(true)
	return REWARD_POOL.back().duplicate(true)


static func get_display_name(item_id: String) -> String:
	if item_id == "ammo_supply_box":
		return "弹药盒（200发）"
	var product := GlobalVar.get_shop_product(item_id)
	return str(product.get("name", item_id))


static func get_display_value(item_id: String, amount: int = 1) -> int:
	var product := GlobalVar.get_shop_product(item_id)
	return roundi(float(product.get("buy_price", 0)) * float(amount))


static func get_reward_text(item_id: String, amount: int) -> String:
	var name := get_display_name(item_id)
	return "%s × %d" % [name, amount] if amount != 1 else name
