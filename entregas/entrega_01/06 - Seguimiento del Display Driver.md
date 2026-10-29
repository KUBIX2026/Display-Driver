# Seguimiento del Display Driver

## Estado

| Parte | Estado |
|---|---|
| Receptor SPI | Hecho |
| Barrido del panel HUB75 y PWM | Hecho |
| Prueba con la ESP32 | Hecha |
| Especificación (tramas, registros, errores) | En diseño |
| Diagramas | En diseño |
| Plan de pruebas | En diseño |
| Compositor (sprites sobre fondo) | Por hacer |
| Memorias de sprites y fondos | Por hacer |
| Doble buffer | Por hacer |

## En GitHub

- Crear un **issue** por cada parte de la tabla, con responsable y fecha.
- Hacer commits con mensajes claros y abrir el **pull request** al repositorio general.

## Limpieza del repositorio

1. Borrar las marcas `[cite: 8]`, `[cite: 10]` que quedaron en el texto.
2. Borrar el `)]` suelto de la sección 1.1.
3. Cambiar `0xFFFF` / `1xFFFF` por `#0F081F` en todos lados.
4. Dejar la trama en **40 bits** (hoy aparece 32 en un documento y 40 en otro).
5. Que las rutas del README coincidan con las carpetas reales.
