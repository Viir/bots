using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;

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

        static public IImmutableList<(string name, LiteralNodeObject obj)> FilterBlobsInTreeContent(
            IImmutableList<(string name, LiteralNodeObject obj)> treeContent,
            System.Func<string[], byte[], bool> keepBlob)
        {
            return
                treeContent.Select(treeNode =>
                {
                    LiteralNodeObject getFilteredObj()
                    {
                        var treeNodePrefix = new string[] { treeNode.name };

                        if (treeNode.obj.BlobContent != null)
                        {
                            if (keepBlob(treeNodePrefix, treeNode.obj.BlobContent))
                                return treeNode.obj;

                            return null;
                        }

                        var childFilteredTreeContent =
                            FilterBlobsInTreeContent(
                                treeNode.obj.TreeContent,
                                (childNodeNames, blobContent) => keepBlob(treeNodePrefix.Concat(childNodeNames).ToArray(), blobContent));

                        if (0 < childFilteredTreeContent.Count)
                            return new LiteralNodeObject { TreeContent = childFilteredTreeContent };

                        return null;
                    }

                    return (treeNode.name, obj: getFilteredObj());
                })
                .Where(filteredNode => filteredNode.obj != null)
                .ToImmutableList();
        }
    }

    public class BotPropertiesFromCode
    {
        public string[] tags;

        public string[] authorsForumUsernames;

        public string descriptionText;

        public string frameworkId;
    }

    static public class BotCode
    {
        static public bool BlobPathIsBotModule(IEnumerable<string> path) =>
            path.Select(pathNode => pathNode.ToLowerInvariant()).SequenceEqual(new[] { "src", "bot.elm" });

        static public BotPropertiesFromCode ReadPropertiesFromBotCode(LiteralNodeObject botCode)
        {
            var mainBotFile =
                botCode
                .EnumerateBlobsTransitive()
                .FirstOrDefault(blob => BlobPathIsBotModule(blob.path));

            if (mainBotFile.blobContent == null)
                return null;

            string[] readTags()
            {
                try
                {
                    var mainBotFileSourceLines =
                        System.Text.Encoding.UTF8.GetString(mainBotFile.blobContent)
                        .Split(new char[] { (char)10, (char)13 });

                    var catalogTagsLineMatch =
                        mainBotFileSourceLines
                        .Select(line => System.Text.RegularExpressions.Regex.Match(
                            line,
                            "\\s*bot-catalog-tags:([\\w\\d\\-,]+)",
                            System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                        .FirstOrDefault(match => match.Success);

                    if (catalogTagsLineMatch == null)
                        return null;

                    var aggregatedTags = catalogTagsLineMatch.Groups[1].Value;

                    return aggregatedTags.Split(new[] { ',' }).Select(tag => tag.Trim()).ToArray();
                }
                catch
                {
                    return null;
                }
            }

            string[] readAuthorsForumUsernames()
            {
                try
                {
                    var mainBotFileSourceLines =
                        System.Text.Encoding.UTF8.GetString(mainBotFile.blobContent)
                        .Split(new char[] { (char)10, (char)13 });

                    var authorsForumUsernamesLineMatch =
                        mainBotFileSourceLines
                        .Select(line => System.Text.RegularExpressions.Regex.Match(
                            line,
                            "\\s*authors-forum-usernames:([\\w\\d\\-,]+)",
                            System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                        .FirstOrDefault(match => match.Success);

                    if (authorsForumUsernamesLineMatch == null)
                        return null;

                    var aggregatedAuthorsForumUsernames = authorsForumUsernamesLineMatch.Groups[1].Value;

                    return aggregatedAuthorsForumUsernames.Split(new[] { ',' }).Select(name => name.Trim()).ToArray();
                }
                catch
                {
                    return null;
                }
            }

            string readDescriptionText()
            {
                try
                {
                    var descriptionTextMatch =
                        System.Text.RegularExpressions.Regex.Match(
                            System.Text.Encoding.UTF8.GetString(mainBotFile.blobContent),
                            "\\{\\-.*?\\-\\}",
                            System.Text.RegularExpressions.RegexOptions.Singleline);

                    if (!descriptionTextMatch.Success)
                        return null;

                    return descriptionTextMatch.Value;
                }
                catch
                {
                    return null;
                }
            }

            string readFrameworkId()
            {
                try
                {
                    var frameworkCodeNode =
                        new LiteralNodeObject
                        {
                            TreeContent = LiteralNodeObject.FilterBlobsInTreeContent(botCode.TreeContent,
                                (blobPath, blobContent) => !BlobPathIsBotModule(blobPath)),
                        };

                    var frameworkCodeFilesFromSource =
                        frameworkCodeNode
                        ?.EnumerateBlobsTransitive()
                        .Select(blobPathAndContent => (path: string.Join("/", blobPathAndContent.path), blobPathAndContent.blobContent))
                        .ToImmutableList();

                    var frameworkCodeZip = Kalmit.ZipArchive.ZipArchiveFromEntries(
                        frameworkCodeFilesFromSource,
                        System.IO.Compression.CompressionLevel.NoCompression);

                    return
                        Kalmit.CommonConversion.StringBase16FromByteArray(
                            Kalmit.CommonConversion.HashSHA256(frameworkCodeZip));
                }
                catch
                {
                    return null;
                }
            }

            return new BotPropertiesFromCode
            {
                tags = readTags(),
                authorsForumUsernames = readAuthorsForumUsernames(),
                descriptionText = readDescriptionText(),
                frameworkId = readFrameworkId(),
            };
        }
    }
}
