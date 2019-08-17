using BotEngine.Windows.Console.BotSourceModel;
using System.Collections.Immutable;
using System.IO;
using System.Linq;

namespace BotEngine.Windows.Console
{
    static public class LoadFromLocalFilesystem
    {
        static public LiteralNodeObject LoadLiteralNodeFromPath(string path)
        {
            if (File.Exists(path))
                return new LiteralNodeObject { BlobContent = File.ReadAllBytes(path) };

            if (!Directory.Exists(path))
                return null;

            var treeEntries =
                Directory.EnumerateFileSystemEntries(path)
                .Select(fileSystemEntry =>
                {
                    var name = Path.GetRelativePath(path, fileSystemEntry);

                    return (name, LoadLiteralNodeFromPath(fileSystemEntry));
                })
                .ToImmutableList();

            return new LiteralNodeObject
            {
                TreeContent = treeEntries,
            };
        }
    }
}
