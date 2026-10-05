# System check

Settings > System check (also shown once on first run). Local only: nothing
is sent. It reports OS, GPU name, driver, renderer (Vulkan, or "OpenGL
fallback" when no Vulkan runtime is installed) and RAM, then recommends a
quality preset. The rules (first match wins) are in `SystemCheck.recommend()`:

1. Software rendering or no Vulkan runtime: Low
2. Under 8 GB RAM: Low
3. Integrated GPU: Medium with 16 GB or more RAM, otherwise Low
4. Unknown GPU or RAM: Medium
5. High-end discrete GPU (RTX 40/50, RTX 3080+, RX 6800+/7xxx/9xxx) and 16 GB+: Ultra
6. Discrete GPU and 12 GB+: High
7. Other discrete GPU: Medium

"Apply" writes the preset into the game's settings file (GameSettingsFile).
