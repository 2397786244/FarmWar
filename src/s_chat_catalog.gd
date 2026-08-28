extends RefCounted
class_name SChatCatalog

const POSTS_PATH := "res://data/s_chat/posts.json"
const DEFAULT_AVATAR_PATH := "res://assets/icons/s_chat/avatars/default.png"
const LIKE_ICON_PATH := "res://assets/icons/s_chat/actions/like.png"
const COMMENT_ICON_PATH := "res://assets/icons/s_chat/actions/comment.png"
const REPOST_ICON_PATH := "res://assets/icons/s_chat/actions/repost.png"

# 互动数据属于帖子本身的静态展示数据，不代表多人世界状态。基础点赞、评论
# 和转发数由内容作者预先写入 posts.json，打开不同电脑时看到的是同一组帖子
# 基础数据；玩家自己的点赞会额外叠加在当前电脑的 Browser app_data 上。
const NPC_PROFILES := {
	"npc_leah_mercer": {
		"display_name": "Leah Mercer",
		"handle": "@leahgrows",
		"avatar": "res://assets/icons/s_chat/avatars/leah_mercer.png",
		"popularity": 0.96,
	},
	"npc_marcus_bell": {
		"display_name": "Marcus Bell",
		"handle": "@bellwrench",
		"avatar": "res://assets/icons/s_chat/avatars/marcus_bell.png",
		"popularity": 0.89,
	},
	"npc_dana_ortiz": {
		"display_name": "Dana Ortiz",
		"handle": "@dana_dines",
		"avatar": "res://assets/icons/s_chat/avatars/dana_ortiz.png",
		"popularity": 1.18,
	},
	"npc_calvin_reed": {
		"display_name": "Calvin Reed",
		"handle": "@rangeledger",
		"avatar": "res://assets/icons/s_chat/avatars/calvin_reed.png",
		"popularity": 0.84,
	},
	"npc_jordan_kim": {
		"display_name": "Jordan Kim",
		"handle": "@roadsidejordan",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.82,
	},
	"npc_evelyn_shaw": {
		"display_name": "Evelyn Shaw",
		"handle": "@fieldnotes_eve",
		"avatar": "res://assets/icons/s_chat/avatars/evelyn_shaw.png",
		"popularity": 0.92,
	},
	"npc_theo_grant": {
		"display_name": "Theo Grant",
		"handle": "@nightshift_tg",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.70,
	},
	"npc_aiko_mori": {
		"display_name": "Aiko Mori",
		"handle": "@aiko_afterrain",
		"avatar": "res://assets/icons/s_chat/avatars/aiko_mori.png",
		"popularity": 1.45,
	},
	"npc_eddie_vale": {
		"display_name": "Eddie Vale",
		"handle": "@dealwire_daily",
		"avatar": "res://assets/icons/s_chat/avatars/eddie_vale.png",
		"popularity": 1.12,
	},
	"npc_grace_chen": {
		"display_name": "Grace Chen",
		"handle": "@grainroute",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.86,
	},
	"npc_nolan_fraser": {
		"display_name": "Nolan Fraser",
		"handle": "@nolanpulls",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.76,
	},
	"npc_ren_takahashi": {
		"display_name": "Ren Takahashi",
		"handle": "@renbuilds",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.88,
	},
	"npc_priya_nair": {
		"display_name": "Priya Nair",
		"handle": "@circuitandchai",
		"avatar": "res://assets/icons/s_chat/avatars/priya_nair.png",
		"popularity": 1.05,
	},
	"npc_seo_yeon_han": {
		"display_name": "Seo-yeon Han",
		"handle": "@seoyeon_onset",
		"avatar": "res://assets/icons/s_chat/avatars/seo_yeon_han.png",
		"popularity": 1.62,
	},
	"npc_sofia_marin": {
		"display_name": "Sofia Marin",
		"handle": "@sofiaonwheels",
		"avatar": "res://assets/icons/s_chat/avatars/sofia_marin.png",
		"popularity": 1.08,
	},
}

