import esphome.codegen as cg
import esphome.config_validation as cv
from esphome.components import light
from esphome.const import CONF_OUTPUT_ID, CONF_PIN

single_ws2812_ns = cg.esphome_ns.namespace("single_ws2812")
SingleWS2812Light = single_ws2812_ns.class_("SingleWS2812Light", light.LightOutput, cg.Component)

from esphome import pins

CONFIG_SCHEMA = light.RGB_LIGHT_SCHEMA.extend({
    cv.GenerateID(CONF_OUTPUT_ID): cv.declare_id(SingleWS2812Light),
    cv.Required(CONF_PIN): pins.internal_gpio_output_pin_number,
}).extend(cv.COMPONENT_SCHEMA)

async def to_code(config):
    var = cg.new_Pvariable(config[CONF_OUTPUT_ID])
    await cg.register_component(var, config)
    await light.register_light(var, config)
    
    cg.add(var.set_pin(config[CONF_PIN]))
