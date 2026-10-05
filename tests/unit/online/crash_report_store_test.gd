extends GdUnitTestSuite
## W15 crash reports, server side: CrashReportStore size / rate limits,
## 30-day retention, folder cap, owner-only files, nothing personal added.

const DIR := "user://test_crash_reports"
const NOW := 1_800_000_000


func before_test() -> void:
	_wipe()


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


func _rules() -> OnlineRulesDef:
	var r := OnlineRulesDef.new()
	r.crash_max_bytes = 4096
	r.crash_per_ip_per_hour = 2
	r.crash_per_account_per_day = 3
	r.crash_retention_days = 30
	r.crash_dir_cap_mb = 1
	return r


static func _report(extra: String = "") -> PackedByteArray:
	return JSON.stringify({"kind": "crash", "exit_code": 11, "files": {"system.json": "{}", "x": extra}}) \
		.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


func test_accepts_a_valid_report_and_adds_nothing() -> void:
	var st := CrashReportStore.new(DIR, _rules())
	assert_int(st.accept(_report(), "a:198.51.100.4", "0123456789abcdef0123456789abcdef", NOW)).is_equal(CrashReportStore.Result.OK)
	assert_int(st.count()).is_equal(1)
	var d := ProjectSettings.globalize_path(DIR)
	var f: String = DirAccess.get_files_at(d)[0]
	var body := FileAccess.get_file_as_bytes(d.path_join(f)).decompress_dynamic(1 << 20, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	assert_bool(body.contains("198.51.100.4") or body.contains("0123456789abcdef") or f.contains("198")).is_false()
	if OS.get_name() == "Linux":
		assert_int(FileAccess.get_unix_permissions(d.path_join(f)) & 63).is_equal(0)


func test_rejects_too_big_and_malformed() -> void:
	var st := CrashReportStore.new(DIR, _rules())
	var big := Crypto.new().generate_random_bytes(5000)
	assert_int(st.accept(big, "a:1", "", NOW)).is_equal(CrashReportStore.Result.TOO_BIG)
	assert_int(st.accept("not gzip".to_utf8_buffer(), "a:1", "", NOW)).is_equal(CrashReportStore.Result.MALFORMED)
	var other := JSON.stringify({"kind": "spam"}).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	assert_int(st.accept(other, "a:1", "", NOW)).is_equal(CrashReportStore.Result.MALFORMED)
	assert_int(st.count()).is_equal(0)


func test_rate_limit_per_ip_per_hour() -> void:
	var st := CrashReportStore.new(DIR, _rules())
	assert_int(st.accept(_report(), "a:1", "", NOW)).is_equal(CrashReportStore.Result.OK)
	assert_int(st.accept(_report(), "a:1", "", NOW + 1)).is_equal(CrashReportStore.Result.OK)
	assert_int(st.accept(_report(), "a:1", "", NOW + 2)).is_equal(CrashReportStore.Result.RATE_LIMITED)
	assert_int(st.accept(_report(), "a:2", "", NOW + 2)).is_equal(CrashReportStore.Result.OK)
	assert_int(st.accept(_report(), "a:1", "", NOW + 3601)).is_equal(CrashReportStore.Result.OK)


func test_rate_limit_per_account_per_day() -> void:
	var st := CrashReportStore.new(DIR, _rules())
	var acc := "fedcba9876543210fedcba9876543210"
	for i in 3:
		assert_int(st.accept(_report(), "a:%d" % i, acc, NOW + i)).is_equal(CrashReportStore.Result.OK)
	assert_int(st.accept(_report(), "a:9", acc, NOW + 10)).is_equal(CrashReportStore.Result.RATE_LIMITED)
	assert_int(st.accept(_report(), "a:9", acc, NOW + 86401)).is_equal(CrashReportStore.Result.OK)


func test_retention_deletes_after_30_days() -> void:
	var st := CrashReportStore.new(DIR, _rules())
	st.accept(_report(), "a:1", "", NOW)
	st.accept(_report(), "a:2", "", NOW + 20 * 86400)
	assert_int(st.sweep(NOW + 30 * 86400)).is_equal(0)
	assert_int(st.sweep(NOW + 30 * 86400 + 1)).is_equal(1)
	assert_int(st.count()).is_equal(1)


func test_folder_cap_drops_oldest() -> void:
	var r := _rules()
	r.crash_max_bytes = 1048576
	r.crash_per_ip_per_hour = 100
	var st := CrashReportStore.new(DIR, r)
	var noise := Crypto.new().generate_random_bytes(300000).hex_encode().left(400000)  # incompressible-ish
	for i in 6:
		assert_int(st.accept(_report(noise), "a:1", "", NOW + i)).is_equal(CrashReportStore.Result.OK)
	var total := 0
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		total += FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(DIR).path_join(f)).size()
	assert_int(total).is_less_equal(1048576)
	assert_int(st.count()).is_less(6)
