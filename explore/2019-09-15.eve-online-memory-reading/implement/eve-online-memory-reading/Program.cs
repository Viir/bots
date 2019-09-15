using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace eve_online_memory_reading
{
    class Program
    {
        /*
        This program reads from the memory of an EVE Online client process.
        The memory reading approach here is based on the example from https://forum.botengine.org/t/advanced-do-it-yourself-memory-reading-in-eve-online/68

        In contrast to the original code, this version also supports reading from a file containing a sample of the client process.
        This allows us to repeat the reading as often we want, without having to start an instance of the game client.
        For a guide on how to save a Windows process to a file, see https://forum.botengine.org/t/how-to-collect-samples-for-memory-reading-development/50

		Example command line:
		dotnet run -- --source="C:\path-to-a-process-sample-file.zip"  --output="C:\path\to\directory\with\write\access"
		*/
        static void Main(string[] args)
        {
            var outputPathParamName = "--output";

            (bool isPresent, string argumentValue) argumentFromParameterName(string parameterName)
            {
                var match =
                    args
                    .Select(arg => Regex.Match(arg, parameterName + "(=(.*)|)", RegexOptions.IgnoreCase))
                    .FirstOrDefault(match => match.Success);

                if (match == null)
                    return (false, null);

                if (match.Groups[1].Length < 1)
                    return (true, null);

                return (true, match?.Groups[2].Value);
            }

            var sourceArgument = argumentFromParameterName("--source").argumentValue;
            var outputPathArgument = argumentFromParameterName(outputPathParamName).argumentValue;

            IMemoryReader memoryReader = null;

            try
            {
                string sampleId = null;

                if (0 < sourceArgument?.Length)
                {
                    Console.WriteLine("I got the following source and will load from this file: '" + sourceArgument + "'");

                    var sampleFile = System.IO.File.ReadAllBytes(sourceArgument);

                    sampleId = CommonConversion.StringIdentifierFromValue(sampleFile);

                    Console.WriteLine("Loaded sample " + sampleId + " from '" + sourceArgument + "'");

                    var sampleStructure = BotEngine.ProcessMeasurement.MeasurementFromZipArchive(sampleFile);

                    memoryReader = new SampleMemoryReader(sampleStructure);
                }
                else
                {
                    Console.WriteLine("I did not receive a path to a sample file, so I will try to find a live EVE Online client process to read from.");

                    var MengeCandidateProcess = System.Diagnostics.Process.GetProcessesByName("exefile");

                    var gameClientProcess = MengeCandidateProcess.FirstOrDefault();

                    if (null == gameClientProcess)
                    {
                        Console.WriteLine("I did not find an EVE Online client process.");
                        return;
                    }

                    memoryReader = new ProcessMemoryReader(gameClientProcess);
                }

                var pythonMemoryReader = new PythonMemoryReader(memoryReader);

                var uiTreeRoot = EveOnline.UITreeRoot(pythonMemoryReader);

                if (null == uiTreeRoot)
                {
                    Console.WriteLine("Did not find the root of the UI tree.");
                    return;
                }

                Console.WriteLine("Found the root of the UI tree at {0} (0x{0:X})", uiTreeRoot.BaseAddress);

                var allNodes =
                    new UITreeNode[] { uiTreeRoot }
                    .Concat(uiTreeRoot.EnumerateChildrenTransitive(pythonMemoryReader)).ToArray();

                Console.WriteLine("Found {0} nodes in this UI tree.", allNodes.Length);

                var representationForReading =
                    System.Text.Encoding.UTF8.GetBytes(
                        Newtonsoft.Json.JsonConvert.SerializeObject(InspectUITreeNode(uiTreeRoot), Newtonsoft.Json.Formatting.Indented));

                Console.WriteLine("The representation for reading has the id '{0}'.",
                    CommonConversion.StringIdentifierFromValue(representationForReading));

                if (outputPathArgument == null)
                {
                    Console.WriteLine("Did not receive a path to write the results for reading. Add the '" +
                        outputPathParamName + "' argument to specify the directory to write the results to.");
                    return;
                }

                Console.WriteLine("I write the result to '{0}'.", outputPathArgument);
                System.IO.Directory.CreateDirectory(outputPathArgument);
                var outputFilePath = System.IO.Path.Combine(outputPathArgument, "memory-reading-from-sample-" + sampleId?.Substring(0, 8) + ".json");
                System.IO.File.WriteAllBytes(outputFilePath, representationForReading);
            }
            finally
            {
                (memoryReader as IDisposable)?.Dispose();
            }
        }

        static object InspectUITreeNode(UITreeNode node)
        {
            var children =
                node.children
                ?.Select(InspectUITreeNode)
                ?.ToList();

            var dictEntriesWithStringKey =
                node.Dict?.Slots
                ?.Where(slot => slot.KeyStr != null)
                ?.Select(slot =>
                {
                    return new
                    {
                        keyString = slot.KeyStr,
                        value_address = slot.me_value.ToString(),
                    };
                }).ToList();

            return new
            {
                address = node.BaseAddress,
                dictEntriesWithStringKey = dictEntriesWithStringKey,
                children = children,
            };
        }
    }
}
