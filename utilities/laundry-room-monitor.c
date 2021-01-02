// gcc -o laundry-room-monitor laundry-room-monitor.c -l bcm2835
// sudo chown root ./laundry-room-monitor; sudo chmod +s ./laundry-room-monitor
// ./laundry-room-monitor

// to install bcm2835 see http://www.airspayce.com/mikem/bcm2835/
// you have to download the tarball and compile it locally

// Inspired by a sample by Mike McCauley.

#include <bcm2835.h>
#include <stdio.h>

// RPI_BPLUS_GPIO_J8_XX refers to pin XX on the pinout, not the "BCM"
// number, nor the GPIO number.
#define DRYER_PIN RPI_BPLUS_GPIO_J8_18 // GPIO5 (connect other side to 3.3V pin 17)

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (!bcm2835_init()) {
    printf("bcm2835 library initialization failure\n");
    return 1;
  }

  bcm2835_gpio_fsel(DRYER_PIN, BCM2835_GPIO_FSEL_INPT);
  bcm2835_gpio_set_pud(DRYER_PIN, BCM2835_GPIO_PUD_DOWN);

  uint8_t last_value = 0xFF;
  
  while (1) {
    uint8_t dryer = bcm2835_gpio_lev(DRYER_PIN); // will be 0x00 or 0x01
    uint8_t next_value = dryer; // mix in other bits here if we add any
    if (last_value != next_value) {
      printf("%c", next_value);
      last_value = next_value;
    }
    delay(250); // really no need to be super responsive on this sensor
  }

  bcm2835_close();
  return 0;
}
