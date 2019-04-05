//  This script demonstrates common functionality for botting in EVE Online, such as finding information in the game clients' memory and interacting with objects in the game window.
//  You can load and use it with the BotEngine Windows App from https://to.botengine.org/guide/windows-repl

#load "setup-sanderling.csx"

Console.WriteLine("I begin with reading from a process sample from a file, so we do not need a EVE Online client. If you do not yet have a process sample of an EVE Online client, you can follow the guide at https://forum.botengine.org/t/how-to-collect-samples-for-memory-reading-development/50 to get one.");

DemonstrateExploreProcessSample();

Console.WriteLine("Next step is to explore a live EVE Online client process, and send input.");

DemonstrateExploreLiveProcessAndSendInput();

void DemonstrateExploreProcessSample()
{
    var processSampleFilePath =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            @"EVE-Online-process-sample\my-eve-online-client-process-sample.zip");

    Console.WriteLine("Save the process sample to following path, then press any key to continue: '" + processSampleFilePath + "'");

    Console.ReadKey();

    if (!File.Exists(processSampleFilePath))
    {
        Console.WriteLine("I did not find a file at '" + processSampleFilePath + "', therefore I skip this part.");
        return;
    }

    Console.WriteLine("I try to load the process sample from '" + processSampleFilePath + "'...");

    var memoryReader = MemoryReaderFromProcessMeasurementFilePath(processSampleFilePath);

    Console.WriteLine("I begin to search for the root of the UI tree...");

    var uiTreeRoot = UITreeRootFromMemoryReader(memoryReader);

    Console.WriteLine("I read the partial python model of the UI tree...");

    var memoryMeasurementPartialPythonModel = PartialPythonModelFromUITreeRoot(memoryReader, uiTreeRoot);

    var allNodesFromMemoryMeasurementPartialPythonModel =
        EnumerateNodeFromTreeDFirst(
            memoryMeasurementPartialPythonModel,
            node => node.GetListChild()?.Cast<Optimat.EveOnline.AuswertGbs.UINodeInfoInTree>())
        .ToList();

    Console.WriteLine($"The tree in memoryMeasurementPartialPythonModel contains { allNodesFromMemoryMeasurementPartialPythonModel.Count } nodes");

    var sanderlingMemoryMeasurement = SanderlingMemoryMeasurementFromPartialPythonModel(memoryMeasurementPartialPythonModel);

    var allNodesFromSanderlingMemoryMeasurement =
        EnumerateReferencedSanderlingUIElementsTransitive(sanderlingMemoryMeasurement)
        .ToList();

    Console.WriteLine($"The sanderlingMemoryMeasurement contains { allNodesFromSanderlingMemoryMeasurement.Count } UI elements.");

    var parsedMemoryMeasurement = ParseSanderlingMemoryMeasurement(sanderlingMemoryMeasurement);

    //	At this point, you will find in the "parsedMemoryMeasurement" variable the contents read from the process measurement as they would appear in the Sanderling API Explorer.

    Console.WriteLine("Overview window read: " + (parsedMemoryMeasurement.WindowOverview?.Any() ?? false));

    var firstShipUIModule = parsedMemoryMeasurement.ShipUi.Module.FirstOrDefault();

    if (firstShipUIModule == null)
    {
        Console.WriteLine("I did not find any module in the ship UI. I skip the part exploring the ship module.");
        Console.WriteLine("If you want to test this part of the demo, use a process sample taken when in space and modules visible in the Ship UI.");
    }
    else
    {
        Console.WriteLine("The first ship UI module is located at " + NamesFromRawRectInt(firstShipUIModule.Region));

        var firstShipUIModuleInPartialPythonModel =
            allNodesFromMemoryMeasurementPartialPythonModel.First(node => node.PyObjAddress == firstShipUIModule.Id);

        var nodesOnPathToFirstShipUIModule =
            FindNodesOnPathFromTreeNodeToDescendant(
                memoryMeasurementPartialPythonModel,
                node => node.GetListChild()?.Cast<Optimat.EveOnline.AuswertGbs.UINodeInfoInTree>(),
                firstShipUIModuleInPartialPythonModel)
            .Select(nodeOnPath => new UINodeMostPopularProperties(nodeOnPath))
            .ToList();

        Console.WriteLine("In the tree of the partial python model, I found this path to first ship UI module: " + Newtonsoft.Json.JsonConvert.SerializeObject(nodesOnPathToFirstShipUIModule));
    }

    var textToSearch = "agent missions";

    var nodesWithMatchingText =
        allNodesFromMemoryMeasurementPartialPythonModel
        .Where(node => ("" + node.Text + node.SetText).ToLowerInvariant().Contains(textToSearch.ToLowerInvariant()))
        .ToList();

    Console.WriteLine($"Found {nodesWithMatchingText.Count} nodes containing the text '{ textToSearch}'.");

    Console.WriteLine("I search the tree with spatial criteria....");

    var regionToSearch =
        new Rectangle(left: 500, top: 850, right: 500 + 1, bottom: 850 + 1);

    var nodesInSearchRegion =
        allNodesFromMemoryMeasurementPartialPythonModel
        .Where(UITreeNodeRegionIntersectsRectangle(regionToSearch))
        .ToList();

    var nodesInSearchRegionPartsToPrint =
        nodesInSearchRegion
        .Select(node => new UINodeMostPopularProperties(node))
        .ToList();

    Console.WriteLine(
        "I found " + nodesInSearchRegion.Count() + " nodes at " + regionToSearch);
}

