//  This script defines common functions for botting in EVE Online.
//  You can load and use it with the BotEngine Windows App from https://to.botengine.org/guide/windows-repl

#r "Bib3.dll"
#r "BotEngine.Interface.dll"
#r "BotEngine.Common.dll"
#r "Sanderling.Interface.dll"
#r "Sanderling.dll"
#r "Sanderling.MemoryReading.dll"
#r "Newtonsoft.Json.dll"
#r "WindowsInput.dll"
#r "Sanderling.ExploreProcessMeasurement.exe"

using System.Collections.Immutable;
using System.Security.Cryptography;
using Sanderling.ExploreProcessMeasurement;

var assembliesToReport = new[]
    {
        typeof(Optimat.EveOnline.GbsAstInfo),
        typeof(Sanderling.Interface.MemoryStruct.IMemoryMeasurement),
        typeof(Sanderling.Parse.IMemoryMeasurement)
    }
    .Select(clrType => clrType.Assembly)
    .Distinct()
    .ToImmutableList();

byte[] SHA256FromByteArray(byte[] array)
{
    using (var hasher = new SHA256Managed())
        return hasher.ComputeHash(buffer: array);
}

string ToStringBase16(byte[] array) => BitConverter.ToString(array).Replace("-", "");

/*
Console.WriteLine(
    "Loaded assemblies: " +
    String.Join(", ", assembliesToReport.Select(assembly => assembly.FullName + " v" + ToStringBase16(SHA256FromByteArray(File.ReadAllBytes(assembly.CodeBase))))));
*/

/*
Make it easy to use popular Sanderling functions:
Define shortcuts and memorable names below, based on the demonstration at https://github.com/Arcitectus/Sanderling/blob/cb33a8be206c67d382dc283d0aeedddcbb77b08c/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L12-L53
*/

BotEngine.Interface.IMemoryReader MemoryReaderFromProcessMeasurementFilePath(string windowsProcessMeasurementFilePath)
{
    var windowsProcessMeasurementZipArchive = System.IO.File.ReadAllBytes(windowsProcessMeasurementFilePath);

    var windowsProcessMeasurement = BotEngine.Interface.Process.Snapshot.Extension.SnapshotFromZipArchive(windowsProcessMeasurementZipArchive);

    var memoryReader = new BotEngine.Interface.Process.Snapshot.SnapshotReader(windowsProcessMeasurement?.ProcessSnapshot?.MemoryBaseAddressAndListOctet);

    Console.WriteLine("Loaded sample " + ToStringBase16(SHA256FromByteArray(windowsProcessMeasurementZipArchive)));

    return memoryReader;
}

BotEngine.Interface.IMemoryReader MemoryReaderFromLiveProcessId(int processId) =>
    new BotEngine.Interface.ProcessMemoryReader(processId);

Optimat.EveOnline.MemoryAuswertWurzelSuuce UITreeRootFromMemoryReader(
    BotEngine.Interface.IMemoryReader memoryReader)
{
    Console.WriteLine("I am searching the root of the UI tree now. This can take several seconds. You only need to do this once per game client process, because the address of the root does not change during a session.");
    return Sanderling.ExploreProcessMeasurement.Extension.SearchForUITreeRoot(memoryReader);
}

Optimat.EveOnline.AuswertGbs.UINodeInfoInTree PartialPythonModelFromUITreeRoot(
    BotEngine.Interface.IMemoryReader memoryReader,
    Optimat.EveOnline.MemoryAuswertWurzelSuuce uiTreeRoot) =>
    Optimat.EveOnline.AuswertGbs.Extension.SictAuswert(
        Sanderling.ExploreProcessMeasurement.Extension.ReadUITreeFromRoot(memoryReader, uiTreeRoot));

Sanderling.Interface.MemoryStruct.IMemoryMeasurement SanderlingMemoryMeasurementFromPartialPythonModel(
    Optimat.EveOnline.GbsAstInfo partialPython) =>
    Optimat.EveOnline.AuswertGbs.Extension.SensorikScnapscusKonstrukt(partialPython, null);

Sanderling.Parse.IMemoryMeasurement ParseSanderlingMemoryMeasurement(
    Sanderling.Interface.MemoryStruct.IMemoryMeasurement memoryMeasurement) =>
    Sanderling.Parse.Extension.Parse(memoryMeasurement);

