using RacingDSX.Config;
using RacingDSX.GameParsers;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace RacingDSX
{
    public enum InstructionTriggerMode : sbyte
    {
        NONE,
        RESISTANCE,
        VIBRATION
    }

    public class RacingDSXWorker
    {
        public struct RacingDSXReportStruct
        {
            public enum ReportType : ushort
            {
                VERBOSEMESSAGE = 0,
                NORACE = 1,
                RACING = 2
            }

            public enum RacingReportType : ushort
            {
                // 0 = Throttle vibration message
                THROTTLE_VIBRATION = 0,
                // 1 = Throttle message
                THROTTLE,
                // 2 = Brake vibration message
                BRAKE_VIBRATION,
                // 3 = Brake message
                BRAKE
            }
            public RacingDSXReportStruct(VerboseLevel level, ReportType type, RacingReportType racingType, string msg)
            {
                this.verboseLevel = level;
                this.type = type;
                this.racingType = racingType;
                this.message = msg;
            }

            public RacingDSXReportStruct(ReportType type, RacingReportType racingType, string msg)
            {
                this.type = type;
                this.racingType = racingType;
                this.message = msg;
            }

            public RacingDSXReportStruct(VerboseLevel level, ReportType type, string msg)
            {
                this.verboseLevel = level;
                this.type = type;
                this.message = msg;
            }

            public RacingDSXReportStruct(ReportType type, string msg)
            {
                this.type = type;
                this.message = msg;
            }

            public RacingDSXReportStruct(VerboseLevel level, string msg)
            {
                this.verboseLevel = level;
                this.type = ReportType.VERBOSEMESSAGE;
                this.message = msg;
            }

            public RacingDSXReportStruct(string msg)
            {
                this.type = ReportType.VERBOSEMESSAGE;
                this.message = msg;
            }

            public ReportType type = 0;
            public RacingReportType racingType = 0;
            public string message = string.Empty;
            public VerboseLevel verboseLevel = VerboseLevel.Limited;
        }

        private RacingDSX.Config.Config settings;
        private IProgress<RacingDSXReportStruct> progressReporter;
        private Parser parser;

        // How long we wait on a telemetry packet before deciding the game stopped sending.
        // FH6 cuts the stream entirely in menus, pauses, replays and after a race, where
        // FH4/FH5 kept streaming with IsRaceOn = 0.
        private const int TelemetryIdleTimeoutMs = 500;
        // Resend an unchanged payload at least this often so DSX can't drift out of sync.
        private const int KeepAliveMs = 1000;

        private readonly Stopwatch sendClock = Stopwatch.StartNew();
        private long nextSendDueMs = 0;
        private string lastSentJson = null;
        private long lastSentMs = long.MinValue;
        private bool bTelemetryIdle = false;
        private bool bReceivedAnyPacket = false;
        private readonly HashSet<int> reportedUnknownBufferLengths = new HashSet<int>();
        // Strongest trigger vibration seen since the last send, per trigger (null = none).
        private Instruction heldRightVibration = null;
        private Instruction heldLeftVibration = null;

        // JSON serialization options
        private static readonly JsonSerializerOptions jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        };

        public RacingDSXWorker(RacingDSX.Config.Config currentSettings, IProgress<RacingDSXReportStruct> progressReporter)
        {
            settings = currentSettings;
            this.progressReporter = progressReporter;
        }

        public void SetSettings(RacingDSX.Config.Config currentSettings)
        {
            lock(this)
            {
                settings = currentSettings;
            }
        }

        void SendData()
        {
            // IsRaceOn() carries the RPM accumulator, so it has to run on every telemetry
            // frame even when we are not going to talk to DSX this tick.
            bool bRaceOn = parser.IsRaceOn();
            bool bSendDue = IsSendDue();

            // No race = normal triggers
            if (!bRaceOn)
            {
                heldRightVibration = null;
                heldLeftVibration = null;

                if (!bSendDue)
                {
                    return;
                }

                ReportableInstruction preRace = parser.GetPreRaceInstructions();
                Report(preRace);
                Send(preRace.Instructions);
                return;
            }

            // Run the filters against every telemetry sample so the EWMA smoothing still
            // sees the full stream, then ship only the newest result at the capped rate.
            ReportableInstruction rightTrigger = parser.GetInRaceRightTriggerInstruction();
            ReportableInstruction leftTrigger = parser.GetInRaceLeftTriggerInstruction();
            ReportableInstruction lightBar = parser.GetInRaceLightbarInstruction();

            HoldVibration(rightTrigger, ref heldRightVibration);
            HoldVibration(leftTrigger, ref heldLeftVibration);

            if (!bSendDue)
            {
                return;
            }

            ApplyHeldVibration(rightTrigger, ref heldRightVibration);
            ApplyHeldVibration(leftTrigger, ref heldLeftVibration);

            Report(rightTrigger);
            Report(leftTrigger);
            Report(lightBar);

            // One datagram carrying all three instructions instead of three datagrams.
            // DSX applies them in a single pass and it cuts the message rate by 3x.
            Send(Combine(rightTrigger, leftTrigger, lightBar));
        }

        // Throttles the stream we push at DSX. Returns true at most DSXUpdateRateHz times
        // per second; consuming the slot here (rather than in Send) keeps us from
        // re-serializing the same payload on every skipped frame.
        private bool IsSendDue()
        {
            long nowMs = sendClock.ElapsedMilliseconds;
            if (nowMs < nextSendDueMs)
            {
                return false;
            }

            int rateHz = Math.Clamp(settings.DSXUpdateRateHz, 5, 120);
            long intervalMs = 1000 / rateHz;

            // Restart the window from now instead of accumulating it, so a stall in the
            // game (loading screen, alt-tab) cannot leave us owing a burst of packets.
            nextSendDueMs = nowMs + intervalMs;
            return true;
        }

        // A wheel lock or wheelspin can last a frame or two at FH6's frame rate, which is shorter
        // than one send slot, so the rate limit used to drop most of them and the trigger never
        // kicked. Remember the strongest vibration since the last send and deliver it at the next
        // slot even if grip has already come back. This keeps the outbound rate unchanged.
        private static void HoldVibration(ReportableInstruction trigger, ref Instruction held)
        {
            Instruction current = FirstInstruction(trigger);
            if (!IsVibration(current))
            {
                return;
            }

            if (held == null || VibrationStrength(current) >= VibrationStrength(held))
            {
                // Parameters is replaced, never mutated, by the parser each frame, so sharing
                // the array is safe; the Instruction object itself is reused and is not.
                held = new Instruction(current.Type) { Parameters = current.Parameters };
            }
        }

        private static void ApplyHeldVibration(ReportableInstruction trigger, ref Instruction held)
        {
            if (held != null && !IsVibration(FirstInstruction(trigger)))
            {
                trigger.Instructions = new Instruction[] { held };
            }

            held = null;
        }

        private static Instruction FirstInstruction(ReportableInstruction reportableInstruction)
        {
            Instruction[] instructions = reportableInstruction?.Instructions;
            return instructions != null && instructions.Length > 0 ? instructions[0] : null;
        }

        // Vibration is CustomTriggerValue mode: [controller, trigger, mode, customMode, frequency, ...]
        private static bool IsVibration(Instruction instruction)
        {
            object[] parameters = instruction?.Parameters;
            return parameters != null
                && parameters.Length > 4
                && Convert.ToInt32(parameters[2]) == (int)TriggerMode.CustomTriggerValue;
        }

        private static double VibrationStrength(Instruction instruction)
        {
            return Convert.ToDouble(instruction.Parameters[4]);
        }

        private void Report(ReportableInstruction reportableInstruction)
        {
            if (progressReporter == null)
            {
                return;
            }

            reportableInstruction.RacingDSXReportStructs.ForEach(x =>
            {
                if (x.verboseLevel <= settings.VerboseLevel)
                {
                    progressReporter.Report(x);
                }
            });
        }

        private static Instruction[] Combine(params ReportableInstruction[] reportableInstructions)
        {
            List<Instruction> instructions = new List<Instruction>();
            foreach (ReportableInstruction reportableInstruction in reportableInstructions)
            {
                if (reportableInstruction?.Instructions != null)
                {
                    instructions.AddRange(reportableInstruction.Instructions);
                }
            }

            return instructions.ToArray();
        }

        // Called when the game has gone quiet. FH6 stops sending telemetry outright in
        // menus, pauses, replays and after a race, so without this the triggers stay
        // latched in whatever state the last frame of driving left them.
        private void OnTelemetryIdle()
        {
            if (!bReceivedAnyPacket || bTelemetryIdle)
            {
                return;
            }

            bTelemetryIdle = true;

            if (settings.VerboseLevel > VerboseLevel.Off && progressReporter != null)
            {
                progressReporter.Report(new RacingDSXReportStruct("Telemetry stopped. Releasing triggers."));
            }

            Instruction rightTrigger = new Instruction(InstructionType.TriggerUpdate)
            {
                Parameters = new object[] { 0, Trigger.Right, TriggerMode.Normal, 0, 0 }
            };
            Instruction leftTrigger = new Instruction(InstructionType.TriggerUpdate)
            {
                Parameters = new object[] { 0, Trigger.Left, TriggerMode.Normal, 0, 0 }
            };

            Send(new Instruction[] { leftTrigger, rightTrigger });
        }

        static UdpClient senderClient;
        static IPEndPoint endPoint;

        // Connect to DSX
        void Connect()
        {
            senderClient = new UdpClient();
            var portNumber = settings.DSXPort;

            if (progressReporter != null)
            {
                progressReporter.Report(new RacingDSXReportStruct("DSX is using port " + portNumber + ". Attempting to connect.."));
            }

            if (!int.TryParse(portNumber.ToString(), out int portNum))
            {
                if (progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct($"DSX provided a non-numerical port! Using configured default ({settings.DSXPort})."));
                }
                portNum = settings.DSXPort;
            }

            endPoint = new IPEndPoint(IPAddress.Loopback, portNum);

            try
            {
                senderClient.Connect(endPoint);
            }
            catch (Exception e)
            {
                if (progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct("Error connecting: " + e.Message));

                    if (e is SocketException)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Couldn't access port. " + e.Message));
                    }
                    else if (e is ObjectDisposedException)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Connection object closed. Restart the application."));
                    }
                    else
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Unknown error: " + e.Message));
                    }
                }
            }
        }

        // Rebuild the sender socket after an error and force the next payload through,
        // since DSX has almost certainly lost whatever state we last handed it.
        void ReconnectSender()
        {
            try
            {
                senderClient?.Close();
                senderClient?.Dispose();
            }
            catch (Exception)
            {
                // The socket is already unusable; nothing to salvage.
            }

            lastSentJson = null;

            // Don't resurrect the socket if we are on the way out.
            if (bRunning)
            {
                Connect();
            }
        }

        //Send Data to DSX
        void Send(Instruction[] instructions)
        {
            if (instructions == null || instructions.Length == 0)
            {
                return;
            }

            if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
            {
                progressReporter.Report(new RacingDSXReportStruct($"Converting Message to JSON"));
            }

            try
            {
                Packet data = new Packet();
                data.Instructions = instructions;

                string jsonString = JsonSerializer.Serialize(data, jsonOptions);

                // Nothing changed since the last update, so there is no reason to make DSX
                // write another HID report. The keep-alive covers the case where DSX was
                // restarted and lost the state we last gave it.
                long nowMs = sendClock.ElapsedMilliseconds;
                if (jsonString == lastSentJson && nowMs - lastSentMs < KeepAliveMs)
                {
                    return;
                }

                lastSentJson = jsonString;
                lastSentMs = nowMs;

                byte[] RequestData = Encoding.ASCII.GetBytes(jsonString);

                if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct($"{Encoding.ASCII.GetString(RequestData)}"));
                }

                if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct($"Sending Message to DSX..."));
                }

                senderClient.Send(RequestData, RequestData.Length);

                if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct($"Message sent to DSX"));
                }
            }
            catch (JsonException je)
            {
                if (progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct($"JSON Serialization Error: {je.Message}"));
                }
            }
            catch (Exception e)
            {
                if (progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct("Error Sending Message: "));
                }

                if (e is SocketException)
                {
                    if (progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Couldn't Access Port. " + e.Message));
                    }

                    // A connected UDP socket surfaces the ICMP "port unreachable" that DSX
                    // leaves behind when it restarts. Rebuilding the socket clears the
                    // pending error; tearing the whole worker down here meant RacingDSX
                    // went silent until the user restarted it.
                    ReconnectSender();
                }
                else if (e is ObjectDisposedException)
                {
                    if (progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Connection closed. Restarting..."));
                    }
                    ReconnectSender();
                }
                else
                {
                    if (progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Unknown Error: " + e.Message));
                    }
                }
            }
        }

        static IPEndPoint ipEndPoint = null;
        static UdpClient client = null;
        
        public struct UdpState
        {
            public UdpClient u;
            public IPEndPoint e;

            public UdpState(UdpClient u, IPEndPoint e)
            {
                this.u = u;
                this.e = e;
            }
        }

        protected bool bRunning = false;

        public void Run()
        {
            bRunning = true;

            // This worker instance is reused across restarts, so clear the per-run state.
            nextSendDueMs = 0;
            lastSentJson = null;
            lastSentMs = long.MinValue;
            bTelemetryIdle = false;
            bReceivedAnyPacket = false;
            heldRightVibration = null;
            heldLeftVibration = null;

            try
            {
                Connect();
                if (settings.ActiveProfile == null)
                {
                    if (progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("No active profile selected. Exiting..."));
                    }
                    return;
                }

                switch (settings.ActiveProfile.GameType)
                {
                    case GameTypes.Forza:
                        parser = new ForzaParser(settings);
                        break;
                    case GameTypes.Dirt:
                        parser = new DirtParser(settings);
                        break;
                    default:
                        parser = new NullParser(settings);
                        break;
                }

                ipEndPoint = new IPEndPoint(IPAddress.Loopback, settings.ActiveProfile.gameUDPPort);
                client = new UdpClient(settings.ActiveProfile.gameUDPPort);
                client.Client.ReceiveTimeout = TelemetryIdleTimeoutMs;

                while (bRunning)
                {
                    byte[] resultBuffer = null;

                    try
                    {
                        resultBuffer = client.Receive(ref ipEndPoint);
                    }
                    catch (SocketException se) when (se.SocketErrorCode == SocketError.TimedOut)
                    {
                        OnTelemetryIdle();
                        continue;
                    }

                    if (resultBuffer == null)
                        continue;

                    bReceivedAnyPacket = true;
                    bTelemetryIdle = false;

                    // FH6 emits at the game's frame rate, so if anything briefly stalls this
                    // loop the kernel buffer queues packets and we would spend the next
                    // frames acting on stale telemetry. Keep only the newest one.
                    while (client.Available > 0)
                    {
                        byte[] newerBuffer = client.Receive(ref ipEndPoint);
                        if (newerBuffer != null && newerBuffer.Length > 0)
                        {
                            resultBuffer = newerBuffer;
                        }
                    }

                    if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("received Message from Forza!"));
                    }

                    if (!AdjustToBufferType(resultBuffer.Length))
                    {
                        continue;
                    }

                    parser.ParsePacket(resultBuffer);
                    if (settings.VerboseLevel > VerboseLevel.Limited && progressReporter != null)
                    {
                        progressReporter.Report(new RacingDSXReportStruct("Data Parsed"));
                    }

                    SendData();
                }
            }
            catch (Exception e)
            {
                if (progressReporter != null)
                {
                    progressReporter.Report(new RacingDSXReportStruct("Application encountered an exception: " + e.Message));
                }
            }
            finally
            {
                Stop();
            }
        }

        public void Stop()
        {
            bRunning = false;

            if (settings.VerboseLevel > VerboseLevel.Off && progressReporter != null)
            {
                progressReporter.Report(new RacingDSXReportStruct($"Cleaning Up"));
            }

            if (client != null)
            {
                client.Close();
                client.Dispose();
            }
            if (senderClient != null)
            {
                senderClient.Close();
                senderClient.Dispose();
            }

            if (settings.VerboseLevel > VerboseLevel.Off)
            {
                progressReporter.Report(new RacingDSXReportStruct($"Cleanup Finished. Exiting..."));
            }
        }

        bool AdjustToBufferType(int bufferLength)
        {
            switch (bufferLength)
            {
                case 232: // FM7 sled
                    return false;
                case 264: // Dirt Rally 1
                    FMData.BufferOffset = 0;
                    return true;
                case 311: // FM7 dash
                    FMData.BufferOffset = 0;
                    return true;
                case 331: // FM8 dash
                    FMData.BufferOffset = 0;
                    return true;
                case 324: // FH4 / FH5 / FH6
                    // FH6's layout is byte-for-byte identical to FH4/FH5. The 12 bytes that
                    // this offset skips past are the CarGroup, SmashableVelDiff and
                    // SmashableMass fields Microsoft finally documented for FH6.
                    FMData.BufferOffset = 12;
                    return true;
                default:
                    // Report each unknown size once so a future game patch that changes the
                    // wire format is visible instead of just looking like a dead app.
                    if (progressReporter != null && reportedUnknownBufferLengths.Add(bufferLength))
                    {
                        progressReporter.Report(new RacingDSXReportStruct(
                            $"Ignoring telemetry packet of unsupported size {bufferLength} bytes."));
                    }
                    return false;
            }
        }
    }
}