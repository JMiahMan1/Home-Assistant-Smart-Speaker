#pragma once

#include "esphome/core/component.h"
#include "esphome/components/light/light_output.h"
#include "esphome/core/log.h"
#include "driver/gpio.h"
#include "soc/gpio_reg.h"
#include "soc/soc.h"
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

namespace esphome {
namespace single_ws2812 {

class SingleWS2812Light : public light::LightOutput, public Component {
 public:
  void set_pin(int pin) { pin_ = pin; }
  void setup() override;
  light::LightTraits get_traits() override;
  void write_state(light::LightState *state) override;

 protected:
  int pin_;

  void IRAM_ATTR send_byte(uint8_t val);
  void IRAM_ATTR send_zero();
  void IRAM_ATTR send_one();
  void IRAM_ATTR set_pin_level(int level);
  void IRAM_ATTR delay_cycles(uint32_t cycles);
  uint32_t IRAM_ATTR get_ccount();
};

} // namespace single_ws2812
} // namespace esphome
