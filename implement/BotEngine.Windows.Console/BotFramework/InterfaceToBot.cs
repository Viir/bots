using System;

namespace BotEngine.Windows.Console.BotFramework.InterfaceToBot
{
    /*
     * Interface structures as shown at https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
     * */

    public class BotEventAtTime
    {
        public Int64 timeInMilliseconds;

        public BotEvent @event;
    }

    public class BotEvent
    {
        public Result<string, MemoryMeasurement> memoryMeasurementFinished;
    }

    public class Result<Err, Ok>
    {
        public Err err;

        public Ok ok;
    }

    public class MemoryMeasurement
    {
        public string reducedWithNamedNodesJson;
    }

    public class BotRequest
    {
        public string reportStatus;

        public Int64? takeMemoryMeasurementAtTimeInMilliseconds;

        public BotEffect effect;

        public object finishSession;
    }

    public class BotEffect
    {
        public SimpleBotEffect simpleEffect;
    }

    public class SimpleBotEffect
    {
        public SimpleMouseClickAtLocation simpleMouseClickAtLocation;
    }

    public class SimpleMouseClickAtLocation
    {
        public Location location;

        public MouseButton mouseButton;
    }

    public class Location
    {
        public Int64 x, y;
    }

    public enum MouseButton
    {
        left, right,
    }

    public class BotResponse
    {
        public string decodeError;

        public DecodeSuccess decodeSuccess;

        public class DecodeSuccess
        {
            public BotRequest[] botRequests;
        }
    }
}
