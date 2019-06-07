using System.Collections.Generic;
using System.Collections.Immutable;

namespace BotEngine.Windows.Console.BotSourceModel
{
    /// <summary>
    /// A node represents either a tree or a blob.
    /// </summary>
    public class LiteralNodeObject
    {
        public byte[] BlobContent;

        public IImmutableList<(string name, LiteralNodeObject obj)> TreeContent;

        public IImmutableList<(IImmutableList<string> path, byte[] blobContent)> EnumerateBlobsTransitive() =>
            TreeContent == null ? null :
            EnumerateBlobsRecursive(TreeContent)
            .ToImmutableList();

        static IEnumerable<(IImmutableList<string> name, byte[] content)> EnumerateBlobsRecursive(IImmutableList<(string name, LiteralNodeObject obj)> tree)
        {
            foreach (var treeEntry in tree)
            {
                if (treeEntry.obj.BlobContent != null)
                    yield return (ImmutableList.Create(treeEntry.name), treeEntry.obj.BlobContent);

                if (treeEntry.obj.TreeContent != null)
                {
                    foreach (var subTreeEntry in EnumerateBlobsRecursive(treeEntry.obj.TreeContent))
                    {
                        yield return (subTreeEntry.name.Insert(0, treeEntry.name), subTreeEntry.content);
                    }
                }
            }
        }
    }
}
