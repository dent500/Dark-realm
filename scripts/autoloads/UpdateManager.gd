## UpdateManager.gd
## Manages game versions, checks for remote updates, and loads patch resource packs (.pck).
extends Node

signal update_check_completed(has_update: bool, latest_version: String, patch_url: String)
signal download_progress(received_bytes: int, total_bytes: int)
signal download_completed(success: bool)

const CURRENT_VERSION = "1.0.0"
# Replace this with your actual version JSON URL (e.g., GitHub Raw link)
const UPDATE_URL = "https://raw.githubusercontent.com/Bugs/Dark-Realm/main/version.json"
const PATCH_DIR = "user://updates/"

var _http_request: HTTPRequest
var _download_request: HTTPRequest

var latest_version_info: Dictionary = {}
var is_update_available: bool = false

func _ready() -> void:
	# 1. Ensure patch directory exists
	if not DirAccess.dir_exists_absolute(PATCH_DIR):
		DirAccess.make_dir_absolute(PATCH_DIR)
	
	# 2. Load existing patches immediately on startup
	_load_installed_patches()
	
	# 3. Setup HTTP nodes
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_update_check_request_completed)
	
	_download_request = HTTPRequest.new()
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_completed)
	
	# Automatically check for updates after a short delay (so UI is ready)
	await get_tree().create_timer(1.0).timeout
	check_for_updates()

## Loops through the user patch directory and loads any .pck files found.
func _load_installed_patches() -> void:
	var dir = DirAccess.open(PATCH_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".pck"):
				var patch_path = PATCH_DIR + file_name
				print("[UpdateManager] Loading patch: ", patch_path)
				var success = ProjectSettings.load_resource_pack(patch_path)
				if success:
					print("[UpdateManager] Patch loaded successfully!")
				else:
					print("[UpdateManager] Failed to load patch: ", patch_path)
			file_name = dir.get_next()

func check_for_updates() -> void:
	print("[UpdateManager] Checking for updates at: ", UPDATE_URL)
	var err = _http_request.request(UPDATE_URL)
	if err != OK:
		print("[UpdateManager] HTTP Request failed: ", err)
		update_check_completed.emit(false, CURRENT_VERSION, "")

func _on_update_check_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[UpdateManager] Update check failed with code: ", response_code)
		update_check_completed.emit(false, CURRENT_VERSION, "")
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json is Dictionary:
		latest_version_info = json
		var latest_v = json.get("version", CURRENT_VERSION)
		var patch_url = json.get("patch_url", "")
		
		is_update_available = _is_version_newer(latest_v, CURRENT_VERSION)
		print("[UpdateManager] Latest Version: ", latest_v, " (Available: ", is_update_available, ")")
		update_check_completed.emit(is_update_available, latest_v, patch_url)
	else:
		print("[UpdateManager] Failed to parse version JSON.")
		update_check_completed.emit(false, CURRENT_VERSION, "")

func download_patch(url: String) -> void:
	if url.is_empty(): return
	
	var file_name = url.get_file()
	if not file_name.ends_with(".pck"):
		file_name += ".pck"
	
	var save_path = PATCH_DIR + file_name
	print("[UpdateManager] Downloading patch to: ", save_path)
	
	_download_request.download_file = save_path
	var err = _download_request.request(url)
	if err != OK:
		print("[UpdateManager] Download failed to start: ", err)
		download_completed.emit(false)

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var success = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	print("[UpdateManager] Download finished. Success: ", success)
	download_completed.emit(success)

func _is_version_newer(latest: String, current: String) -> bool:
	var v_latest = latest.split(".")
	var v_current = current.split(".")
	
	for i in range(min(v_latest.size(), v_current.size())):
		if v_latest[i].to_int() > v_current[i].to_int():
			return true
		if v_latest[i].to_int() < v_current[i].to_int():
			return false
	
	return v_latest.size() > v_current.size()
