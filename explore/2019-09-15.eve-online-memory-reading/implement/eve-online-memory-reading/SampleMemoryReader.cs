using System;

namespace eve_online_memory_reading
{
    public class SampleMemoryReader : IMemoryReader
    {
        readonly BotEngine.ProcessMeasurement sample;

        public MemoryReaderModuleInfo[] Modules()
        {
            throw new NotImplementedException();
        }

        public SampleMemoryReader(BotEngine.ProcessMeasurement sample)
        {
            this.sample = sample;
        }

        public byte[] ReadBytes(Int64 address, int bytesCount)
        {
            foreach (var memoryBaseAddressAndListOctet in sample.MemoryBaseAddressAndListOctet)
            {
                var offsetInSampleRange =
                    address - memoryBaseAddressAndListOctet.Key;

                if (offsetInSampleRange < 0 || memoryBaseAddressAndListOctet.Value.Length <= offsetInSampleRange)
                    continue;

                var bytes = new byte[Math.Min(bytesCount, memoryBaseAddressAndListOctet.Value.Length - offsetInSampleRange)];

                Array.Copy(memoryBaseAddressAndListOctet.Value, offsetInSampleRange, bytes, 0, bytes.Length);

                return bytes;
            }

            return null;
        }
    }
}
