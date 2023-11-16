## Tablet Internet Switch

Physical switch to turn off and on the internet on the kids' tablet (oh no the Internet seems to have stopped working!)

### How it works:
1. Script is installed on a Raspberry Pi or another Linux based network connected device. It does not have to be installed on the router/firewall/tablet/smart toaster/etc. It just needs to be connected to the same network.
3. The script monitors a switch connected to a predefined GPIO pin.
4. When the switch is on, the script runs `arpspoof` to prevent the predefined IP from communicating with the Internet gateway.
5. When the switch is off, the script stops arpsoof, allowing it to re-arp the target IP, restoring its access to the Internet.

### Installing:
1. Install arpspoof. This is part of the dsniff package. In debian this can be achieved with:
    ```
    sudo apt-get update
    sudo apt-get install dsniff
    ```
2. Configure to start at boot. To have the script start at boot, the easiest way is via root's cron:
   ```
   sudo crontab -e
   ```
   Add the following line, updating the path with the path of the script:
   ```
   @reboot ( /root/tablet-internet-switch/switch-listener.sh; )
   ```
   Save and exit.

### Configuring:
1. The (static) IP address of the target, and
2. The gateway need to be updated, as well as
3. The GPIO pin the switch is conneted to, config near the top of the script:
   ```bash
    TARGET_IP=192.168.0.65 # IP of the tablet
    #...
    GPIO_PIN=2
    ```

For example, I use GPIO 2 (pin 3), and ground (pin 6) for the switch:

![image](https://github.com/caffeinatedgoat/Tablet-Internet-Switch/assets/41058709/f24e2b12-ab17-4e35-a45f-5f1f50ad912f)


