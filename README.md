# Home Assistant Voice Assistant Smart Speaker

In the search for an "easy" Voice Assistant I ran across a lot of different implementations, many of which were confusing or left out key information needed. I decided to use an ESP32-S3-DevKitC-1-N8R2 Development Board. I finally found a Blog (https://tristam.ie/2024/1126/) that helped at least get a Voice Assistant up and running the only problem was, it wasn't a media_player. A lot of the work here is based on that work, except the Yaml file. I spent some time reviewing available working speakers including purchasing the ESP32-Box-S3 as an example of something that worked and finally came up with something that "works". It's still a work in progress, but I can play music on it, announcements, and it's working fairly well. Note: This is a Work in progress, not a finished project.  

# Files in the repo

- README.md - This readme
- schem (folder) - Contains a png wiring schematic for those who like a visual representation. This was taken from the aforementioned blog and edited.
- YAML (folder) - This contains the current working yaml for ESPHome in Home Assistant
- 3D Print - This contains the stl files to 3D print a box to place the components in. Currently, it is based on a remix (https://www.printables.com/model/982104-esp32-s3-esphome-voice-assistant-with-local-wake-w) of the original (https://www.printables.com/model/967157-esp32-s3-esphome-voice-assistant-with-local-wake-w) my plan is to not leave these unedited for long and make assembly more intuitive. 
