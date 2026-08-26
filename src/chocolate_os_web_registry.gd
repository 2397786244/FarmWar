extends RefCounted
class_name ChocolateOSWebRegistry

const DEFAULT_URL := "www.osapp.store"
const STORE_DOMAIN := "www.osapp.store"


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
