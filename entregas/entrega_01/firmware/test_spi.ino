#include <SPI.h>

// Configuración de Pines ESP32-WROOM-32
const int PIN_MOSI   = 23; 
const int PIN_CLK    = 18; 
const int PIN_CS     = 5;  
const int PIN_BUTTON = 4; // Botón entre pin 4 y GND

// Colores RGB565 para ciclar
uint16_t colores[] = {
  0xFFFF, // Blanco
  0xF800, // Rojo
  0x07E0, // Verde
  0x001F, // Azul
  0x7BEF  // Gris
};
const int NUM_COLORES = 5;
int indice_color = 0;

int estado_anterior = HIGH;

void setup() {
  Serial.begin(115200);
  
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH); // SPI inactivo al inicio
  
  SPI.begin(PIN_CLK, -1, PIN_MOSI, PIN_CS);
  Serial.println("Consola iniciada. Presiona el botón para cambiar de color.");
}

void enviarTrama(uint16_t color) {
  // Transacción SPI a 1MHz, Modo 0
  SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  
  digitalWrite(PIN_CS, LOW); // Avisamos a la FPGA
  
  SPI.transfer(0x01); // Comando: Color plano
  SPI.transfer(0x00); // ID Objeto
  SPI.transfer(0x00); // Pos X
  SPI.transfer((color >> 8) & 0xFF); // Parte ALTA del color
  SPI.transfer(color & 0xFF);        // Parte BAJA del color
  
  digitalWrite(PIN_CS, HIGH); // Finalizamos mensaje
  SPI.endTransaction();
}

void loop() {
  int lectura = digitalRead(PIN_BUTTON);
  
  // Si el botón está presionado AHORA (LOW) pero ANTES no lo estaba (HIGH)
  if (lectura == LOW && estado_anterior == HIGH) {
    
    indice_color = (indice_color + 1) % NUM_COLORES;
    uint16_t color_actual = colores[indice_color];
    
    Serial.print("Enviando color: 0x");
    Serial.println(color_actual, HEX);
    
    enviarTrama(color_actual);
    
    // Retardo rudo pero efectivo de 200ms para ignorar el rebote del resorte físico
    delay(200); 
  }
  
  estado_anterior = lectura;
}
