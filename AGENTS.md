# AGENTS.md — PescaIsla (Godot 4.7.1, Mobile, 1080x1920 vertical)

## Estructura de carpetas
```
assets/art/cat/      poses del gato en juego (cat_idle, cat_wait, cat_cast, cat_catch + defringe/)
assets/art/fish/     peces de 512 px con defringe (fish_<nombre>.png, rareza solo en datos)
assets/art/bg/       fondos (bg_dawn, bg_day, bg_night, bg_sunset)
assets/art/ui/       (futuro) piezas de UI recortadas
assets/art/shop/     cañas (rod_*) y cebos (bait_*)
assets/art/fx/       (futuro) efectos
assets/models/       (futuro) modelos reducidos listos para juego
assets/textures/     texturas en uso por la escena
assets/props/        modelos en uso por la escena
assets/audio/music|ambient|sfx|ui/
assets/fonts/        (futuro)
scripts/ shaders/ scenes/ data/ docs/ tools/ tools/
source/              ORIGINALES (ignorado por git y por Godot vía .gdignore):
  concepto/ ui/ peces/ gato/ modelos/ audio/ _sin_clasificar/
docs/previews/      capturas locales de validación (ignorado en git salvo reorg_base.png)
```

## Nombres
- Juego: `snake_case`, minúsculas, sin espacios, prefijos en inglés:
  `rod_bamboo|coral|moon|cherry|rainbow`, `bait_pink_worm|peach_shrimp|firefly_worm|golden_pearl`,
  `bg_dawn|day|night|sunset`, `fish_<nombre>` (ver tabla en docs/PROJECT_STATE.md),
  `sfx_*`, `ui_*`, `mus_*`, `amb_*`, `prop_*`.
- `source/`: conserva el nombre original SIEMPRE (aunque tenga espacios o mayúsculas).

## Reglas de trabajo
1. No mover, rotar ni escalar nodos existentes; no cambiar valores de escenas. Solo mover archivos + actualizar rutas.
2. `git mv` archivo junto con su `.import` (y `.uid` si existe). Renombrar solo fuera de `source/`.
3. Tras cada lote: `--import`, luego verificación (abajo). Si falla: `git checkout` del lote y avisar.
4. Un commit por lote (`Reorg 4x: ...`). Nada de más de 10 MB en el repositorio.
5. Nada se borra nunca. Lo dudoso va a `source/_sin_clasificar/`.
6. `export_presets.cfg` es LOCAL (ignorado en git). Copia de seguridad en `export_presets.cfg.bak`
   (no commitear). Su `exclude_filter` excluye de la APK: `tools/*, docs/*, source/*`,
   `AGENTS.md`, `README.md`. `tools/` contiene solo ayuda de desarrollo.
7. `source/` tiene `.gdignore` (Godot no lo importa) y está ignorado en git. `docs/` tiene
   `.gdignore`; sus `.import` antiguos son restos inertes, no tocar.
8. Capturas comparables exigen el MISMO `user://save.json` (la UI muestra monedas/progreso).

## Validación por lote
```
Godot --headless --path . --import                        # 0 errores, 0 warnings, sin "Failed loading resource"
Godot --headless --fixed-fps 60 --path . --script res://tools/dump_transforms.gd   # DUMP_OUT=... ; diff idéntico al base
Godot --path . --fixed-fps 60 --resolution 540x960 --script res://tools/capture.gd # DUMP_OUT=...
```
Comparar captura contra `docs/previews/reorg_base.png`: diferencia media < 0.5 fuera de
zonas de partículas (agua con ondas, luciérnagas, barco).

## Identificadores de peces (confirmados)
común: `fish_pink_sardine`, `fish_moon`, `fish_cream_carp` · poco común: `fish_mint_puffer`,
`fish_peach_angelfish`, `fish_jellyfish` · raro: `fish_lanternfish`, `fish_golden_koi`,
`fish_seahorse` · legendario: `fish_cloud`, `fish_mini_whale`, `fish_sea_dragon`
