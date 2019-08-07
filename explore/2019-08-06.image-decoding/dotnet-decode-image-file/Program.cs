using System;
using System.Linq;
using System.Security.Cryptography;

namespace dotnet_decode_image_file
{
    class Program
    {
        static void Main(string[] args)
        {
            var fileContent = System.IO.File.ReadAllBytes(@".\..\..\2019-07-10.locate-objects-in-screenshot\2019-07-11.example-from-eve-online-crop-0.bmp");

            Console.WriteLine("Loaded file '" + ToStringBase16(SHA256FromByteArray(fileContent)) + "'.");

            var imagePixels = decodeImageFromFile(fileContent);

            var imageWidth = imagePixels[0].Length;
            var imageHeight = imagePixels.Length;

            Console.WriteLine("Loaded image with width of " + imagePixels[0].Length + " and height of " + imageHeight + ".");

            foreach (var (x, y) in new[] { (0, 0), (0, imageWidth - 1), (imageHeight - 1, 0), (imageHeight - 1, imageWidth - 1) })
            {
                Console.WriteLine("Pixel at " + x + ", " + y + " has value " + imagePixels[x][y]);
            }
        }

        static byte[] SHA256FromByteArray(byte[] array)
        {
            using (var hasher = new SHA256Managed())
                return hasher.ComputeHash(buffer: array);
        }

        static string ToStringBase16(byte[] array) => BitConverter.ToString(array).Replace("-", "");

        static PixelValue[][] decodeImageFromFile(byte[] imageFile)
        {
            //  https://github.com/SixLabors/ImageSharp
            //  https://docs.sixlabors.com/api/ImageSharp/SixLabors.ImageSharp.Image.html#SixLabors_ImageSharp_Image_Load_ReadOnlySpan_System_Byte__

            using (SixLabors.ImageSharp.Image<SixLabors.ImageSharp.PixelFormats.Rgba32> image = SixLabors.ImageSharp.Image.Load(imageFile))
            {
                var imageFrame = image.Frames.Single();

                return
                    Enumerable.Range(0, imageFrame.Height)
                    .Select(rowIndex =>
                        Enumerable.Range(0, imageFrame.Width)
                        .Select(columnIndex =>
                            {
                                var pixel = imageFrame[columnIndex, rowIndex];

                                return new PixelValue
                                {
                                    red = pixel.R,
                                    green = pixel.G,
                                    blue = pixel.B,
                                };
                            }).ToArray()
                        ).ToArray();
            }
        }
    }

    public class PixelValue
    {
        public int red, green, blue;

        override public string ToString() => Newtonsoft.Json.JsonConvert.SerializeObject(this);
    }
}