static var _loaded := false
static var _posts: Array[Dictionary] = []


static func get_posts() -> Array[Dictionary]:
	_ensure_loaded()
	var posts_by_npc: Dictionary = {}
	for post: Dictionary in _posts:
		var npc_id := str(post.get("npc_id", ""))
		if not posts_by_npc.has(npc_id):
			posts_by_npc[npc_id] = []
		(posts_by_npc[npc_id] as Array).append(post.duplicate(true))
	for npc_id: Variant in posts_by_npc:
		(posts_by_npc[npc_id] as Array).shuffle()
	return _interleave_post_buckets(posts_by_npc)


static func _interleave_post_buckets(posts_by_npc: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active_npc_ids: Array = posts_by_npc.keys()
	active_npc_ids.shuffle()
	var previous_npc_id := ""
	while not active_npc_ids.is_empty():
		var largest_bucket_size := -1
		var candidates: Array = []
		for npc_id_value: Variant in active_npc_ids:
			var npc_id := str(npc_id_value)
			if npc_id == previous_npc_id and active_npc_ids.size() > 1:
				continue
			var bucket_size := (posts_by_npc[npc_id] as Array).size()
			if bucket_size > largest_bucket_size:
				largest_bucket_size = bucket_size
				candidates = [npc_id]
			elif bucket_size == largest_bucket_size:
				candidates.append(npc_id)
		candidates.shuffle()
		var selected_npc_id := str(candidates[0])
		var selected_bucket := posts_by_npc[selected_npc_id] as Array
		result.append(selected_bucket.pop_back() as Dictionary)
		if selected_bucket.is_empty():
			active_npc_ids.erase(selected_npc_id)
		previous_npc_id = selected_npc_id
	return result


static func get_profile(npc_id: String) -> Dictionary:
	var profile_value: Variant = NPC_PROFILES.get(npc_id, {})
	if profile_value is Dictionary and not (profile_value as Dictionary).is_empty():
		return (profile_value as Dictionary).duplicate(true)
	return {
		"display_name": npc_id.replace("npc_", "").replace("_", " "),
		"handle": "@unknown",
		"avatar": DEFAULT_AVATAR_PATH,
		"popularity": 0.65,
	}


static func get_avatar_path(npc_id: String) -> String:
	return str(get_profile(npc_id).get("avatar", DEFAULT_AVATAR_PATH))


static func get_engagement(post: Dictionary) -> Dictionary:
	var value: Variant = post.get("engagement", {})
	if not value is Dictionary:
		return {"likes": 0, "comments": 0, "reposts": 0}
	var engagement := value as Dictionary
	return {
		"likes": maxi(0, int(engagement.get("likes", 0))),
		"comments": maxi(0, int(engagement.get("comments", 0))),
		"reposts": maxi(0, int(engagement.get("reposts", 0))),
	}


static func get_image_paths(post: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var images_value: Variant = post.get("images", [])
	if images_value is Array:
		for image_value: Variant in images_value:
			if image_value is String:
				_append_existing_image_path(result, image_value as String)
	if result.is_empty():
		var legacy_image_value: Variant = post.get("image", null)
		if legacy_image_value is String:
			_append_existing_image_path(result, legacy_image_value as String)
	return result


static func _append_existing_image_path(result: Array[String], image_path: String) -> void:
	var normalized_path := image_path.strip_edges()
	if not normalized_path.is_empty() and ResourceLoader.exists(normalized_path):
		result.append(normalized_path)


static func format_count(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(POSTS_PATH, FileAccess.READ)
	if file == null:
		push_error("s.chat posts are missing: %s" % POSTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("s.chat posts contain invalid JSON: %s" % POSTS_PATH)
		return
	var posts_value: Variant = (parsed as Dictionary).get("posts", [])
	if not posts_value is Array:
		return
	for post_value: Variant in posts_value:
		if post_value is Dictionary:
			var post := (post_value as Dictionary).duplicate(true)
			if not str(post.get("post_id", "")).is_empty():
				_posts.append(post)
