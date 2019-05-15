using System;
using System.Collections.Generic;

namespace BotEngine.Windows.Console.BotFramework
{
    static public class SanderlingSetup
    {
        //  EVE Online functionality based on https://github.com/Viir/bots/blob/59607e9c0e90f52cd35df2205401363c72787c1b/eve-online/setup-sanderling.csx

        static public Interface.IMemoryReader MemoryReaderFromLiveProcessId(int processId) =>
            new Interface.ProcessMemoryReader(processId);

        static public Optimat.EveOnline.MemoryAuswertWurzelSuuce UITreeRootFromMemoryReader(
            Interface.IMemoryReader memoryReader)
        {
            return global::Sanderling.ExploreProcessMeasurement.Extension.SearchForUITreeRoot(memoryReader);
        }

        static public Optimat.EveOnline.AuswertGbs.UINodeInfoInTree PartialPythonModelFromUITreeRoot(
            Interface.IMemoryReader memoryReader,
            Optimat.EveOnline.MemoryAuswertWurzelSuuce uiTreeRoot) =>
            Optimat.EveOnline.AuswertGbs.Extension.SictAuswert(
                global::Sanderling.ExploreProcessMeasurement.Extension.ReadUITreeFromRoot(memoryReader, uiTreeRoot));

        static public global::Sanderling.Interface.MemoryStruct.IMemoryMeasurement SanderlingMemoryMeasurementFromPartialPythonModel(
            Optimat.EveOnline.GbsAstInfo partialPython) =>
            Optimat.EveOnline.AuswertGbs.Extension.SensorikScnapscusKonstrukt(partialPython, null);

        static public IEnumerable<T> EnumerateNodeFromTreeDFirst<T>(
            T root,
            Func<T, IEnumerable<T>> callbackEnumerateChildInNode,
            int? depthMax = null,
            int? depthMin = null) =>
            Bib3.Extension.EnumerateNodeFromTreeDFirst(root, callbackEnumerateChildInNode, depthMax, depthMin);
    }
}
