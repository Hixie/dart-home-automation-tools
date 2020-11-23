// gcc -o leak-sensor-monitor leak-sensor-monitor.c -l bcm2835
// sudo chown root ./leak-sensor-monitor; sudo chmod +s ./leak-sensor-monitor
// ./leak-sensor-monitor

// to install bcm2835 see http://www.airspayce.com/mikem/bcm2835/
// you have to download the tarball and compile it locally

// Inspired by a sample by Mike McCauley.

#include <bcm2835.h>
#include <stdio.h>

// Connect the sensor's "ground" wire to pin GPIO12, and
// sensor's the "live" wire to pin GPIO6.
// The GPIO6 pin is driven to 3.3v as an output, and the
// GPIO12 pin is pulled down.

// The 3.3v rail could be used instead of an output pin
// but with the minipitft taking up both 3.3v rail pins
// it's just easier to use an output pin.

#define SENSOR_PIN RPI_BPLUS_GPIO_J8_32 // GPIO12 (sensing pin)
#define POWER_PIN RPI_BPLUS_GPIO_J8_31 // GPIO6 (output 3.3v)

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (!bcm2835_init()) {
    printf("bcm2835 library initialization failure\n");
    return 1;
  }

  // Configure the sensor pin to use a pull-down resistor.
  bcm2835_gpio_fsel(SENSOR_PIN, BCM2835_GPIO_FSEL_INPT);
  bcm2835_gpio_set_pud(SENSOR_PIN, BCM2835_GPIO_PUD_DOWN);

  // Sensor should be connected to 3.3v rail (not ground);
  // here we configure a pin to act as that rail.
  bcm2835_gpio_fsel(POWER_PIN, BCM2835_GPIO_FSEL_OUTP);
  bcm2835_gpio_set(POWER_PIN);

  while (1) {
    uint8_t value = bcm2835_gpio_lev(SENSOR_PIN);
    printf("%c", value);
    delay(100);
  }

  bcm2835_close();
  return 0;
}
