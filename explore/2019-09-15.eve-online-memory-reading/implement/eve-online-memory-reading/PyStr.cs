using System;

namespace eve_online_memory_reading
{
    public class PyStr : PyObject
    {
        readonly public string String;

        public PyStr(
            Int64 BaseAddress,
            IMemoryReader MemoryReader)
            :
            base(BaseAddress, MemoryReader)
        {
            String = MemoryReader.ReadStringAsciiNullTerminated(BaseAddress + 20);
        }
    }
}
