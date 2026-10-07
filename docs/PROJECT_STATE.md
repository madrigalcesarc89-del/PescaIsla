# PROJECT_STATE.md — PescaIsla

## Estado (tras Reorg 0–3)
- Escena `scenes/Main.tscn` terminada visualmente; sombra de contacto del gato activa.
- Fase 1 jugable: `scripts/fishing.gd` (IDLE→CAST→WAIT→BITE→REEL→CATCH/ESCAPE),
  `data/fish_db.json` (5 entradas provisionales), guardado en `user://save.json`.
- Exportación Android: preset local `export_presets.cfg` (ignorado en git, con `.bak`);
  excluye `tools/*, docs/*, source/*, AGENTS.md, README.md`. JDK 17 + SDK + plantillas OK.
- Reorg: raíz con ~53 assets sueltos sin referenciar (inventario en paso 1–2).

## Pendiente tras la reorg
1. **Reemplazar `data/fish_db.json` por los 12 peces reales con su rareza**
   (ver identificadores en AGENTS.md). Hoy `payaso` no corresponde a ningún pez real.
2. **Cortar en piezas las hojas de `source/ui/`** (marcos, iconos, botones, alerta, barra,
   panel) antes de usarlas en la interfaz.
3. Integrar cañas/cebos (`assets/art/shop/`), peces 512 px (`assets/art/fish/`),
   fondos (`assets/art/bg/`) y audio (`assets/audio/`) cuando los pidan las fases.
4. Música OGG: generada en el paso 4 con ffmpeg (`Gyan.FFmpeg` por winget).
