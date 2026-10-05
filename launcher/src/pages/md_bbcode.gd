class_name MdBbcode
extends RefCounted
## Small Markdown to RichTextLabel (BBCode) converter for the patch notes page.
##
## Supports: # / ## / ### headings, "-" / "*" bullets with nesting (2 spaces
## per level), "1." numbered lists, **bold**, *italic*, `code`, fenced code
## blocks, > quotes, --- rules, [text](https://url) links and
## ![alt](path) images. Hard-wrapped lines of one paragraph are joined.
## Square brackets in the source are escaped, so notes can never inject tags.
## Images are only embedded when the file exists (res:// or relative to
## `base_dir`); otherwise the alt text is shown in italics.
##
## Example:
##   rich.text = MdBbcode.convert("## Hi\n- **one**\n- `two`", UiKit.tokens())

const H1_SIZE: int = 26
const H2_SIZE: int = 20
const H3_SIZE: int = 16
## Longest image edge shown in the page (px).
const IMG_MAX_W: int = 560


## Converts `md` to BBCode. `t` supplies the colours (null = the default dark
## palette). `base_dir` is where relative image paths are looked up.
static func convert(md: String, t: UiKitTokens = null, base_dir: String = "") -> String:
	var pal: UiKitTokens = t if t != null else UiKitTokens.new()
	var out: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = md.replace("\r", "").split("\n")
	var para: PackedStringArray = PackedStringArray()
	var list_depth: int = 0
	var list_kinds: Array[String] = []
	var in_fence: bool = false
	var fence: PackedStringArray = PackedStringArray()
	var last_item: int = -1
	for raw in lines:
		var s: String = raw
		var stripped: String = s.strip_edges()
		if stripped.begins_with("```"):
			if in_fence:
				out.append("[bgcolor=%s][color=%s][code]%s[/code][/color][/bgcolor]" % [_hex(pal.panel_sunken), _hex(pal.text), _esc("\n".join(fence))])
				fence = PackedStringArray()
			else:
				_flush_para(out, para, pal, base_dir)
				para = PackedStringArray()
				_close_lists(out, list_kinds)
				list_depth = 0
				last_item = -1
			in_fence = not in_fence
			continue
		if in_fence:
			fence.append(s)
			continue
		var bullet: Dictionary = _bullet_of(s)
		if not bullet.is_empty():
			_flush_para(out, para, pal, base_dir)
			para = PackedStringArray()
			var level: int = int(bullet["level"])
			var kind: String = String(bullet["kind"])
			var closing: String = ""
			while list_kinds.size() > level + 1 or (list_kinds.size() == level + 1 and list_kinds[level] != kind):
				closing += "[/%s]" % list_kinds.pop_back()
			if closing != "" and last_item >= 0:
				out[last_item] += closing
			var opening: String = ""
			while list_kinds.size() < level + 1:
				opening += "[ul bullet=•]" if kind == "ul" else "[ol type=1]"
				list_kinds.append(kind)
			out.append(opening + _inline(String(bullet["text"]), pal, base_dir))
			last_item = out.size() - 1
			list_depth = list_kinds.size()
			continue
		if stripped == "":
			_flush_para(out, para, pal, base_dir)
			para = PackedStringArray()
			if list_depth > 0 and not s.begins_with(" "):
				_close_lists(out, list_kinds)
				list_depth = 0
				last_item = -1
			continue
		if list_depth > 0 and s.begins_with(" ") and last_item >= 0:
			# Continuation line of a list item.
			out[last_item] += " " + _inline(stripped, pal, base_dir)
			continue
		if list_depth > 0:
			_close_lists(out, list_kinds)
			list_depth = 0
			last_item = -1
		if stripped.begins_with("#"):
			_flush_para(out, para, pal, base_dir)
			para = PackedStringArray()
			out.append(_heading(stripped, pal, base_dir))
		elif stripped.begins_with("---") and stripped.replace("-", "") == "":
			_flush_para(out, para, pal, base_dir)
			para = PackedStringArray()
			out.append("[color=%s]%s[/color]" % [_hex(pal.line_strong), "─".repeat(40)])
		elif stripped.begins_with(">"):
			_flush_para(out, para, pal, base_dir)
			para = PackedStringArray()
			out.append("[indent][color=%s][i]%s[/i][/color][/indent]" % [_hex(pal.text_dim), _inline(stripped.substr(1).strip_edges(), pal, base_dir)])
		else:
			para.append(stripped)
	if in_fence:
		out.append("[code]%s[/code]" % _esc("\n".join(fence)))
	_flush_para(out, para, pal, base_dir)
	_close_lists(out, list_kinds)
	return "\n".join(out)


