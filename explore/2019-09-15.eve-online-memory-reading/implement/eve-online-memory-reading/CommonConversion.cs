
using System;

namespace eve_online_memory_reading
{
    static public class CommonConversion
    {
        static public string StringIdentifierFromValue(byte[] value)
        {
            using (var sha = new System.Security.Cryptography.SHA256Managed())
            {
                return BitConverter.ToString(sha.ComputeHash(value)).Replace("-", "");
            }
        }
    }
}
