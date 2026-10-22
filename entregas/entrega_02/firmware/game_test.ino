#include <SPI.h>

const int PIN_MOSI   = 23; 
const int PIN_CLK    = 18; 
const int PIN_CS     = 5;  
const int PIN_BUTTON = 4; // Botón (Jump)

// Parámetros del juego
int dino_x = 10;
int dino_y = 48; // Nivel del suelo
int dino_w = 4;
int dino_h = 6;

float velocity_y = 0;
bool is_jumping = false;
float gravity = 1.0;

int cactus_x = 63;
int cactus_y = 48;
int cactus_w = 3;
int cactus_h = 6;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);
  
  SPI.begin(PIN_CLK, -1, PIN_MOSI, PIN_CS);

  // Limpiar toda la pantalla a negro al iniciar
  drawRect(0, 0, 64, 64, 0x0000);
  // Dibujar línea del suelo blanca
  drawRect(0, 54, 64, 2, 0xFFFF);
}

// Función base que envía un pixel a la FPGA
void enviarPixel(uint8_t x, uint8_t y, uint16_t color) {
  if (x > 63 || y > 63) return; // Evitar desbordamiento
  
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  digitalWrite(PIN_CS, LOW);
  
  SPI.transfer(0x01); // Comando: Dibujar Píxel
  SPI.transfer(x);
  SPI.transfer(y);
  SPI.transfer((color >> 8) & 0xFF);
  SPI.transfer(color & 0xFF);
  
  digitalWrite(PIN_CS, HIGH);
  SPI.endTransaction();
}

// Función para dibujar sprites rectangulares
void drawRect(int start_x, int start_y, int w, int h, uint16_t color) {
  for(int i = 0; i < w; i++) {
    for(int j = 0; j < h; j++) {
      int px = start_x + i;
      int py = start_y + j;
      if(px >= 0 && px <= 63 && py >= 0 && py <= 63) {
        enviarPixel((uint8_t)px, (uint8_t)py, color);
      }
    }
  }
}

void loop() {
  // 1. FASE DE BORRADO: Pintamos el fondo (negro) sobre la posición ANTERIOR
  drawRect(dino_x, (int)dino_y, dino_w, dino_h, 0x0000);
  drawRect(cactus_x, cactus_y, cactus_w, cactus_h, 0x0000);

  // 2. FASE LÓGICA: Física del salto
  if (digitalRead(PIN_BUTTON) == LOW && !is_jumping) {
    velocity_y = -6.5; // Fuerza del salto hacia arriba (coordenadas Y bajan)
    is_jumping = true;
  }

  dino_y += velocity_y;

  if (is_jumping) {
    velocity_y += gravity;
  }

  // Comprobar colisión con el suelo
  if (dino_y >= 48) {
    dino_y = 48;
    is_jumping = false;
    velocity_y = 0;
  }

  // Movimiento del Cactus hacia la izquierda
  cactus_x -= 2; 
  if (cactus_x < -cactus_w) {
    cactus_x = 63; // Reaparece a la derecha
  }

  // 3. COLISIONES: Game Over si los cuadros se superponen
  bool colision_x = (dino_x < cactus_x + cactus_w) && (dino_x + dino_w > cactus_x);
  bool colision_y = (dino_y < cactus_y + cactus_h) && (dino_y + dino_h > cactus_y);

  if (colision_x && colision_y) {
    drawRect(0, 0, 64, 64, 0xF800); // Pantalla Roja (Game Over)
    delay(2000);
    drawRect(0, 0, 64, 64, 0x0000); // Limpiar Pantalla
    drawRect(0, 54, 64, 2, 0xFFFF); // Repintar suelo
    cactus_x = 63;
    dino_y = 48;
    is_jumping = false;
  }

  // 4. FASE DE DIBUJADO: Pintamos los sprites en la posición NUEVA
  drawRect(dino_x, (int)dino_y, dino_w, dino_h, 0x07E0);    // Dino Verde
  drawRect(cactus_x, cactus_y, cactus_w, cactus_h, 0xF800); // Cactus Rojo

  // 5. Velocidad del juego (FPS)
  delay(40); 
}