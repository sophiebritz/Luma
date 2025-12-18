/*
 * WS2812B LED Test for ESP32-C3
 * Tests different GPIO pins to find your LEDs
 */

#include <Arduino.h>
#include <Adafruit_NeoPixel.h>

// ========================================
// CHANGE THIS TO YOUR LED DATA PIN
// ========================================
#define LED_PIN 0      // Try: 0, 1, 2, 3, 4, 5, 6, 7
#define NUM_LEDS 12    // Number of LEDs in your strip

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("\n=== WS2812B LED Test ===");
    Serial.print("Testing LEDs on GPIO");
    Serial.println(LED_PIN);
    Serial.print("Number of LEDs: ");
    Serial.println(NUM_LEDS);
    
    strip.begin();
    strip.setBrightness(100);  // 0-255
    strip.clear();
    strip.show();
    
    Serial.println("LEDs initialized!");
    Serial.println("You should see: RED -> GREEN -> BLUE -> CHASE");
}

void loop() {
    Serial.println("\n--- RED ---");
    strip.fill(strip.Color(255, 0, 0));  // Red
    strip.show();
    delay(1000);
    
    Serial.println("--- GREEN ---");
    strip.fill(strip.Color(0, 255, 0));  // Green
    strip.show();
    delay(1000);
    
    Serial.println("--- BLUE ---");
    strip.fill(strip.Color(0, 0, 255));  // Blue
    strip.show();
    delay(1000);
    
    Serial.println("--- WHITE ---");
    strip.fill(strip.Color(255, 255, 255));  // White
    strip.show();
    delay(1000);
    
    Serial.println("--- CHASE ---");
    for (int i = 0; i < NUM_LEDS; i++) {
        strip.clear();
        strip.setPixelColor(i, strip.Color(255, 0, 0));
        strip.show();
        delay(100);
    }
    
    Serial.println("--- OFF ---");
    strip.clear();
    strip.show();
    delay(500);
}
