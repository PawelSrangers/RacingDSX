![GitHub all releases](https://img.shields.io/github/downloads/cosmii02/racingDSX/total)

Tested and confirmed to work with DSX v2 and v3.1

🔺🔺 It is REQUIRED to install .NET8 for racingDSX to work at all!🔺🔺           
Download .NET8.0 from the link here: https://dotnet.microsoft.com/en-us/download



# Setting up DiRT Rally 1 / 2 for UDP Connection:
1. Go to `C:\Users\<USER>\Documents\My Games\DiRT Rally X.0\hardwaresettings`;
2. Open `hardware_settings_config` file with your favorite text editor;
3. Find for **udp** tag and configure as shown below:
      ```xml
      <motion_platform>
           ...
           <udp enabled="true" extradata="3" ip="127.0.0.1" port="5300" delay="1" />
           ...
      </motion_platform>
      ```
   - **enabled = true**
   - **extradata = 3**
   - **port = 5300**

🔺🔺 Note for Forza Horizon 4 and Forza Motorsport 7 (THIS IS REQUIRED FOR IT TO WORK) 🔺🔺
1. Install [Window 8 AppContainer Loopback Utility](https://telerik-fiddler.s3.amazonaws.com/fiddler/addons/enableloopbackutility.exe)
2. Start the utility (if it shows a message about orphan sid, you can safely ignore it)
3. Make sure that Forza Horizon 4 / Motorsport 7 are checked
4. Save changes
In case the above do not work for you run the below command in Powershell as admin, the command enables udp loopback without needing the utility.

Forza Horizon 4: ```CheckNetIsolation LoopbackExempt -a -n="Microsoft.SunriseBaseGame_8wekyb3d8bbwe"```

Forza Motorsport 7: I do not have FM7 to get the ID, sorry :)

-----------------------------------------------------------------------------------------------------------------------------------------

Step by step instructions for Forza Horizon 5:
1. Download latest version of RacingDSX from releases https://github.com/cosmii02/RacingDSX/releases
2. extract the zip file to a folder (For example desktop)
3. Run RacingDSX exe
![image](https://user-images.githubusercontent.com/27782168/183417053-33676d94-f137-454b-ad7b-78066f71f6d2.png)
4. allow firewall prompts if they show up
5. Open DSX
6. Run forza horizon 5
7. Go to settings and enable DATA OUT and set ip to 127.0.0.1 and DATA OUT IP PORT to 5300
![image](https://user-images.githubusercontent.com/27782168/183418210-145b6701-f1f7-4783-91ba-7a1893294601.png)
8. In DSX make sure UDP is enabled, go to settings, click controller and then click networking. UDP has to be enabled and must be listening to port 6969


-----------------------------------------------------------------------------------------------------------------------------------------

Step by step instructions for Forza Horizon 6:

Setup is the same as Forza Horizon 5 (HUD & Gameplay -> Telemetry Output -> Data Out ON, IP 127.0.0.1, port 5300).
The packet format is identical to FH4/FH5, so no extra configuration is needed.

Two things differ from FH5 and are handled by RacingDSX automatically:

1. **FH6 sends telemetry at the game's frame rate**, not at a fixed 60 Hz. At 120-240 fps that is
   two to four times the FH5 rate. Forwarding all of it to DSX floods its HID output queue, which
   stalls DSX's controller thread and leaves the emulated pad latched on its last state - the
   symptom is steering or throttle "sticking" at a random moment even though you released the stick.
   RacingDSX now caps the update rate it sends to DSX and packs all instructions into one message.
   The cap lives in `RacingDSX.json` as `DSXUpdateRateHz` (default 30). **If you use the controller
   over Bluetooth and still see sticking, lower it to 20 or 15.** Raising it above 60 is not
   recommended.

2. **FH6 stops sending telemetry entirely** in menus, pauses, replays and after a race, where FH4/FH5
   kept streaming with `IsRaceOn = 0`. RacingDSX now detects the silence and releases the triggers
   instead of leaving them stiff.

-----------------------------------------------------------------------------------------------------------------------------------------
Note for Forza Motorsport 7
1. Launch the game and head to the HUD options menu
2. Set Data Out to ON
3. Set Data Out IP Address to 127.0.0.1 (localhost)
4. Set Data Out IP Port to 5300
5. Set Data Out Packet Format to CAR DASH









## Thanks and Credits

[DualSenseX](https://github.com/Paliverse/DualSenseX)

[Forza-Telemetry](https://github.com/austinbaccus/forza-telemetry/tree/main/ForzaCore)

[patmagauran](https://github.com/patmagauran)
