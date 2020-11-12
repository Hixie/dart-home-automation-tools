// gcc -o button-monitor button-monitor.c -l bcm2835
// sudo chown root ./button-monitor; sudo chmod +s ./button-monitor
// ./button-monitor

// to install bcm2835 see http://www.airspayce.com/mikem/bcm2835/
// you have to download the tarball and compile it locally

// Inspired by a sample by Mike McCauley.

#include <bcm2835.h>
#include <stdio.h>

#define BUTTONA_PIN RPI_BPLUS_GPIO_J8_16
#define BUTTONB_PIN RPI_BPLUS_GPIO_J8_18

int main(int argc, char **argv) {
  setvbuf(stdout, NULL, _IONBF, 0);
  if (!bcm2835_init()) {
    printf("bcm2835 library initialization failure\n");
    return 1;
  }

  bcm2835_gpio_fsel(BUTTONA_PIN, BCM2835_GPIO_FSEL_INPT);
  bcm2835_gpio_fsel(BUTTONB_PIN, BCM2835_GPIO_FSEL_INPT);
  bcm2835_gpio_set_pud(BUTTONA_PIN, BCM2835_GPIO_PUD_OFF);
  bcm2835_gpio_set_pud(BUTTONB_PIN, BCM2835_GPIO_PUD_OFF);

  uint8_t last_value = 0xFF;
  
  while (1) {
    uint8_t buttonA = ~bcm2835_gpio_lev(BUTTONA_PIN) & 0x01;
    uint8_t buttonB = ~bcm2835_gpio_lev(BUTTONB_PIN) & 0x01;
    uint8_t next_value = buttonA | (buttonB << 1);
    if (last_value != next_value) {
      printf("%c", next_value);
      last_value = next_value;
    }
    delay(10);
  }

  bcm2835_close();
  return 0;
}