void DemonstrateExploreLiveProcessAndSendInput()
{
    Console.WriteLine("Make sure a character is selected in game, and the neocom is visible. Then press any key to continue.");

    Console.ReadKey();

    Console.WriteLine("I start looking for a running EVE Online client process.");

    var eveOnlineClientProcess = GetWindowsProcessesLookingLikeEVEOnlineClient().FirstOrDefault();

    if (eveOnlineClientProcess == null)
    {
        Console.WriteLine("I did not find an EVE Online client process. I skip this part.");
        return;
    }

    Console.WriteLine("I found an EVE Online client process with id " + eveOnlineClientProcess.Id);

    BotEngine.Interface.IMemoryReader memoryReaderForLiveProcess() => new BotEngine.Interface.ProcessMemoryReader(eveOnlineClientProcess.Id);

    Console.WriteLine("I begin to search for the root of the UI tree...");

    var uiTreeRoot = UITreeRootFromMemoryReader(memoryReaderForLiveProcess());

    Console.WriteLine("I read the memory measurement...");

    var memoryMeasurement = SanderlingMemoryMeasurementFromPartialPythonModel(
        PartialPythonModelFromUITreeRoot(memoryReaderForLiveProcess(), uiTreeRoot));

    var neocomButton = memoryMeasurement?.Neocom?.EveMenuButton;

    if (neocomButton == null)
    {
        Console.WriteLine("I did not find the neocom button.");
        return;
    }

    Console.WriteLine("I found the neocom button at " + NamesFromRawRectInt(neocomButton.Region));

    var motor = new Sanderling.Motor.WindowMotor(eveOnlineClientProcess.MainWindowHandle);

    var buttonLocation = Bib3.Geometrik.RectExtension.Center(neocomButton.Region);

    Console.WriteLine("I try to click with the left mouse button on the EVE Online client at " + buttonLocation.A + "|" + buttonLocation.B);

    motor.ActSequenceMotion(new BotEngine.Motor.Motion[]
    {
        new BotEngine.Motor.Motion(
            mousePosition: buttonLocation,
            mouseButtonDown: new[]{BotEngine.Motor.MouseButtonIdEnum.Left},
            windowToForeground: true),

        new BotEngine.Motor.Motion(
            mousePosition: buttonLocation,
            mouseButtonUp: new[]{BotEngine.Motor.MouseButtonIdEnum.Left},
            windowToForeground: true),
    });
}
