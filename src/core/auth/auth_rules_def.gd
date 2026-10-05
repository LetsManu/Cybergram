class_name AuthRulesDef
extends Resource
## Server account rules (data: assets/data/net/auth_rules.tres), see
## design/ux/lobby-and-social.md §6. Tuning lives here, not in code.

## PBKDF2-HMAC-SHA256 rounds for new / changed passwords (stored per account,
## so raising it later does not break old hashes).
@export_range(1000, 2000000) var pbkdf2_iterations: int = 60000
@export_range(8, 64) var salt_bytes: int = 16
@export_range(8, 128) var password_min: int = 8
@export_range(16, 128) var password_max: int = 64
## Failed logins allowed per account / per connection inside the window,
## then the account / connection is locked for lockout_s.
@export_range(1, 100) var max_failures_per_account: int = 5
@export_range(1, 100) var max_failures_per_peer: int = 10
@export_range(1.0, 3600.0) var failure_window_s: float = 300.0
@export_range(1.0, 86400.0) var lockout_s: float = 300.0
## Session token lifetime after the connection is gone (the lobby -> match ->
## lobby handover and short reconnects re-use it); then it is dropped.
@export_range(5.0, 600.0) var session_grace_s: float = 60.0
## Accounts not logged into for this many days are deleted (GDPR retention).
@export_range(30, 3650) var retention_days: int = 365
## Registration needs this minimum age (Austria, GDPR Art. 8: 14).
@export_range(13, 18) var min_age: int = 14
## Most accounts the store will hold (registration is refused beyond).
@export_range(10, 1000000) var max_accounts: int = 50000
@export_range(1, 500) var max_friends: int = 200
@export_range(1, 200) var max_pending_requests: int = 50
@export_range(1, 500) var max_blocks: int = 200
## W21-N1 recovery code (PRIVACY.md: only its PBKDF2 hash is stored): groups
## of Crockford base32 characters (5 bit each), e.g. 4 x 5 = 100 bit.
@export_range(2, 8) var recovery_groups: int = 4
@export_range(4, 8) var recovery_group_len: int = 5
## Admin reset requests (AccountAdmin): the running server looks into its
## admin folder this often, and the admin tool waits this long for it.
@export_range(0.5, 60.0) var admin_poll_s: float = 2.0
@export_range(1.0, 120.0) var admin_wait_s: float = 15.0