IEnumerable<T> EnumerateNodeFromTreeDFirst<T>(
    T root,
    Func<T, IEnumerable<T>> callbackEnumerateChildInNode,
    int? depthMax = null,
    int? depthMin = null) =>
    Bib3.Extension.EnumerateNodeFromTreeDFirst(root, callbackEnumerateChildInNode, depthMax, depthMin);

IEnumerable<Sanderling.Interface.MemoryStruct.IUIElement> EnumerateReferencedSanderlingUIElementsTransitive(
    object parent) =>
    parent == null ? null :
    Sanderling.Interface.MemoryStruct.Extension.EnumerateReferencedUIElementTransitive(parent)
    .Distinct();

struct Rectangle
{
    public Rectangle(Int64 left, Int64 top, Int64 right, Int64 bottom)
    {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }

    readonly public Int64 top, left, bottom, right;

    override public string ToString() =>
        Newtonsoft.Json.JsonConvert.SerializeObject(this);
}

struct UINodeMostPopularProperties
{
    public readonly Int64? pythonObjectAddress;

    public readonly string pythonTypeName;

    public readonly Rectangle? region;

    public UINodeMostPopularProperties(Optimat.EveOnline.AuswertGbs.UINodeInfoInTree uiNode)
    {
        pythonObjectAddress = uiNode.PyObjAddress;
        pythonTypeName = uiNode.PyObjTypName;

        var uiNodeRegion = RawRectFromUITreeNode(uiNode);

        region =
            uiNodeRegion.HasValue ? (Rectangle?)NamesFromRawRectInt(uiNodeRegion.Value) : null;
    }
}

static Rectangle NamesFromRawRectInt(Bib3.Geometrik.RectInt raw) =>
    new Rectangle(left: raw.Min0, top: raw.Min1, right: raw.Max0, bottom: raw.Max1);

Func<Optimat.EveOnline.AuswertGbs.UINodeInfoInTree, bool> UITreeNodeRegionIntersectsRectangle(Rectangle rectangle) =>
    uiNode =>
    {
        var uiNodeRegion = RawRectFromUITreeNode(uiNode);

        if (!uiNodeRegion.HasValue)
            return false;

        return
            !Bib3.Geometrik.RectExtension.IsEmpty(Bib3.Geometrik.Geometrik.Intersection(
                uiNodeRegion.Value,
                Bib3.Geometrik.RectInt.FromMinPointAndMaxPoint(
                    new Bib3.Geometrik.Vektor2DInt(rectangle.left, rectangle.top),
                    new Bib3.Geometrik.Vektor2DInt(rectangle.right, rectangle.bottom))));
    };

static Bib3.Geometrik.RectInt? RawRectFromUITreeNode(Optimat.EveOnline.AuswertGbs.UINodeInfoInTree node) =>
    Optimat.EveOnline.AuswertGbs.Glob.FläceAusGbsAstInfoMitVonParentErbe(node);

Func<Sanderling.Interface.MemoryStruct.IUIElement, bool> UIElementRegionIntersectsRectangle(Rectangle rectangle) =>
    uiElement =>
    !Bib3.Geometrik.RectExtension.IsEmpty(Bib3.Geometrik.Geometrik.Intersection(
        uiElement.Region,
        Bib3.Geometrik.RectInt.FromMinPointAndMaxPoint(
            new Bib3.Geometrik.Vektor2DInt(rectangle.left, rectangle.top),
            new Bib3.Geometrik.Vektor2DInt(rectangle.right, rectangle.bottom))));

Process[] GetWindowsProcessesLookingLikeEVEOnlineClient() =>
    Process.GetProcessesByName("exefile");

IReadOnlyList<T> FindNodesOnPathFromTreeNodeToDescendant<T>(T pathRoot, Func<T, IEnumerable<T>> getChildrenFromNode, T descendant)
    =>
    FindNodesOnPathFromTreeNodeToDescendantMatchingPredicate(
        pathRoot,
        getChildrenFromNode,
        candidate => ((object)candidate == null && (object)descendant == null) || (candidate?.Equals(descendant) ?? false));

IReadOnlyList<T> FindNodesOnPathFromTreeNodeToDescendantMatchingPredicate<T>(
    T pathRoot,
    Func<T, IEnumerable<T>> getChildrenFromNode,
    Func<T, bool> descendantPredicate) =>
    Bib3.Extension.EnumeratePathToNodeFromTreeBFirst(pathRoot, getChildrenFromNode)
    .FirstOrDefault(path => descendantPredicate(path.Last()));
