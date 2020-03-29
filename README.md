# Z-Way for OpenLuup		
 Zway introduction as a replacement for vera		

  Why Migrate? If you are reading this, you probably already know but just in case...		

  Because Z-way is a far more stable platform than the vera especially on larger networks. The vera current state has such fundamental design flaws that it is nearly unuseable for any network above ~40 devices. It becomes too chatty and error prone.		
 Even on smaller networks, the notoriously absurd abuse of luup reloads and forced deletion and creation of devices has turned away more than one customer.		
 A quick visit on the vera forum will get you a flavor of the issues plaguing this platform ranging from device bricking, poor storage management using tiny portion of what the hardware provides, ghost sensor trips, memory corruption, memory leaks... All of which I have experienced.		

  Z-way-server on the other hand is built on a much more stable and solid API and zwave library. The "Expert UI" can pretty much support any device which has nothing propriatory. It's smarthome UI, which API this plugin relies on however has its flaws, filtering out useful command classes and requiring some workaround to address the lower level API.		

  Assuming that the entire automation setup (scenes and plugins) have already been migrated to openLuup, you can now migrate the zwave hub and take advantage of the best part of the vera, it's object data structure, API and lua/plugins, and get rid of its instability.		

  # Guide to migrate from Vera as a zwave device hub to Z-way		

  There are many ways to migrate a zwave network. 		
 One way to initially run testing is just to add the z-way as a secondary controller to your network. Normally, the inclusion process of z-way involves a security key exchange which the vera often fails so you may need a few retries. At some point though when ready to let go of the vera, a different method will be required to give z-way the zwave primary role.		
 In order to do this, the official method is to run a controller shift which is similar to an inclusion but with the shifting of the primary role from the vera to the new controller. This again could require several retries due to vera's extraordinary ability to fail secure class key exchanges		

  My recommendation is to clone the controller. It has the advantage of not having to touch any other device on the network and some devices either only accept 1 lifeline associated controller (accept to take some packets only from one controller or worse, some devices won't even wake up to any other controller but the lifeline they had forcing the user to exclude/reinclude the device if the controller chained ID. Some devices even only accept their lifeline association to device ID1, again making having a controller not being the node ID #1 impossible for them.		

  A. Cloning the Vera's zwave dongle. (Vera Plus/Edge/Secure) using a zwave.me uzb stick		

  1. Always have a recent backup of your vera configuration handy. Preferably backup your zwave network along with your configuration now before you do anything.		
 2. SSH into the vera using an SSH client (i.e putty)		
 3. Go to /etc/cmh/ and take a look at your dongle's backup: 		
    cd /etc/cmh		
    ls		
    You should see a bunch of "dongle.dump" files. These are the backups of your zwave chips NVM. Basically your network data, including all the node information and routing.		
 4. Now insert the uzb into the usb port of the vera.  		
    ls /dev        should show a serial port called ttyACM0		
 5. Go into the vera UI and go under Settings/Z-wave settings/Options Tab and change the port field to "/dev/ttyACM0" and let the luup engine reload. This will wipe out all the zwave devices from your vera configuration (Another wonderful feature of the luup reload...) and switch you to the uzb as your zwave chip.		
 6. Go back to your SSH client window and still in the folder /etc/cmh/, type "touch dongle.restore", go back to the vera UI and start a luup reload. Once the luup engine has reloaded and you can see your dashboard, go to the ssh screen and type "reboot"		
 7. Upon reboot of the vera you should see all your old zwave devices repopulated with new names and without room assignments. Success! You have cloned your zwave dongle into the uzb.		

  B. Security key. (S0)		

  If you previously succesfully included or shifted the z-way into the vera's network with the security key then the key will be in your /z-way-server/config/zddx/config*** file at the entry line 57. If not you can always ask vera's support for the way to extract the key as they deleted my post which provided the instructions to do so. I will not post it here. You will need this key (16 bytes) if you have secure class devices on your network.		

  C. Configure Z-way		

  Move the uzb to your z-way-server machine and start z-way. Make sure that the zwave app has your uzb as its dongle device. Again it should be /dev/ttyACM0 if you are on a linux machine. You could also keep the uzb in the vera, nuke the vera software and forward the uzb serial port over IP to a virtual machine containing the z-wave-me server. This is a topic for another chapter. Make sure to have the Z-way credentials handy and to enable the Zwave API from the Z-way apps/Z-Wave Network Access menu. (tick every checkbox and save)		
 Once zway is up and running, go to the Expert UI and send a "NIF" (Node Information Frame) in the controller menu to every node. You may need to wakeup the sleepy nodes to interview them. Some devices may need a configuration change to work with z-way vs. vera. Ask on the forum if you run into something like this and can't figure it out. As devices get interviewed, their configurations get populated and virtual devices will show up in zway's Smarthome UI. You should not need to worry about associations since you cloned the controller's ID. For more information on interviews, consult the z-way manual.		

  Once this is done, you may want to rename all of the devices on the smartHome UI through recognizing them by their node IDs. Create rooms and assign the devices to the same room they were on the vera. Make sure that the room names are the same down to capitalization. This will make things easier for the next step.		

  D. Install the Z-way2 Bridge		

  It is as simple as downloading the files in this repo, drop them in your openLuup plugin folder (normally /etc/cmh-ludl) and create a new device using D_ZWay.xml and I_Zway2.xml as the device and implementation files respectively. Alternatively, it can be installed through openLuup's AltAppStore.		
 After installation, you will need to provide the z-way IP and credentials. For local installations on the same machine as openLuup, you can use "127.0.0.1" as the localhost IP. You will have to enter the credentials through openLuup's console.		
 Enable the CloneRooms feature by setting the variable to "1" in the plugin's device variable list and reload luup.		
 Tada! Upon luup reload, the zway devices will be populated on openluup in the same rooms as you set them on zway and also with the same names. Because zway does not use the same device library as vera and openLuup is does, some devices may have the wrong device types. You may need to go change the device file and device json for some of the devices but the rest should work from here.		

  E. Hardware Options		

  Z-way comes in two different hardware versions: 		
    The Razberry which is a raspberry Pi with a zwave daughter board		
    The uzb which is a silabs SD3102 USB dongle with a proprietary bootloader enabling it to keep a license key, manage the LED amoungst other things.		

  At the time of writting the razberry version of z-way 3.0.x is suffering from a bug causing it to shutdown under heavy http request load. I have not observed this on my ubuntu version.		

  Location of the zwave controller is crucial to the functionning of the network and therefore one will want to position it at a central location in the house. ith either of these two solutions, you have the possibility of locating the zwave device at one location and then forward its serial signal to another location, for example a server or a virtual machine on a computer which is on 24/7. Since you are running openluup, the recommendation would be to run z-way on the same machine as openluup no matter what it is as z-way is available on many platforms from windows to linux on arm64, arm32, to x64 an x32.		
 These are some guides to use ser2net to forward the serial port from one machine and receive it on the host computer with socat:		

  https://community.openhab.org/t/share-z-wave-dongle-over-ip-usb-over-ip-using-ser2net-socat-guide/34895		
 https://community.home-assistant.io/t/using-a-vera-edge-as-a-network-attached-zwave-device-skipping-the-vera-software/30607
