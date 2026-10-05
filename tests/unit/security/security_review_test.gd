extends GdUnitTestSuite
## Regression tests for the W11-Q1 security review
## (docs/security/review-2026-10-05.md). One test (or more) per fixed finding.


# SEC-001: an account session token never travels over plain UDP.
func test_sec001_account_token_never_sent_on_plain_link() -> void:
	assert_bool(MainMenu.may_send_token(false, false)).is_false()
	assert_bool(MainMenu.may_send_token(true, false)).is_true()
	# Guest tokens carry no account: they may resume on a guest-only server.
	assert_bool(MainMenu.may_send_token(false, true)).is_true()


# SEC-005: --dtls-insecure has no effect in a release export.
func test_sec005_dtls_insecure_ignored_in_release() -> void:
	var rel := AuthConfig.parse(PackedStringArray(["--dtls-insecure"]), {}, 0)
	assert_bool(rel.insecure).is_false()
	assert_bool(rel.client_tls_for("cyber.djboeck.at").is_unsafe_client()).is_false()
	var dbg := AuthConfig.parse(PackedStringArray(["--dtls-insecure"]), {}, 1)
	assert_bool(dbg.insecure).is_true()
