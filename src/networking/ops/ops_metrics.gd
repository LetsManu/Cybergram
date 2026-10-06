class_name OpsMetrics
extends RefCounted
## Counters and gauges of one server process in Prometheus text format (P1,
## docs/monitoring.md). Counters only grow; gauges are set by whoever renders
## (the front fills them from its live state right before `render()`).
## Anonymous numbers only: no ids, no names (labels are queue ids, states).
##
## Example:
##   metrics.inc("cybergram_ready_checks_total", {"outcome": "accepted"})
##   metrics.set_gauge("cybergram_queue_players", 4, {"queue": "normal_5v5"})
##   var text := metrics.render()

## name -> {help, type}
var _meta: Dictionary = {}
## name -> {label string -> value}
var _values: Dictionary = {}


## Declares a metric (help text and type "counter" / "gauge"). Optional:
## undeclared metrics render as untyped.
func describe(name: String, type: String, help: String) -> void:
	_meta[name] = {"type": type, "help": help}


func inc(name: String, labels: Dictionary = {}, by: float = 1.0) -> void:
	var m: Dictionary = _values.get_or_add(name, {})
	var k := _labels(labels)
	m[k] = float(m.get(k, 0.0)) + by


func set_gauge(name: String, value: float, labels: Dictionary = {}) -> void:
	(_values.get_or_add(name, {}) as Dictionary)[_labels(labels)] = value


## Drops every value of a gauge (before re-filling one with per-label values).
func clear(name: String) -> void:
	_values.erase(name)


func value(name: String, labels: Dictionary = {}) -> float:
	return float((_values.get(name, {}) as Dictionary).get(_labels(labels), 0.0))


## Prometheus exposition text (version 0.0.4).
func render() -> String:
	var names := _values.keys()
	names.sort()
	var out := PackedStringArray()
	for n: String in names:
		var meta: Dictionary = _meta.get(n, {})
		if not meta.is_empty():
			out.append("# HELP %s %s" % [n, meta.help])
			out.append("# TYPE %s %s" % [n, meta.type])
		var series: Dictionary = _values[n]
		var keys := series.keys()
		keys.sort()
		for k: String in keys:
			out.append("%s%s %s" % [n, k, _num(float(series[k]))])
	return "\n".join(out) + "\n"


static func _labels(labels: Dictionary) -> String:
	if labels.is_empty():
		return ""
	var keys := labels.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var v := str(labels[k]).replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
		parts.append("%s=\"%s\"" % [k, v])
	return "{" + ",".join(parts) + "}"


static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)) and absf(v) < 1.0e15:
		return str(int(roundf(v)))
	return "%.6f" % v
