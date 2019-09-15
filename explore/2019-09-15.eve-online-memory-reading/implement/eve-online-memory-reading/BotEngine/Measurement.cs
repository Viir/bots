using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace BotEngine
{
    public class ProcessMeasurement
    {
        public KeyValuePair<Int64, byte[]>[] MemoryBaseAddressAndListOctet;

        static string ProcessMemoryEntryName => @"Process\Memory";

        static public Int64? BaseAddressFromMemoryEntryName(string MemoryEntryName)
        {
            if (null == MemoryEntryName)
            {
                return null;
            }

            var match = Regex.Match(MemoryEntryName, @"0x([\d\w]+)");

            if (!match.Success)
            {
                return null;
            }

            if (Int64.TryParse(
                match.Groups[1].Value,
                System.Globalization.NumberStyles.HexNumber,
                System.Globalization.CultureInfo.InvariantCulture.NumberFormat,
                out var asInt))
                return asInt;

            return null;
        }

        static public ProcessMeasurement MeasurementFromZipArchive(byte[] ZipArchiveSerial)
        {
            using (var ZipArchive = new System.IO.Compression.ZipArchive(new MemoryStream(ZipArchiveSerial), System.IO.Compression.ZipArchiveMode.Read))
            {
                var memoryEntries =
                    ZipArchive.Entries
                    .Where(entry => entry.FullName.StartsWith(ProcessMemoryEntryName, StringComparison.InvariantCultureIgnoreCase))
                    .ToList();

                var memoryList =
                    memoryEntries
                    ?.Select(Entry =>
                    {
                        var content = new byte[Entry.Length];

                        using (var stream = Entry.Open())
                        {
                            if (stream.Read(content, 0, content.Length) != content.Length)
                                throw new NotImplementedException();
                        }

                        return new
                        {
                            baseAddress = BaseAddressFromMemoryEntryName(Entry.Name),
                            content = content,
                        };
                    })
                    ?.ToArray();

                return new ProcessMeasurement
                {
                    MemoryBaseAddressAndListOctet =
                        memoryList
                        ?.Where(AddressAndListOctet => AddressAndListOctet.baseAddress.HasValue && null != AddressAndListOctet.content)
                        ?.Select(AddressAndListOctet => new KeyValuePair<Int64, byte[]>(AddressAndListOctet.baseAddress.Value, AddressAndListOctet.content))
                        ?.ToArray(),
                };
            }
        }
    }
}