using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Linq;
using System.Collections.Immutable;

namespace BotEngine.Windows.Console.Test
{
    [TestClass]
    public class LoadFromGithubTest
    {
        [TestMethod]
        public void Test_LoadFromGithub_Tree()
        {
            var expectedFilesNamesAndHashes = new[]
            {
                //  https://botengine.blob.core.windows.net/blob-library/by-name/get-sha256-hash-from-file.html#

                (".gitignore", "ab074031b6fb4d6cd8d0b90393a95186c0686c3736152159ef91072619eb22d4"),
                ("elm.json", "e36ac0553ddffc03ad240f629b4d2c5fce81569c51fe2edf82041028f78be88b"),

                ("src/Bot_Interface_To_Host_20190529.elm", "2483c72af2057422407ae8dc73648fb6851f184a4486c8e2027b5b32b7720ecc"),
                ("src/Main.elm", "a0676ccc4a05f0bbb03b9756b947cee003ed1a5c166ddc2d3c55d6c1b50be023"),
                ("src/Sanderling.elm", "0dff2cc2ff14791d8b463af0b411b33198a9d5bf8a0c9c94675bcb79bd770dc4"),
                ("src/SanderlingMemoryMeasurement.elm", "a91c639bdc292a94bce49cc260ccfc4b16a449742eeb48df0efb048a1e46734c"),
                ("src/SanderlingVolatileHostSetup.elm", "56e8cdfcc233a642909dde93c5d5d53d35012ea71de452f9cb57bbd001fdd2c4"),
                ("src/SimpleSanderling.elm", "f91fc011548f6883d3897ac55c4758163deabf7dbb3e6926060c6377bf8a6574"),
            };

            var loadFromGithubResult =
                LoadFromGithub.LoadFromUrl(
                    "https://github.com/Viir/bots/tree/32559530694cc0523f77b7ea27c530ecaecd7d2f/implement/bot/eve-online/eve-online-warp-to-0-autopilot");

            Assert.IsNull(loadFromGithubResult.Error, "No error: " + loadFromGithubResult.Error);

            var loadedFilesNamesAndContents =
                loadFromGithubResult.Success.EnumerateBlobsTransitive()
                .Select(blobPathAndContent => (
                    fileName: string.Join("/", blobPathAndContent.path),
                    fileContent: blobPathAndContent.blobContent))
                .ToImmutableList();

            var loadedFilesNamesAndHashes =
                loadedFilesNamesAndContents
                .Select(fileNameAndContent =>
                    (fileNameAndContent.fileName,
                        Kalmit.CommonConversion.StringBase16FromByteArray(
                            Kalmit.CommonConversion.HashSHA256(fileNameAndContent.fileContent)).ToLowerInvariant()))
                .ToImmutableList();

            CollectionAssert.AreEquivalent(
                expectedFilesNamesAndHashes,
                loadedFilesNamesAndHashes,
                "Loaded files equal expected files.");
        }

        [TestMethod]
        public void Test_LoadFromGithub_Tree_at_root()
        {
            var expectedFilesNamesAndHashes = new[]
            {
                //  https://botengine.blob.core.windows.net/blob-library/by-name/get-sha256-hash-from-file.html#

                (fileName: "README.md", fileHash: "6f360ccaccd4aeb7d19c7003e77d7b6d33d5245f6e385d95b51d582047584e37"),
            };

            var loadFromGithubResult =
                LoadFromGithub.LoadFromUrl(
                    "https://github.com/Viir/bots/tree/32559530694cc0523f77b7ea27c530ecaecd7d2f/");

            Assert.IsNull(loadFromGithubResult.Error, "No error: " + loadFromGithubResult.Error);

            var loadedFilesNamesAndContents =
                loadFromGithubResult.Success.EnumerateBlobsTransitive()
                .Select(blobPathAndContent => (
                    fileName: string.Join("/", blobPathAndContent.path),
                    fileContent: blobPathAndContent.blobContent))
                .ToImmutableList();

            var loadedFilesNamesAndHashes =
                loadedFilesNamesAndContents
                .Select(fileNameAndContent =>
                    (fileName: fileNameAndContent.fileName,
                        fileHash: Kalmit.CommonConversion.StringBase16FromByteArray(
                            Kalmit.CommonConversion.HashSHA256(fileNameAndContent.fileContent)).ToLowerInvariant()))
                .ToImmutableList();

            foreach (var expectedFileNameAndHash in expectedFilesNamesAndHashes)
            {
                Assert.IsTrue(
                    loadedFilesNamesAndHashes.Contains(expectedFileNameAndHash),
                    "Collection of loaded files contains a file named '" + expectedFileNameAndHash.fileName +
                    "' with hash " + expectedFileNameAndHash.fileHash + ".");
            }
        }

        [TestMethod]
        public void Test_LoadFromGithub_Object()
        {
            var expectedFileHash = "e36ac0553ddffc03ad240f629b4d2c5fce81569c51fe2edf82041028f78be88b";

            var loadFromGithubResult =
                LoadFromGithub.LoadFromUrl(
                    "https://github.com/Viir/bots/blob/32559530694cc0523f77b7ea27c530ecaecd7d2f/implement/bot/eve-online/eve-online-warp-to-0-autopilot/elm.json");

            Assert.IsNull(loadFromGithubResult.Error, "No error: " + loadFromGithubResult.Error);

            var blobContent = loadFromGithubResult.Success.BlobContent;

            Assert.IsNotNull(blobContent, "Found blobContent.");

            Assert.AreEqual(expectedFileHash,
                Kalmit.CommonConversion.StringBase16FromByteArray(
                    Kalmit.CommonConversion.HashSHA256(blobContent))
                .ToLowerInvariant(),
                "Loaded blob content hash equals expected hash.");
        }
    }
}
