#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <SpotifyEsp32.h>
#include <SPI.h>
#include <TJpg_Decoder.h>
#include <math.h>
#include "driver/gpio.h"

const char* SSID = "SSID";
const char* PASSWORD = "PASSWORD";

const char* CLIENT_ID = "CLIENT_ID";
const char* CLIENT_SECRET = "CLIENT_SECRET";
const char* REFRESH_TOKEN = "REFRESH_TOKEN";

Spotify sp(CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN);

const int PIN_CS = 5;

// Buffer local: Aquí guardamos la portada plana de 64x64 antes de rotarla
uint16_t album_cover[4096]; 
float angulo = 0.0;

String track_actual = "";

// Callback: TJpg_Decoder lo llama para guardar los colores en el buffer local
bool guardar_bloque_en_ram(int16_t x, int16_t y, uint16_t w, uint16_t h, uint16_t* bitmap) {
  for (int16_t j = 0; j < h; j++) {
    for (int16_t i = 0; i < w; i++) {
      int index = ((y + j) * 64) + (x + i);
      if (index < 4096) album_cover[index] = bitmap[j * w + i];
    }
  }
  return true;
}

// Descarga un archivo JPG desde internet directamente a TJpg_Decoder
void descargar_imagen_a_vram(String url) {
  HTTPClient http;
  http.begin(url);
  int httpCode = http.GET();
  
  if (httpCode == HTTP_CODE_OK) {
    int len = http.getSize();
    uint8_t* buff = (uint8_t*) malloc(len);
    
    if (buff != NULL) {
      WiFiClient * stream = http.getStreamPtr();
      int c = stream->readBytes(buff, len);
      
      // Solo si descargó el archivo completo, lo pasamos al decodificador.
      // Esto evita que la pantalla se ponga negra si la descarga falla a la mitad.
      if (c == len && len > 0) {
        TJpgDec.drawJpg(0, 0, buff, len);
        Serial.println("Imagen cargada exitosamente en VRAM.");
      } else {
        Serial.println("Error: Archivo JPG incompleto.");
      }
      free(buff);
    }
  } else {
    Serial.println("Error HTTP al descargar la imagen: " + String(httpCode));
  }
  http.end();
}

// Tarea independiente para manejar la descarga de Spotify en el fondo
void tarea_spotify(void *pvParameters) {
  while (1) {
    String nuevo_track = sp.current_track_name();
    
    // FILTRO ANTIBASURA: Ignoramos respuestas nulas, vacías o errores temporales de la API
    if (nuevo_track != track_actual && 
        nuevo_track != "" && 
        nuevo_track != "null" && 
        nuevo_track.indexOf("Something went wrong") == -1) {
          
      Serial.println("Cambio real detectado. Nueva canción: " + nuevo_track);
      
      // Obtenemos la URL de la imagen en tamaño pequeño (índice 2 = 64x64)
      String url_imagen = sp.get_current_album_image_url(2);
      
      // Solo guardamos la pista como "actual" si la URL de la imagen es válida
      if (url_imagen != "" && url_imagen.indexOf("Something went wrong") == -1) {
        track_actual = nuevo_track; // Ahora sí actualizamos la memoria
        Serial.println("Descargando carátula...");
        descargar_imagen_a_vram(url_imagen);
      } else {
        Serial.println("La API no entregó una carátula válida aún.");
      }
    }
    
    // Pausa de 1.5 segundos (Equilibrio perfecto entre velocidad de reacción y evitar baneos de Spotify)
    vTaskDelay(pdMS_TO_TICKS(1500));
  }
}

// Motor de Renderizado 2D
void enviar_frame_rotado() {
  // Límite de velocidad SPI seguro para la FPGA (6 MHz recomendado)
  SPI.beginTransaction(SPISettings(4500000, MSBFIRST, SPI_MODE0));
  
  float s = sin(angulo);
  float c = cos(angulo);
  float centro = 31.5; 

  for (int y = 0; y < 64; y++) {
    for (int x = 0; x < 64; x++) {
      float dx = x - centro;
      float dy = y - centro;
      float distancia_cuadrada = dx * dx + dy * dy;

      uint16_t color = 0x0000; 
      
      if (distancia_cuadrada <= 992 && distancia_cuadrada >= 30) {
        int rx = round(dx * c - dy * s + centro);
        int ry = round(dx * s + dy * c + centro);

        if (rx >= 0 && rx < 64 && ry >= 0 && ry < 64) {
          color = album_cover[ry * 64 + rx];
        }
      }

      // Manipulación directa de registros GPIO de ESP-IDF para velocidad máxima
      gpio_set_level((gpio_num_t)PIN_CS, 0); 
      
      SPI.transfer(0x01);         
      SPI.transfer(x);            
      SPI.transfer(y);            
      SPI.transfer(color >> 8);   
      SPI.transfer(color & 0xFF); 
      
      gpio_set_level((gpio_num_t)PIN_CS, 1); 
    }
  }
  SPI.endTransaction();
  
  // Velocidad de rotación
  angulo += 0.06; 
}

void setup() {
  Serial.begin(115200);
  
  // Configuración SPI hacia la FPGA
  pinMode(PIN_CS, OUTPUT);
  digitalWrite(PIN_CS, HIGH);
  SPI.begin();

  // Configuración Wi-Fi
  WiFi.begin(SSID, PASSWORD);
  Serial.print("Conectando Wi-Fi...");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi Conectado.");

  // Configuración Spotify
  sp.begin();
  while(!sp.is_auth()) sp.handle_client();
  Serial.println("Spotify Autenticado silenciosamente.");

  // Configuración del motor JPG
  TJpgDec.setJpgScale(1);
  TJpgDec.setCallback(guardar_bloque_en_ram);

  // Asignar la tarea de red al Núcleo 0 (Independiza el Wi-Fi del SPI)
  xTaskCreatePinnedToCore(
    tarea_spotify,   
    "SpotifyTask",   
    10000,           
    NULL,            
    1,               
    NULL,            
    0                // Se ejecuta en el Core 0
  );
}

void loop() {
  // El loop principal se ejecuta en el Núcleo 1 y solo dispara fotogramas ininterrumpidamente
  enviar_frame_rotado();
}
