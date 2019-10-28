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
    }

    public class BotPropertiesFromCode
    {
        public string[] tags;

        public string descriptionText;
    }

    static public class BotCode
    {
        static public BotPropertiesFromCode ReadPropertiesFromBotCode(LiteralNodeObject botCode)
        {
            var mainBotFile =
                botCode
                .EnumerateBlobsTransitive()
                .FirstOrDefault(blob => blob.path.Select(pathNode => pathNode.ToLowerInvariant()).SequenceEqual(new[] { "src", "bot.elm" }));

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

                    return aggregatedTags.Split(new[] { ',' });
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

            return new BotPropertiesFromCode
            {
                tags = readTags(),
                descriptionText = readDescriptionText(),
            };
        }
    }
}
