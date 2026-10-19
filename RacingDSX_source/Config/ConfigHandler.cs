using RacingDSX.GameParsers;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace RacingDSX.Config
{
    public class ConfigHandler
    {
        //Methods to read config file
        //Method to initialize config file (Using default values), need to account for the different default profiles
        //Method to write config file
        //Singleton access to config data
        private static readonly String configFilePath = "RacingDSX.json";
        private static Config configData;
        // Set when RacingDSX.json exists but could not be read. The file is then left alone for the
        // whole session: writing defaults over it would wipe the user's tuned settings.
        private static bool bConfigReadOnly = false;

        private static void InitializeConfig()
        {
            configData ??= ReadConfigFromDisk();
            configData ??= new Config();
            configData = AddDefaultProfiles(configData);
            SaveConfig();
        }




        private static Config AddDefaultProfiles(Config config)
        {
            config.Profiles ??= new Dictionary<string, Profile>();
            if (!config.Profiles.ContainsKey("Forza"))
            {
                Profile profile = new Profile
                {
                    Name = "Forza",
                    gameUDPPort = 5300,
                    GameType = GameTypes.Forza,
                };
                profile.executableNames.AddRange(new string[] { "ForzaHorizon6", "ForzaHorizon5", "ForzaHorizon4", "ForzaMotorsport7", "forza_gaming.desktop.x64_release_final", "forza_steamworks_release_final" });
                config.Profiles.Add("Forza", profile);
            }
            if (!config.Profiles.ContainsKey("Dirt"))
            {
                Profile profile = new Profile
                {
                    Name = "Dirt",
                    gameUDPPort = 5300,
                    GameType = GameTypes.Dirt
                };
                profile.throttleSettings.GripLossValue = 0.4f;
                profile.executableNames.AddRange(new string[] { "drt", "dirtrally2"});
                config.Profiles.Add("Dirt", profile);
            }

            return config;
        }

        private static Config ReadConfigFromDisk()
        {

            if (!File.Exists(configFilePath))
            {
                return null;
            }

            Exception error = null;
            // A sharing violation (file open in an editor, antivirus scan) is usually gone within a
            // second, so retry I/O errors briefly. Bad JSON will not fix itself; fail at once.
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    string jsonString = File.ReadAllText(configFilePath);
                    Config config = JsonSerializer.Deserialize<Config>(jsonString);
                    if (config != null)
                    {
                        return config;
                    }
                    error = new InvalidDataException("the file contains no settings");
                    break;
                }
                catch (IOException e)
                {
                    error = e;
                    System.Threading.Thread.Sleep(200);
                }
                catch (Exception e)
                {
                    error = e;
                    break;
                }
            }

            bConfigReadOnly = true;
            MessageBox.Show(
                $"{Path.GetFullPath(configFilePath)} could not be read:\r\n{error.Message}\r\n\r\n" +
                "The file was left untouched. RacingDSX is running with default settings, and changes " +
                "made in this session will not be saved. Fix or remove the file and restart RacingDSX.",
                "RacingDSX settings not loaded", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return null;
        }
        private static void WriteConfigToDisk()
        {
            if (bConfigReadOnly)
            {
                return;
            }
            try
            {
                // Write a temp file and move it over the real one, so a crash mid-write leaves the
                // old file intact instead of a truncated one that would fail to load next start.
                string jsonString = JsonSerializer.Serialize(configData);
                string tempPath = configFilePath + ".tmp";
                File.WriteAllText(tempPath, jsonString);
                File.Move(tempPath, configFilePath, true);
            } catch (Exception)
            {

            }
        }

        public static void SaveConfig()
        {
            WriteConfigToDisk();

        }
        
        public static Config GetConfig()
        {
            if (configData == null)
            {
                InitializeConfig();
            }
            return configData;
        }
    }
}
