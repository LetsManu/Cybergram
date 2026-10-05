extends GdUnitTestSuite
## W15 parties: PartyService (invite / accept / decline / leave, leader
## hand-over, size cap, invite expiry) and the game's party-join decision.

const A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const C := "cccccccccccccccccccccccccccccccc"
const D := "dddddddddddddddddddddddddddddddd"


func test_invite_accept_makes_a_party_with_the_inviter_as_leader() -> void:
	var ps := PartyService.new(3, 120.0)
	assert_int(ps.invite(A, B, 0.0)).is_equal(PartyService.OK)
	assert_array(ps.state_of(B, 1.0).invites_in).contains([A])
	assert_array(ps.state_of(A, 1.0).invites_out).contains([B])
	assert_int(ps.accept(B, A, 1.0)).is_equal(PartyService.OK)
	var st := ps.state_of(B, 2.0)
	assert_str(st.leader).is_equal(A)
	assert_array(st.members).contains_exactly([A, B])
	assert_array(ps.mates_of(B)).contains_exactly([A])
	assert_array(st.invites_in).is_empty()


func test_size_cap_and_self_invite() -> void:
	var ps := PartyService.new(2, 120.0)
	assert_int(ps.invite(A, A, 0.0)).is_equal(PartyService.E_BAD)
	ps.invite(A, B, 0.0)
	ps.accept(B, A, 0.0)
	assert_int(ps.invite(A, C, 0.0)).is_equal(PartyService.E_FULL)


func test_invite_expires_and_decline() -> void:
	var ps := PartyService.new(3, 120.0)
	ps.invite(A, B, 0.0)
	assert_int(ps.accept(B, A, 121.0)).is_equal(PartyService.E_NO_INVITE)
	ps.invite(A, C, 200.0)
	ps.decline(C, A)
	assert_int(ps.accept(C, A, 201.0)).is_equal(PartyService.E_NO_INVITE)
	assert_dict(ps.parties).is_empty()


func test_leader_leaves_hands_over_and_last_member_dissolves() -> void:
	var ps := PartyService.new(3, 120.0)
	ps.invite(A, B, 0.0)
	ps.accept(B, A, 0.0)
	ps.invite(B, C, 0.0)  # a member may invite too
	ps.accept(C, B, 0.0)
	assert_array(ps.state_of(C, 0.0).members).contains_exactly([A, B, C])
	ps.leave(A)
	assert_str(ps.state_of(B, 0.0).leader).is_equal(B)
	ps.forget(C)
	assert_dict(ps.parties).is_empty()
	assert_str(ps.state_of(B, 0.0).party).is_equal("")


func test_joining_another_party_leaves_the_old_one() -> void:
	var ps := PartyService.new(3, 120.0)
	ps.invite(A, B, 0.0)
	ps.accept(B, A, 0.0)
	ps.invite(D, B, 0.0)
	ps.accept(B, D, 0.0)
	assert_array(ps.state_of(B, 0.0).members).contains_exactly([D, B])
	assert_str(ps.state_of(A, 0.0).party).is_equal("")


func test_game_joins_only_a_real_party() -> void:
	var one := {"members": [{"kind": AccountCodec.PARTY_LEADER}, {"kind": AccountCodec.PARTY_INVITE_OUT}]}
	var two := {"members": [{"kind": AccountCodec.PARTY_LEADER}, {"kind": AccountCodec.PARTY_MEMBER}]}
	assert_bool(MainMenu.should_join_party(one)).is_false()
	assert_bool(MainMenu.should_join_party(two)).is_true()
	assert_bool(MainMenu.should_join_party({})).is_false()
