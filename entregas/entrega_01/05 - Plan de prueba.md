# Plan de pruebas del Display Driver

Cada prueba declara estímulo, resultado esperado y criterio de aprobación, tal como pide la rúbrica. Los números de la especificación están en

## A. Recepción de órdenes por SPI

| # | Qué mandamos | Qué esperamos | ¿Hecha? |
|---|---|---|---|
| 1 | `SET_SPRITE` válido: `01 02 05 0A FD` | El slot 2 queda con sprite 5, X = 10, Y = −3, visible | ☐ |
| 2 | `SET_BG` con fondo 1 | `BG_SEL` = 1 | ☐ |
| 3 | `HIDE_SPRITE` del slot 2 | El slot 2 queda oculto | ☐ |
| 4 | Una trama de solo 4 bytes | Se ignora y `STATUS.error` = 1 | ☐ |
| 5 | Una orden desconocida (`0x7F …`) | Se ignora y `STATUS.error` = 1 | ☐ |
| 6 | Slot 16, o un sprite o fondo que no existe | Se ignora y `STATUS.error` = 1 | ☐ |
| 7 | Una trama válida justo después de una inválida | Se procesa normal | ☐ |

## B. Dibujo en pantalla

| # | Qué mandamos | Qué esperamos | ¿Hecha? |
|---|---|---|---|
| 8 | Solo fondo, sin sprites, y `COMMIT` | La pantalla muestra el fondo igual al original | ☐ |
| 9 | Un sprite 8×8 sobre el fondo | Se ve el sprite y **no** hay recuadro negro: donde el sprite es `#0F081F` se ve el fondo | ☐ |
| 10 | Un sprite 8×8 y otro 16×16 a la vez | Cada uno se ve completo | ☐ |
| 11 | Sprite en X = −3 y otro en X = 62 | Se ven recortados en el borde, sin aparecer del otro lado | ☐ |
| 12 | Dos sprites solapados | El del slot menor queda encima; donde es transparente se ve el de abajo | ☐ |
| 13 | Un sprite con un color casi igual a `#0F081F` | Ese color **sí** se dibuja, no se vuelve transparente | ☐ |
| 14 | `SET_SPRITE` sin `COMMIT` | La pantalla no cambia | ☐ |
| 15 | Varios `SET_SPRITE` y luego `COMMIT` | La escena aparece completa de una vez, sin parpadeo | ☐ |

## C. Panel y ESP32

| # | Qué mandamos | Qué esperamos | ¿Hecha? |
|---|---|---|---|
| 16 | Rojo, verde, azul y el color `#0F081F` | Los tres primeros se ven puros y el último se ve casi negro violeta | ☐ |
| 17 | La ESP32 manda una escena real (fondo + 3 sprites) | El panel la muestra bien, sin brillo de más ni fantasmas | ☐ |
