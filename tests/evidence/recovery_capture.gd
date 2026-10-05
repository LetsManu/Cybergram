extends Node
## Evidence capture for W21-N1 (tools/ci/capture_scene.sh): the main menu with
##   --view forgot   the login screen's "Forgot password?" page (filled in)
##   --view code     the show-once recovery code dialog over the login screen
##   --view profile  the account screen of an older account ("No recovery code yet")
## Fixture data only; no server. Until the lead appends the W21-N1 rows to
## hud.csv, they are loaded here from production/qa/evidence/w21-n1/hud_rows.txt.

const ROWS := "res://production/qa/evidence/w21-n1/hud_rows.txt"

var _view := "forgot"
var _menu: MainMenu


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view = args[i + 1]
	_load_rows()
	_menu = (load("res://src/ui/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(_menu)
	await get_tree().process_frame
	_menu._col.visible = false
	if _view == "profile":
		var ps := ProfileScreen.new()
		ps.session = {"token": "", "id": ProfileFixtures.id(0x3c), "username": "neo_runner", "display_name": "Neo",
			"emblem": 3, "accent": 1, "favourite_hero": "brannoc", "guest": 0}
		_menu._center.add_child(ps)
		await get_tree().process_frame
		ps.on_result({"op": AccountCodec.OP_RECOVERY_INFO, "code": 0, "has_code": 0})
		return
	var ls := LoginScreen.new()
	ls.server_text = tr("HUD_LOGIN_SERVER") % ["cyber.djboeck.at:7777", tr("HUD_LOGIN_ENCRYPTED")]
	ls.remembered_username = "neo_runner"
	_menu._center.add_child(ls)
	await get_tree().process_frame
	if _view == "forgot":
		ls.open_recover()
		ls.fill_recover("neo_runner", "7KQ2M-X4D9P-0RTB8-HV3NC", "a new password")
		ls.show_error(LoginScreen.result_text(AccountCodec.OP_RECOVER, AccountCodec.E_CREDENTIALS))
	else:
		ls.set_mode(LoginScreen.Mode.REGISTER)
		RecoveryCodeDialog.show_if_issued(self, {"op": AccountCodec.OP_REGISTER, "code": 0,
			"recovery_code": "7KQ2M-X4D9P-0RTB8-HV3NC"})


func _load_rows() -> void:
	var tr_ := Translation.new()
	tr_.locale = "en"
	var f := FileAccess.open(ROWS, FileAccess.READ)
	if f == null:
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and TranslationServer.translate(row[0]) == row[0]:
			tr_.add_message(row[0], row[1])
	TranslationServer.add_translation(tr_)