static func _close_lists(out: PackedStringArray, kinds: Array[String]) -> void:
	if kinds.is_empty() or out.is_empty():
		kinds.clear()
		return
	while not kinds.is_empty():
		out[out.size() - 1] += "[/%s]" % kinds.pop_back()


static func _flush_para(out: PackedStringArray, para: PackedStringArray, t: UiKitTokens, base_dir: String) -> void:
	if para.is_empty():
		return
	if not out.is_empty():
		out.append("")
	out.append(_inline(" ".join(para), t, base_dir))


static func _heading(line: String, t: UiKitTokens, base_dir: String) -> String:
	var n: int = 0
	while n < line.length() and line[n] == "#":
		n += 1
	var text: String = _inline(line.substr(n).strip_edges(), t, base_dir)
	match n:
		1:
			return "\n[font_size=%d][color=%s][b]%s[/b][/color][/font_size]" % [H1_SIZE, _hex(t.accent_hi), text]
		2:
			return "\n[font_size=%d][color=%s][b]%s[/b][/color][/font_size]" % [H2_SIZE, _hex(t.accent), text]
		_:
			return "\n[font_size=%d][color=%s][b]%s[/b][/color][/font_size]" % [H3_SIZE, _hex(t.text), text]


## {"level": int, "kind": "ul"|"ol", "text": String} for a list line, else {}.
static func _bullet_of(line: String) -> Dictionary:
	var indent: int = 0
	while indent < line.length() and line[indent] == " ":
		indent += 1
	var rest: String = line.substr(indent)
	var level: int = indent / 2
	if rest.begins_with("- ") or rest.begins_with("* "):
		return {"level": level, "kind": "ul", "text": rest.substr(2)}
	var dot: int = rest.find(". ")
	if dot > 0 and dot <= 3 and rest.substr(0, dot).is_valid_int():
		return {"level": level, "kind": "ol", "text": rest.substr(dot + 2)}
	return {}


## Inline spans of one line: bold, italic, code, links, images.
static func _inline(s: String, t: UiKitTokens, base_dir: String) -> String:
	var res: String = ""
	var bold: bool = false
	var ital: bool = false
	var i: int = 0
	while i < s.length():
		var c: String = s[i]
		if c == "`":
			var end: int = s.find("`", i + 1)
			if end > i:
				res += "[bgcolor=%s][color=%s][code]%s[/code][/color][/bgcolor]" % [_hex(t.panel_raised), _hex(t.accent_hi), _esc(s.substr(i + 1, end - i - 1))]
				i = end + 1
				continue
		if c == "!" and s.substr(i, 2) == "![":
			var img: Dictionary = _link_at(s, i + 1)
			if not img.is_empty():
				res += _image(String(img["text"]), String(img["target"]), t, base_dir)
				i = int(img["end"])
				continue
		if c == "[":
			var lk: Dictionary = _link_at(s, i)
			if not lk.is_empty():
				var target: String = String(lk["target"])
				if target.begins_with("https://") or target.begins_with("http://"):
					res += "[color=%s][url=%s]%s[/url][/color]" % [_hex(t.accent), target.replace("[", "").replace("]", ""), _esc(String(lk["text"]))]
				else:
					res += _esc(String(lk["text"]))
				i = int(lk["end"])
				continue
		if s.substr(i, 2) == "**":
			res += "[/b]" if bold else "[b]"
			bold = not bold
			i += 2
			continue
		if c == "*" and (ital or (i + 1 < s.length() and s[i + 1] != " " and s[i + 1] != "*")):
			res += "[/i]" if ital else "[i]"
			ital = not ital
			i += 1
			continue
		res += _esc(c)
		i += 1
	if ital:
		res += "[/i]"
	if bold:
		res += "[/b]"
	return res


## Parses "[text](target)" at `at`; {} when it is not one. `end` = index after ")".
static func _link_at(s: String, at: int) -> Dictionary:
	if at >= s.length() or s[at] != "[":
		return {}
	var close: int = s.find("](", at)
	if close < 0:
		return {}
	var paren: int = s.find(")", close + 2)
	if paren < 0:
		return {}
	return {"text": s.substr(at + 1, close - at - 1), "target": s.substr(close + 2, paren - close - 2).strip_edges(), "end": paren + 1}


static func _image(alt: String, src: String, _t: UiKitTokens, base_dir: String) -> String:
	var path: String = src
	if not (src.begins_with("res://") or src.begins_with("user://")):
		path = base_dir.path_join(src) if base_dir != "" else ""
	if path != "" and not src.contains("..") and ResourceLoader.exists(path):
		return "[img width=%d]%s[/img]" % [IMG_MAX_W, path]
	return "[i]%s[/i]" % _esc(alt if alt != "" else "image")


static func _esc(s: String) -> String:
	return s.replace("]", "\u0001").replace("[", "[lb]").replace("\u0001", "[rb]")


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)
