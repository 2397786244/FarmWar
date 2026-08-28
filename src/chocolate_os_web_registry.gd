extends RefCounted
class_name ChocolateOSWebRegistry

const DEFAULT_URL := "www.osapp.store"
const STORE_DOMAIN := "www.osapp.store"
const SUPPLY_RELAY_DOMAIN := "www.supplyrelay.com"
const FAKE_SUPPLY_DOMAIN := "www.fakesupply.com"
const S_CHAT_DOMAIN := "s.com"
const RANGE_LEDGER_DOMAIN := "www.rangeledger.com"
const SOFIA_ON_WHEELS_DOMAIN := "www.sofiaonwheels.com"
const CIRCUIT_AND_CHAI_DOMAIN := "www.circuitandchai.com"
const MERCER_SEED_DOMAIN := "www.mercerseed.com"
const BELLWRENCH_DOMAIN := "www.bellwrench.com"


static func normalize_url(raw_value: String) -> Dictionary:
	var raw := raw_value.strip_edges()
	if raw.is_empty() or raw.contains(" "):
		return {"ok": false, "error": "invalid_address", "display_url": raw}
	var value := raw.to_lower()
	if value.begins_with("https://"):
		value = value.trim_prefix("https://")
	elif value.begins_with("http://"):
		value = value.trim_prefix("http://")
	if value.is_empty() or not value.contains("."):
		return {"ok": false, "error": "invalid_address", "display_url": raw}
	var slash_index := value.find("/")
	var domain := value if slash_index < 0 else value.left(slash_index)
	var path := "/" if slash_index < 0 else value.substr(slash_index)
	if domain == "osapp.store":
		domain = STORE_DOMAIN
	elif domain == "supplyrelay.com":
		domain = SUPPLY_RELAY_DOMAIN
	elif domain == "fakesupply.com":
		domain = FAKE_SUPPLY_DOMAIN
	elif domain == "s.chat" or domain == "www.s.chat":
		domain = S_CHAT_DOMAIN
	elif domain == "rangeledger.com":
		domain = RANGE_LEDGER_DOMAIN
	elif domain == "sofiaonwheels.com":
		domain = SOFIA_ON_WHEELS_DOMAIN
	elif domain == "circuitandchai.com":
		domain = CIRCUIT_AND_CHAI_DOMAIN
	elif domain == "mercerseed.com":
		domain = MERCER_SEED_DOMAIN
	elif domain == "bellwrench.com":
		domain = BELLWRENCH_DOMAIN
	var query := ""
	var query_index := path.find("?")
	if query_index >= 0:
		query = path.substr(query_index + 1)
		path = path.left(query_index)
	if path.is_empty():
		path = "/"
	while path.length() > 1 and path.ends_with("/"):
		path = path.left(path.length() - 1)
	return {
		"ok": true,
		"domain": domain,
		"path": path,
		"query": query,
		"display_url": domain + path.trim_suffix("/") if path != "/" else domain,
	}


