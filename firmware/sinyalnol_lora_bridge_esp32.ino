/*
  =============================================================================
  SinyalNol - Firmware Bridge Modem Radio LoRa Jarak Jauh (5 - 20 KM)
  Hardware Kompatibel: Heltec WiFi LoRa 32 V3, TTGO T-Beam, SX1262/SX1276 ESP32
  Protokol: USB-OTG Serial CDC @ 115200 baud <--> Radio LoRa RF (915/433 MHz)
  =============================================================================
*/

#include <SPI.h>
#include <RadioLib.h> // Library RadioLib (Universal SX1262 / SX1276 / SX1278)

// Pinout Standar Heltec WiFi LoRa 32 V3 (SX1262)
#define LORA_CS    8
#define LORA_DIO1  14
#define LORA_RST   12
#define LORA_BUSY  13

SX1262 radio = new Module(LORA_CS, LORA_DIO1, LORA_RST, LORA_BUSY);

// Parameter Default Operasional Taktis SAR (Dapat diubah via perintah serial)
float frequency = 915.0; // Indonesia / US ISM Band (atau 433.0 MHz)
float bandwidth = 125.0; // kHz
uint8_t spreadingFactor = 10; // SF10 (Default SAR ~10-15km)
uint8_t codingRate = 7; // 4/7
int8_t txPower = 22; // dBm (Maksimal untuk penetrasi bukit/hutan)

volatile bool receivedFlag = false;

void setFlag(void) {
  receivedFlag = true;
}

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000);

  Serial.println(F("[SinyalNol Bridge] Menginisialisasi transceiver LoRa SX1262..."));

  int state = radio.begin(frequency, bandwidth, spreadingFactor, codingRate, 0x12, txPower);
  if (state == RADIOLIB_ERR_NONE) {
    Serial.println(F("[SinyalNol Bridge] Transceiver LoRa SIAP @ 915.0 MHz SF10!"));
  } else {
    Serial.print(F("[SinyalNol Bridge] Inisialisasi radio gagal, kode error: "));
    Serial.println(state);
  }

  // Set interrupt untuk menerima frame LoRa masuk dari udara
  radio.setPacketReceivedAction(setFlag);
  radio.startReceive();
}

void loop() {
  // 1. Menerima data dari smartphone melalui kabel USB-OTG Serial
  if (Serial.available()) {
    String outPayload = Serial.readStringUntil('\n');
    outPayload.trim();

    if (outPayload.length() > 0) {
      // Perintah konfigurasi modem dari aplikasi
      if (outPayload.startsWith("AT+FREQ=")) {
        frequency = outPayload.substring(8).toFloat();
        radio.setFrequency(frequency);
        Serial.println(F("[ACK] Frekuensi diperbarui"));
      } else if (outPayload.startsWith("AT+SF=")) {
        spreadingFactor = outPayload.substring(6).toInt();
        radio.setSpreadingFactor(spreadingFactor);
        Serial.println(F("[ACK] Spreading factor diperbarui"));
      } else {
        // Pancarkan frame paket JSON ke udara melalui gelombang radio LoRa RF
        Serial.print(F("[LoRa TX] Memancarkan paket radio: "));
        Serial.println(outPayload.length());
        
        int txState = radio.transmit(outPayload);
        if (txState == RADIOLIB_ERR_NONE) {
          Serial.println(F("[LoRa TX] Berhasil dipancarkan ke udara!"));
        } else {
          Serial.print(F("[LoRa TX] Transmisi gagal: "));
          Serial.println(txState);
        }
        
        // Kembalikan ke mode siaga mendengar
        radio.startReceive();
      }
    }
  }

  // 2. Menerima gelombang radio LoRa masuk dari udara dan teruskan ke ponsel via USB
  if (receivedFlag) {
    receivedFlag = false;

    String inPayload;
    int rxState = radio.readData(inPayload);

    if (rxState == RADIOLIB_ERR_NONE) {
      float rssi = radio.getRSSI();
      float snr = radio.getSNR();

      // Format frame yang diterima dan teruskan langsung ke SinyalNol di ponsel
      Serial.println(inPayload);
    }

    radio.startReceive();
  }
}
