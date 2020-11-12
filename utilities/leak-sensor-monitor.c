// gcc -o leak-sensor-monitor leak-sensor-monitor.c -l bcm2835
// sudo chown root ./leak-sensor-monitor; sudo chmod +s ./leak-sensor-monitor
// ./leak-sensor-monitor

// to install bcm2835 see http://www.airspayce.com/mikem/bcm2835/
// you have to download the tarball and compile it locally

// Inspired by a sample by Mike McCauley.

#include <bcm2835.h>
#include <stdio.h>

#define SENSOR_PIN RPI_BPLUS_GPIO_J8_18

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (!bcm2835_init()) {
    printf("bcm2835 library initialization failure\n");
    return 1;
  }

  // Configure the pin to use a pull-down resistor.
  // Sensor should be connected to 3.3V rail.
  bcm2835_gpio_fsel(SENSOR_PIN, BCM2835_GPIO_FSEL_INPT);
  bcm2835_gpio_set_pud(SENSOR_PIN, BCM2835_GPIO_PUD_DOWN);

  while (1) {
    uint8_t value = bcm2835_gpio_lev(SENSOR_PIN);
    printf("%c", value);
    delay(100);
  }

  bcm2835_close();
  return 0;
}
