set -ex
gcc -o leak-sensor-monitor leak-sensor-monitor.c -l bcm2835
sudo chown root ./leak-sensor-monitor
sudo chmod +s ./leak-sensor-monitor
./leak-sensor-monitor
