class_name SystemCheck
extends RefCounted
## First-run / on-demand system check. Local only: it reads what the OS tells
## this process and sends nothing anywhere. Rules for the recommended preset
## are in recommend() and in launcher/src/syscheck/README.md.

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const INTEGRATED_HINTS: Array[String] = ["intel", "uhd", "iris", "radeon graphics", "radeon(tm) graphics",
		"vega 3", "vega 6", "vega 7", "vega 8", "vega 10", "vega 11", "apple", "mali", "adreno", "vc4", "v3d"]
const SOFTWARE_HINTS: Array[String] = ["llvmpipe", "softpipe", "swiftshader", "basic render", "software", "lavapipe", "microsoft basic"]
const HIGH_END_HINTS: Array[String] = ["rtx 40", "rtx 50", "rtx 3080", "rtx 3090", "rx 7", "rx 9", "rx 6800", "rx 6900"]


## What this machine reports: {os, gpu, driver, renderer, vulkan, ram_mb}.
static func gather() -> Dictionary:
	var drv: PackedStringArray = OS.get_video_adapter_driver_info()
	var ram: int = int(OS.get_memory_info().get("physical", -1))
	var vk: bool = vulkan_present(OS.get_name())
	return {
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"driver": " ".join(drv) if drv.size() > 0 else "unknown",
		"renderer": renderer_label(vk, RenderingServer.get_video_adapter_name()),
		"vulkan": vk,
		"ram_mb": ram / 1048576 if ram > 0 else -1,
	}


## True when a Vulkan runtime appears to be installed (the game renders with
## Vulkan; the launcher itself uses OpenGL, so it cannot ask the GPU directly).
static func vulkan_present(os_name: String) -> bool:
	match os_name:
		"Windows":
			return FileAccess.file_exists("C:/Windows/System32/vulkan-1.dll")
		"Linux":
			for p in ["/usr/lib/x86_64-linux-gnu/libvulkan.so.1", "/usr/lib64/libvulkan.so.1", "/usr/lib/libvulkan.so.1"]:
				if FileAccess.file_exists(p):
					return true
	return false


static func renderer_label(vulkan: bool, gpu: String) -> String:
	if is_software(gpu):
		return "Software rendering (no GPU driver)"
	return "Vulkan" if vulkan else "OpenGL fallback (Vulkan not found)"


static func is_software(gpu: String) -> bool:
	var g: String = gpu.to_lower()
	for h in SOFTWARE_HINTS:
		if g.contains(h):
			return true
	return false


static func is_integrated(gpu: String) -> bool:
	var g: String = gpu.to_lower()
	if g.contains("geforce") or g.contains("rtx") or g.contains("gtx") or g.contains(" rx ") or g.contains("radeon rx"):
		return false
	for h in INTEGRATED_HINTS:
		if g.contains(h):
			return true
	return false


## The recommended preset: {"quality": Quality, "reason": String}.
## Rules, first match wins:
##   1. software rendering, or no Vulkan runtime          -> LOW
##   2. under 8 GB RAM                                    -> LOW
##   3. integrated GPU: 16 GB+ -> MEDIUM, otherwise LOW
##   4. unknown GPU name or unknown RAM                   -> MEDIUM
##   5. high-end discrete GPU and 16 GB+                  -> ULTRA
##   6. discrete GPU and 12 GB+                           -> HIGH
##   7. any other discrete GPU                            -> MEDIUM
static func recommend(info: Dictionary) -> Dictionary:
	var gpu: String = String(info.get("gpu", ""))
	var ram: int = int(info.get("ram_mb", -1))
	var gb: float = ram / 1024.0
	if is_software(gpu) or not bool(info.get("vulkan", false)):
		return {"quality": Quality.LOW, "reason": "No hardware Vulkan found, so the lightest preset is safest."}
	if ram > 0 and gb < 7.5:
		return {"quality": Quality.LOW, "reason": "Under 8 GB of RAM."}
	if gpu.strip_edges() == "" or ram <= 0:
		return {"quality": Quality.MEDIUM, "reason": "Could not read the GPU or RAM, so a middle preset."}
	if is_integrated(gpu):
		if gb >= 15.5:
			return {"quality": Quality.MEDIUM, "reason": "Integrated graphics with 16 GB or more RAM."}
		return {"quality": Quality.LOW, "reason": "Integrated graphics with under 16 GB RAM."}
	var g: String = gpu.to_lower()
	if gb >= 15.5:
		for h in HIGH_END_HINTS:
			if g.contains(h):
				return {"quality": Quality.ULTRA, "reason": "High-end graphics card and 16 GB or more RAM."}
	if gb >= 11.5:
		return {"quality": Quality.HIGH, "reason": "Dedicated graphics card and 12 GB or more RAM."}
	return {"quality": Quality.MEDIUM, "reason": "Dedicated graphics card with 8 to 12 GB RAM."}


## Report lines for the UI: [[label, value], ...].
static func lines(info: Dictionary) -> Array:
	var ram: int = int(info.get("ram_mb", -1))
	return [["System", String(info.get("os", "?"))],
		["Graphics card", String(info.get("gpu", "?"))],
		["Driver", String(info.get("driver", "?"))],
		["Renderer", String(info.get("renderer", "?"))],
		["Memory", "%.1f GB" % (ram / 1024.0) if ram > 0 else "unknown"]]
