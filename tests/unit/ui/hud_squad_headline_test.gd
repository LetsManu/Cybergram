extends GdUnitTestSuite
## Polish sprint 2026-10-05: the squad headline names what the squad is really
## doing. Before, it always showed the first pip's command (e.g. FOLLOW) even
## while every Wardling was returning or dissolving.


func _pip(command: int, returning: bool, dissolving: bool) -> WardlingPresenter.SquadPip:
	var p := WardlingPresenter.SquadPip.new()
	p.command = command
	p.flags = WardlingSim.FLAG_RETURNING if returning else 0
	p.dissolving = dissolving
	return p


func test_all_dissolving_reads_dissolving() -> void:
	assert_str(SquadStrip.headline_key([_pip(1, false, true), _pip(1, false, true)])).is_equal("HUD_SQ_DISSOLVING")


func test_all_alive_returning_reads_returning() -> void:
	assert_str(SquadStrip.headline_key([_pip(2, true, false), _pip(2, true, false), _pip(2, false, true)])) \
		.is_equal("HUD_SQ_RETURNING")


func test_mixed_squad_reads_the_command_of_the_first_live_pip() -> void:
	assert_str(SquadStrip.headline_key([_pip(1, false, true), _pip(3, false, false), _pip(3, true, false)])) \
		.is_equal("HUD_CMD_ATTACK")
