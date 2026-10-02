class_name HudLayout
extends RefCounted
## Resolution independence (design/ux/hud.md §3.2, §15, §16): the HUD is laid
## out once in design units and scaled. `compute` returns the screen region the
## HUD occupies (16:9 centre region on ultrawide unless "native" aspect) and the
## scale from design units to pixels:
##   base  = min(region.w / design.w, region.h / design.h)
##   floor = min(min_scale, region.w / min_design.w, region.h / min_design.h)
##   scale = max(base, floor) * ui_scale
## so 1080p = 1.0, 1440p = 1.33, 720p = 0.9 (never below the 720p text floor),
## and tiny windows shrink instead of overlapping.

const ASPECT_16_9: float = 16.0 / 9.0


class Result:
	extends RefCounted
	## Screen-space rectangle (pixels) the HUD root covers.
	var region: Rect2
	## Design units -> pixels.
	var scale: float = 1.0
	## The HUD root size in design units (region.size / scale).
	var canvas: Vector2


static func compute(viewport: Vector2, ui_scale: float, clamp_16_9: bool, tuning: HudTuningDef) -> Result:
	var r := Result.new()
	var size := Vector2(maxf(viewport.x, 1.0), maxf(viewport.y, 1.0))
	var region := Rect2(Vector2.ZERO, size)
	if clamp_16_9 and size.x / size.y > ASPECT_16_9 + 0.01:
		var w := size.y * ASPECT_16_9
		region = Rect2(Vector2((size.x - w) * 0.5, 0.0), Vector2(w, size.y))
	var d := tuning.design_size
	var md := tuning.min_design_size
	var base := minf(region.size.x / d.x, region.size.y / d.y)
	var floor_s := minf(tuning.min_scale, minf(region.size.x / md.x, region.size.y / md.y))
	r.region = region
	r.scale = maxf(base, floor_s) * clampf(ui_scale, 0.5, 2.0)
	r.canvas = region.size / r.scale
	return r
