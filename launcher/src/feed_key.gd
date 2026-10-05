class_name FeedKey
extends RefCounted
## Public key (PEM, ECDSA P-256) that signs the update feed (version.json ->
## version.json.sig). Empty = this launcher was built without a pinned key and
## accepts an unsigned feed with a warning (see LauncherCore.verify_feed and
## docs/security/review-2026-10-05.md SEC-010).
##
## The release workflow (.github/workflows/build.yml) fills this in from the
## FEED_SIGNING_KEY secret before exporting the launcher. The owner may also
## commit the public key here once, so it is pinned in the repository:
##   openssl ec -in feed_signing_key.pem -pubout
const PEM: String = ""
