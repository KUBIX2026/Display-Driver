#include <SPI.h>

// Configuración de Pines ESP32-WROOM-32
const int PIN_MOSI   = 23; 
const int PIN_CLK    = 18; 
const int PIN_CS     = 5;  

// Variable para recorrer el espectro de colores (0 a 255)
uint8_t hue = 0; 

void setup() {
  Serial.begin(115200);
  
  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH); // SPI inactivo al inicio
  
  SPI.begin(PIN_CLK, -1, PIN_MOSI, PIN_CS);
  Serial.println("Prueba de estrés SPI: Degradado de color continuo iniciado.");
}

// Función auxiliar para empaquetar 3 canales de 8 bits (RGB) al estándar RGB565 de 16 bits
uint16_t color565(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

// Función matemática para generar un degradado suave (Rueda de colores arcoíris)
uint16_t colorWheel(uint8_t pos) {
  pos = 255 - pos;
  if (pos < 85) {
    return color565(255 - pos * 3, 0, pos * 3);
  }
  if (pos < 170) {
    pos -= 85;
    return color565(0, pos * 3, 255 - pos * 3);
  }
  pos -= 170;
  return color565(pos * 3, 255 - pos * 3, 0);
}

void enviarTrama(uint16_t color) {
  // Transacción SPI a 1MHz, Modo 0
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  
  digitalWrite(PIN_CS, LOW); // Avisamos a la FPGA
  
  SPI.transfer(0x01); // Comando: Color plano
  SPI.transfer(0x00); // ID Objeto
  SPI.transfer(0x00); // Pos X
  // ¡Se eliminó el byte extra de Pos Y para mantener la trama en 5 bytes exactos (40 bits)!
  SPI.transfer((color >> 8) & 0xFF); // Parte ALTA del color
  SPI.transfer(color & 0xFF);        // Parte BAJA del color
  
  digitalWrite(PIN_CS, HIGH); // Finalizamos mensaje
  SPI.endTransaction();
}

void loop() {
  // 1. Calculamos el color actual en la transición
  uint16_t color_actual = colorWheel(hue);
  
  // 2. Disparamos la trama de 40 bits hacia la FPGA
  enviarTrama(color_actual);
  
  // 3. Incrementamos el tono para el siguiente ciclo. 
  // Al ser uint8_t, al llegar a 255 volverá automáticamente a 0.
  hue++;
  
  // 4. Retardo de 10ms = 100 actualizaciones por segundo (Stress Test)
  delay(10); 
}