static func resolve(raw_value: String) -> Dictionary:
	var parsed := normalize_url(raw_value)
	if not bool(parsed.get("ok", false)):
		parsed["page_kind"] = "invalid"
		parsed["title"] = "地址无效"
		return parsed
	var domain := str(parsed.get("domain", ""))
	var path := str(parsed.get("path", "/"))
	if domain == SUPPLY_RELAY_DOMAIN and path in ["/", "/supply"]:
		parsed["page_kind"] = "supply_relay"
		parsed["site_id"] = "supplyrelay"
		parsed["title"] = "Get Your Supply"
		return parsed
	if domain == FAKE_SUPPLY_DOMAIN and path in ["/", "/supply"]:
		parsed["page_kind"] = "fake_supply"
		parsed["site_id"] = "fakesupply"
		parsed["title"] = "Get Your Supply"
		return parsed
	if domain == S_CHAT_DOMAIN and path in ["/", "/feed"]:
		parsed["page_kind"] = "s_chat"
		parsed["title"] = "s.com · 社区动态"
		return parsed
	if domain == RANGE_LEDGER_DOMAIN:
		if path in ["/", "/catalog"]:
			parsed["page_kind"] = "range_ledger"
			parsed["page_id"] = "catalog"
			parsed["title"] = "Range Ledger · 枪械目录"
			return parsed
		if path == "/future-series":
			parsed["page_kind"] = "range_ledger"
			parsed["page_id"] = "future_series"
			parsed["title"] = "Range Ledger · Future 系列"
			return parsed
		if path == "/safety":
			parsed["page_kind"] = "range_ledger"
			parsed["page_id"] = "safety"
			parsed["title"] = "Range Ledger · 安全与补给"
			return parsed
		parsed["page_kind"] = "404"
		parsed["title"] = "404 - 找不到网页"
		return parsed
	if domain == SOFIA_ON_WHEELS_DOMAIN and path in ["/", "/menu"]:
		parsed["page_kind"] = "sofia_on_wheels"
		parsed["page_id"] = "menu" if path == "/menu" else "home"
		parsed["title"] = "Sofia on Wheels · 餐车菜单"
		return parsed
	if domain == CIRCUIT_AND_CHAI_DOMAIN:
		if path in ["/", "/os08"]:
			parsed["page_kind"] = "circuit_and_chai"
			parsed["page_id"] = "os08"
			parsed["title"] = "Circuit & Chai · ChocolateOS08"
			return parsed
		if path == "/os26":
			parsed["page_kind"] = "circuit_and_chai"
			parsed["page_id"] = "os26"
			parsed["title"] = "Circuit & Chai · ChocolateOS26"
			return parsed
		parsed["page_kind"] = "404"
		parsed["title"] = "404 - 找不到网页"
		return parsed
	if domain == MERCER_SEED_DOMAIN:
		if path == "/":
			parsed["page_kind"] = "mercer_seed"
			parsed["page_id"] = "home"
			parsed["title"] = "Mercer Seed & Supply · 农场用品公告"
			return parsed
		if path == "/seed-guide":
			parsed["page_kind"] = "mercer_seed"
			parsed["page_id"] = "seed_guide"
			parsed["title"] = "Mercer Seed & Supply · 种子指南"
			return parsed
		parsed["page_kind"] = "404"
		parsed["title"] = "404 - 找不到网页"
		return parsed
	if domain == BELLWRENCH_DOMAIN:
		var bellwrench_page_ids := {
			"/": "vehicles",
			"/vehicles": "vehicles",
			"/service": "service",
			"/upgrades": "upgrades",
			"/farm-base": "farm_base",
		}
		if bellwrench_page_ids.has(path):
			parsed["page_kind"] = "bellwrench"
			parsed["page_id"] = bellwrench_page_ids[path]
			parsed["title"] = {
				"vehicles": "Bellwrench · 可购买载具",
				"service": "Bellwrench · 维修服务",
				"upgrades": "Bellwrench · 升级模块",
				"farm_base": "Bellwrench · FarmBaseVehicle 专区",
			}.get(str(bellwrench_page_ids[path]), "Bellwrench · 载具服务")
			return parsed
		parsed["page_kind"] = "404"
		parsed["title"] = "404 - 找不到网页"
		return parsed
	if domain != STORE_DOMAIN:
		parsed["page_kind"] = "404"
		parsed["title"] = "404 - 找不到网页"
		return parsed
	if path == "/" or path == "/apps":
		parsed["page_kind"] = "store"
		parsed["title"] = "Chocolate 应用库"
		return parsed
	if path.begins_with("/apps/") and path.trim_prefix("/apps/").find("/") < 0:
		parsed["page_kind"] = "store_detail"
		parsed["app_id"] = path.trim_prefix("/apps/")
		parsed["title"] = "应用详情"
		return parsed
	parsed["page_kind"] = "404"
	parsed["title"] = "404 - 找不到网页"
	return parsed
