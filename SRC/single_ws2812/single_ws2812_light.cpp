#include "single_ws2812_light.h"

namespace esphome {
namespace single_ws2812 {

void SingleWS2812Light::setup() {
    ESP_LOGI("single_ws2812", "Setting up Single WS2812 LED on pin %d", pin_);
    gpio_reset_pin((gpio_num_t)pin_);
    gpio_set_direction((gpio_num_t)pin_, GPIO_MODE_OUTPUT);
}

light::LightTraits SingleWS2812Light::get_traits() {
    auto traits = light::LightTraits();
    traits.set_supported_color_modes({light::ColorMode::RGB});
    return traits;
}

void SingleWS2812Light::write_state(light::LightState *state) {
    float red, green, blue;
    state->current_values_as_rgb(&red, &green, &blue);

    // Convert to 0-255
    uint8_t r = (uint8_t)(red * 255);
    uint8_t g = (uint8_t)(green * 255);
    uint8_t b = (uint8_t)(blue * 255);

    // Disable interrupts to ensure timing
    portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;
    taskENTER_CRITICAL(&mux);

    // GRB Order
    send_byte(g);
    send_byte(r);
    send_byte(b);

    taskEXIT_CRITICAL(&mux);
}

void IRAM_ATTR SingleWS2812Light::send_byte(uint8_t val) {
    for (int i = 0; i < 8; i++) {
        if (val & 0x80) {
            send_one();
        } else {
            send_zero();
        }
        val <<= 1;
    }
}

void IRAM_ATTR SingleWS2812Light::send_zero() {
    set_pin_level(1);
    delay_cycles(96); 
    set_pin_level(0);
    delay_cycles(204);
}

void IRAM_ATTR SingleWS2812Light::send_one() {
    set_pin_level(1);
    delay_cycles(192);
    set_pin_level(0);
    delay_cycles(108);
}

void IRAM_ATTR SingleWS2812Light::set_pin_level(int level) {
    if (pin_ < 32) {
        if (level) {
            REG_WRITE(GPIO_OUT_W1TS_REG, 1 << pin_);
        } else {
            REG_WRITE(GPIO_OUT_W1TC_REG, 1 << pin_);
        }
    } else {
        if (level) {
            REG_WRITE(GPIO_OUT1_W1TS_REG, 1 << (pin_ - 32));
        } else {
            REG_WRITE(GPIO_OUT1_W1TC_REG, 1 << (pin_ - 32));
        }
    }
}

void IRAM_ATTR SingleWS2812Light::delay_cycles(uint32_t cycles) {
    uint32_t start = get_ccount();
    while ((get_ccount() - start) < cycles) {
        // Spin
    }
}

uint32_t IRAM_ATTR SingleWS2812Light::get_ccount() {
    uint32_t ccount;
    __asm__ __volatile__("rsr %0,ccount":"=a" (ccount));
    return ccount;
}

} // namespace single_ws2812
} // namespace esphome
