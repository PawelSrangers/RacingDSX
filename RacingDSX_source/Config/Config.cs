using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace RacingDSX.Config
{
    public class Config
    {
        public bool DisableAppCheck { get; set; }
        public VerboseLevel VerboseLevel { get; set; } = VerboseLevel.Off;
        public Dictionary<String, Profile> Profiles { get; set; } = new Dictionary<String, Profile>();
        [JsonIgnore]
        public Profile ActiveProfile { get; set; } = null;

        public int DSXPort { get; set; } = 6969; // This sets the default dsx port

        // Upper limit on how many instruction packets per second we push at DSX.
        // Forza Horizon 6 emits telemetry at the game's frame rate (~130+/s) instead of
        // FH4/FH5's fixed 60/s. Forwarding all of it floods DSX's HID output queue, which
        // stalls its controller thread and leaves the emulated pad latched on its last
        // state (sticks appear stuck). Lower this to 20 if you play over Bluetooth.
        public int DSXUpdateRateHz { get; set; } = 30;

        public String DefaultProfile { get; set; } = "Forza";
    }
}
