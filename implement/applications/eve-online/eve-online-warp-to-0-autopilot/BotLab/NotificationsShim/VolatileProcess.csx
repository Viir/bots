#r "mscorlib"
#r "netstandard"
#r "System"
#r "System.Collections.Immutable"
#r "System.IO.Compression"
#r "System.Net"
#r "System.Linq"
#r "System.Text.Json"

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;


class Request
{
    public ConsoleBeepStructure[] EffectConsoleBeepSequence { set; get; }

    public struct ConsoleBeepStructure
    {
        public int frequency { set; get; }

        public int durationInMs { set; get; }
    }
}

class Response
{
    public object CompletedOtherEffect;
}

string serialRequest(string serializedRequest)
{
    var requestStructure = System.Text.Json.JsonSerializer.Deserialize<Request>(serializedRequest);

    var response = request(requestStructure);

    return SerializeToJsonForBot(response);
}

Response request(Request request)
{
    if (request?.EffectConsoleBeepSequence != null)
    {
        foreach (var beep in request?.EffectConsoleBeepSequence)
        {
            if (beep.frequency == 0) //  Avoid exception "The frequency must be between 37 and 32767."
                System.Threading.Thread.Sleep(beep.durationInMs);
            else
                System.Console.Beep(beep.frequency, beep.durationInMs);
        }

        return new Response
        {
            CompletedOtherEffect = new object(),
        };
    }

    return null;
}

string SerializeToJsonForBot<T>(T value) =>
    System.Text.Json.JsonSerializer.Serialize(value);


string InterfaceToHost_Request(string request)
{
    return serialRequest(request);
}
