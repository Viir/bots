using System.Linq;

namespace eve_online_memory_reading
{
    static public class EveOnline
    {
        /// <summary>
        /// returns the root of the UI tree.
        /// </summary>
        /// <param name="MemoryReader"></param>
        /// <returns></returns>
        static public UITreeNode UITreeRoot(
            IPythonMemoryReader MemoryReader)
        {
            var candidateAddresses = PyTypeObject.EnumeratePossibleAddressesOfInstancesOfPythonTypeFilteredByObType(MemoryReader, "UIRoot");

            //	return the candidate tree with the largest number of nodes.
            return
                candidateAddresses
                .Select(candidateAddress => new UITreeNode(candidateAddress, MemoryReader))
                .OrderByDescending(candidate => candidate.EnumerateChildrenTransitive(MemoryReader)?.Count())
                .FirstOrDefault();
        }
    }
}
