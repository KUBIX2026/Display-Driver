# Entrega 03 — Compositor, sprites, texto y barrido HUB75

Código y diagramas van de la mano: cada diagrama de `diagramas/diagramas_actualizados.md`
indica el módulo, el estado o la señal del Verilog que lo implementa y el test que lo verifica.

## Estructura

```
entrega_03/
├── codigos_verilog_sim/
│   ├── top.v  spi_receiver.v  spi_decoder.v  scene_compositor.v
│   ├── scan_counter.v  delay_unit.v  panel_pwm.v
│   ├── *_TB.v            testbenches (módulo tb_<nombre>)
│   ├── constraints.lpf   pines (idénticos a las entregas 01 y 02)
│   ├── Makefile
│   ├── assets/           fondos, sprites, metadatos y fuente (.hex)
│   └── tools/            generate_assets.py · ref_model.py
├── firmware/display_test.ino   ESP32 por SPI
└── diagramas/diagramas_actualizados.md
```

## Uso (desde `codigos_verilog_sim/`)

```
make sim        # 7 testbenches + comparación con el modelo en Python
make report     # síntesis + place&route: LUTs, EBR, frecuencia
make bit        # bitstream (necesita ecppack)
make program    # carga a la placa (openFPGALoader)
```

Requisitos: `iverilog`, `yosys`, `nextpnr-ecp5`, `python3`; `ecppack` y `openFPGALoader`
solo para `make bit` y `make program`. Las rutas de `assets/` son relativas, así
que los comandos se ejecutan desde esta carpeta.

## Trazabilidad diagrama ↔ código ↔ prueba

| Diagrama | Código | Prueba |
|---|---|---|
| 6. Receptor SPI | `spi_receiver.v`, `spi_decoder.v` | `spi_receiver_TB`, `spi_invalid_TB` |
| 3. FSM del compositor | `scene_compositor.v` (`ST_*`) | `framebuffer_TB`, `pending_commit_TB` |
| 4. Datapath del compositor | `scene_compositor.v` (pipeline, recorte, `0x0843`) | `spec_rules_TB` + `tools/ref_model.py` |
| 5. Bloques internos | `top.v` | `top_TB` |
| 7. Barrido HUB75 | `scan_counter.v`, `panel_pwm.v`, `delay_unit.v`, `top.v` | `hw_check_TB`, `spec_rules_TB` |

## Resultados medidos (ECP5-25K, CABGA256, 25 MHz)

| | |
|---|---|
| LUTs | 7 549 de 24 288 (31 %) |
| EBR | 29 de 56 (51 %) |
| Frecuencia máxima | ≈ 75 MHz (pasa a 25 MHz) |
| Refresco | 381 Hz |
