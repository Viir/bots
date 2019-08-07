module VolatileHostSetup exposing (
    GetImageResultStructure(..)
    , GetImageSuccessStructure
    , GetPixelsFromImageResultStructure(..)
    , GetPixels2DSuccessStructure
    , RequestToVolatileHost(..)
    , ResponseFromVolatileHost(..)
    , PixelValue
    , buildScriptToGetResponseFromVolatileHost
    , deserializeResponseFromVolatileHost
    , setupScript)

import Base64.Decode
import Bytes
import Bytes.Decode
import Json.Decode
import Json.Encode



type RequestToVolatileHost
    = ReadFileContent ReadFileContentRequest
    | GetImage ReadFileContentRequest
    | GetPixelsFromImageRectangle GetPixelsFromImageRectangleStructure


type alias ReadFileContentRequest =
    { filePath : String }


type ResponseFromVolatileHost
    = GetImageResult GetImageResultStructure
    | GetPixelsFromImageRectangleResult GetPixelsFromImageResultStructure


type GetImageResultStructure
    = DidNotFindFileAtSpecifiedPath
    | ExceptionAsString String
    | GetImageSuccess GetImageSuccessStructure


type alias GetImageSuccessStructure =
    { fileIdBase16 : String
    , widthInPixels : Int
    , heightInPixels : Int
    }


type alias GetPixelsFromImageRectangleStructure =
    { fileIdBase16 : String
    , left : Int
    , top : Int
    , width : Int
    , height : Int
    , binningX : Int
    , binningY : Int
    }


type GetPixelsFromImageResultStructure
    = DidNotFindSpecifiedImage
    | GetPixels2DSuccess GetPixels2DSuccessStructure


type alias GetPixels2DSuccessStructure =
    { pixels : List (List PixelValue)
    }


type alias GetPixels2DSuccessIntermediateStructure =
    { pixelsRowsEncoded_R8G8B8_Base64 : List String
    }


type alias PixelValue =
    { red : Int, green : Int, blue : Int }


buildScriptToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildScriptToGetResponseFromVolatileHost request =
    "serialRequest("
        ++ (request
                |> encodeRequestToVolatileHost
                |> Json.Encode.encode 0
                |> Json.Encode.string
                |> Json.Encode.encode 0
           )
        ++ ")"


encodeRequestToVolatileHost : RequestToVolatileHost -> Json.Encode.Value
encodeRequestToVolatileHost request =
    case request of
        ReadFileContent readFileContent ->
            Json.Encode.object
                [ ( "readFileContent"
                  , Json.Encode.object [ ( "filePath", readFileContent.filePath |> Json.Encode.string ) ]
                  )
                ]
        GetImage getImage ->
            Json.Encode.object
                [ ( "getImage"
                  , Json.Encode.object [ ( "filePath", getImage.filePath |> Json.Encode.string ) ]
                  )
                ]
        GetPixelsFromImageRectangle getPixelsFromImageRectangle ->
            Json.Encode.object
                [ ( "getPixelsFromImageRectangle"
                  , getPixelsFromImageRectangle |> encodeGetPixelsFromImageRectangle
                  )
                ]


encodeGetPixelsFromImageRectangle : GetPixelsFromImageRectangleStructure -> Json.Encode.Value
encodeGetPixelsFromImageRectangle request =
    [ ( "fileIdBase16", request.fileIdBase16 |> Json.Encode.string )
    , ( "left", request.left |> Json.Encode.int )
    , ( "top", request.top |> Json.Encode.int )
    , ( "width", request.width |> Json.Encode.int )
    , ( "height", request.height |> Json.Encode.int )
    , ( "binningX", request.binningX |> Json.Encode.int )
    , ( "binningY", request.binningY |> Json.Encode.int )
    ]
        |> Json.Encode.object


deserializeResponseFromVolatileHost : String -> Result Json.Decode.Error ResponseFromVolatileHost
deserializeResponseFromVolatileHost =
    Json.Decode.decodeString decodeResponseFromVolatileHost


decodeResponseFromVolatileHost : Json.Decode.Decoder ResponseFromVolatileHost
decodeResponseFromVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "getImageResult" decodeGetImageResultStructure
            |> Json.Decode.map GetImageResult
        , Json.Decode.field "getPixelsFromImageRectangleResult" decodeGetPixelsFromImageRectangleResult
            |> Json.Decode.map GetPixelsFromImageRectangleResult
        ]


decodeGetImageResultStructure : Json.Decode.Decoder GetImageResultStructure
decodeGetImageResultStructure =
    Json.Decode.oneOf
        [ Json.Decode.field "didNotFindFileAtSpecifiedPath" (jsonDecodeSucceedIfNotNull DidNotFindFileAtSpecifiedPath)
        , Json.Decode.field "exceptionAsString" Json.Decode.string |> Json.Decode.map ExceptionAsString
        , Json.Decode.field "getImageSuccess" decodeGetImageSuccessStructure |> Json.Decode.map GetImageSuccess
        ]


decodeGetImageSuccessStructure : Json.Decode.Decoder GetImageSuccessStructure
decodeGetImageSuccessStructure =
    Json.Decode.map3 GetImageSuccessStructure
        (Json.Decode.field "fileIdBase16" Json.Decode.string)
        (Json.Decode.field "widthInPixels" Json.Decode.int)
        (Json.Decode.field "heightInPixels" Json.Decode.int)


decodeGetPixelsFromImageRectangleResult : Json.Decode.Decoder GetPixelsFromImageResultStructure
decodeGetPixelsFromImageRectangleResult =
    Json.Decode.oneOf
        [ Json.Decode.field "didNotFindSpecifiedImage" (jsonDecodeSucceedIfNotNull DidNotFindSpecifiedImage)
        , Json.Decode.field "getPixels2DSuccess" decodeGetPixels2DSuccessStructure |> Json.Decode.map GetPixels2DSuccess
        ]


decodeGetPixels2DSuccessStructure : Json.Decode.Decoder GetPixels2DSuccessStructure
decodeGetPixels2DSuccessStructure =
    decodeGetPixels2DSuccessIntermediateStructure
        |> Json.Decode.map (.pixelsRowsEncoded_R8G8B8_Base64 >> List.map (Base64.Decode.decode Base64.Decode.bytes))
        |> Json.Decode.map (resultCombine >> Result.mapError base64ErrorToString)
        |> Json.Decode.andThen jsonDecodeUnwrapResult
        |> Json.Decode.map (\rows -> { pixels = rows |> List.map pixelsFromByteArrayRGB })


pixelsFromByteArrayRGB : Bytes.Bytes -> List PixelValue
pixelsFromByteArrayRGB bytes =
    bytes
        |> Bytes.Decode.decode
            (Bytes.Decode.loop ( (bytes |> Bytes.width) // 3, [] )
                (decodeListStep decodeSinglePixelRGBFromBytes)
            )
        |> Maybe.withDefault []
        |> List.reverse


decodeListStep : Bytes.Decode.Decoder a -> ( Int, List a ) -> Bytes.Decode.Decoder (Bytes.Decode.Step ( Int, List a ) (List a))
decodeListStep elementDecoder ( n, xs ) =
    if n <= 0 then
        Bytes.Decode.succeed (Bytes.Decode.Done xs)

    else
        Bytes.Decode.map (\x -> Bytes.Decode.Loop ( n - 1, x :: xs )) elementDecoder


resultCombine : List (Result x a) -> Result x (List a)
resultCombine =
    List.foldr (Result.map2 (::)) (Ok [])


jsonDecodeUnwrapResult : Result String ok -> Json.Decode.Decoder ok
jsonDecodeUnwrapResult result =
    case result of
        Err error ->
            Json.Decode.fail error

        Ok success ->
            Json.Decode.succeed success


base64ErrorToString : Base64.Decode.Error -> String
base64ErrorToString error =
    case error of
        Base64.Decode.ValidationError ->
            "ValidationError"

        Base64.Decode.InvalidByteSequence ->
            "InvalidByteSequence"


decodeSinglePixelRGBFromBytes : Bytes.Decode.Decoder PixelValue
decodeSinglePixelRGBFromBytes =
    Bytes.Decode.map3
        (\red green blue -> { red = red, green = green, blue = blue})
        Bytes.Decode.unsignedInt8
        Bytes.Decode.unsignedInt8
        Bytes.Decode.unsignedInt8


decodeGetPixels2DSuccessIntermediateStructure : Json.Decode.Decoder GetPixels2DSuccessIntermediateStructure
decodeGetPixels2DSuccessIntermediateStructure =
    Json.Decode.map GetPixels2DSuccessIntermediateStructure
        (Json.Decode.field "pixelsRowsEncoded_R8G8B8_Base64" (Json.Decode.list Json.Decode.string))


jsonDecodeSucceedIfNotNull : a -> Json.Decode.Decoder a
jsonDecodeSucceedIfNotNull valueIfNotNull =
    Json.Decode.value
        |> Json.Decode.andThen
            (\asValue ->
                if asValue == Json.Encode.null then
                    Json.Decode.fail "Is null."

                else
                    Json.Decode.succeed valueIfNotNull
            )


-- TODO: Adapt the casing of custom type tags for consistency with default JSON decoder.


setupScript : String
setupScript =
    """
#r "mscorlib"
#r "netstandard"
#r "System"
#r "System.Collections.Immutable"
#r "System.ComponentModel.Primitives"
#r "System.IO.Compression"
#r "System.Net"
#r "System.Net.WebClient"
#r "System.Private.Uri"
#r "System.Linq"
#r "System.Security.Cryptography.Algorithms"
#r "System.Security.Cryptography.Primitives"

// "Newtonsoft.Json"
#r "sha256:B9B4E633EA6C728BAD5F7CBBEF7F8B842F7E10181731DBE5EC3CD995A6F60287"

//  SixLabors.Core
#r "sha256:CAC3C847E46F431E6B3F7278BF581D782A88CAAB68FD39111BCD0E3E7B7EF2B9"
//  SixLabors.ImageSharp
#r "sha256:B536AE9B67B4CB85773E3B4C5BE235B6777F3E93E9B6549603659A63366DC506"


using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Security.Cryptography;


byte[] SHA256FromByteArray(byte[] array)
{
    using (var hasher = new SHA256Managed())
        return hasher.ComputeHash(buffer: array);
}

string ToStringBase16(byte[] array) => BitConverter.ToString(array).Replace("-", "");


Dictionary<string, PixelValue[][]> imageFromFileId = new Dictionary<string, PixelValue[][]>();

public class PixelValue
{
    public int red, green, blue;
}

PixelValue[][] decodeImageFromFile(byte[] imageFile)
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


class Request
{
    public ReadFileContent readFileContent;

    public GetImage getImage;

    public GetPixelsFromImageRectangleStructure getPixelsFromImageRectangle;

    public class ReadFileContent
    {
        public string filePath;
    }

    public class GetImage
    {
        public string filePath;
    }

    public class GetPixelsFromImageRectangleStructure
    {
        public string fileIdBase16;

        public int left;

        public int top;

        public int width;

        public int height;

        public int binningX;

        public int binningY;
    }
}

class Response
{
    public ReadFileContentResult readFileContentResult;

    public GetImageResultStructure getImageResult;

    public GetPixelsFromImageResultStructure getPixelsFromImageRectangleResult;

    public class ReadFileContentResult
    {
        public object didNotFindFileAtSpecifiedPath;

        public string exceptionAsString;

        public string fileContentAsBase64;
    }

    public class GetImageResultStructure
    {
        public object didNotFindFileAtSpecifiedPath;

        public string exceptionAsString;

        public Success getImageSuccess;

        public class Success
        {
            public string fileIdBase16;

            public int widthInPixels;

            public int heightInPixels;
        }
    }

    public class GetPixelsFromImageResultStructure
    {
        public object didNotFindSpecifiedImage;

        public GetPixels2DSuccessStructure getPixels2DSuccess;
    }

    public class GetPixels2DSuccessStructure
    {
        public string[] pixelsRowsEncoded_R8G8B8_Base64;
    }
}

string serialRequest(string serializedRequest)
{
    var requestStructure = Newtonsoft.Json.JsonConvert.DeserializeObject<Request>(serializedRequest);

    var response = request(requestStructure);

    return SerializeToJsonForBot(response);
}

Response request(Request request)
{
    if (request?.readFileContent?.filePath != null)
    {
        try
        {

            if (!System.IO.File.Exists(request.readFileContent.filePath))
            {
                return new Response
                {
                    readFileContentResult = new Response.ReadFileContentResult
                    {
                        didNotFindFileAtSpecifiedPath = new object(),
                    }
                };
            }

            var fileContent = System.IO.File.ReadAllBytes(request.readFileContent.filePath);

            return new Response
            {
                readFileContentResult = new Response.ReadFileContentResult
                {
                    fileContentAsBase64 = Convert.ToBase64String(fileContent)
                }
            };
        }
        catch (Exception e)
        {
            return new Response
            {
                readFileContentResult = new Response.ReadFileContentResult
                {
                    exceptionAsString = e.ToString(),
                }
            };
        }
    }

    if (request?.getImage != null)
    {
        return new Response
        {
            getImageResult = getImage(request?.getImage),
        };
    }

    if (request?.getPixelsFromImageRectangle != null)
    {
        return new Response
        {
            getPixelsFromImageRectangleResult = getPixelsFromImageRectangle(request?.getPixelsFromImageRectangle),
        };
    }

    return null;
}

Response.GetImageResultStructure getImage(Request.GetImage request)
{
    try
    {
        var filePath = request.filePath;

        if (!System.IO.File.Exists(filePath))
        {
            return new Response.GetImageResultStructure
            {
                didNotFindFileAtSpecifiedPath = new object(),
            };
        }

        var fileContent = System.IO.File.ReadAllBytes(filePath);

        var fileIdBase16 = ToStringBase16(SHA256FromByteArray(fileContent));

        var imagePixels = decodeImageFromFile(fileContent);

        imageFromFileId.Clear();
        imageFromFileId[fileIdBase16] = imagePixels;

        return new Response.GetImageResultStructure
        {
            getImageSuccess = new Response.GetImageResultStructure.Success
            {
                fileIdBase16 = fileIdBase16,
                widthInPixels = imagePixels[0].Length,
                heightInPixels = imagePixels.Length,
            }
        };
    }
    catch (Exception e)
    {
        return new Response.GetImageResultStructure
        {
            exceptionAsString = e.ToString(),
        };
    }
}

Response.GetPixelsFromImageResultStructure getPixelsFromImageRectangle(
    Request.GetPixelsFromImageRectangleStructure request)
{
    if (!imageFromFileId.TryGetValue(request.fileIdBase16, out var imagePixels))
    {
        return new Response.GetPixelsFromImageResultStructure
        {
            didNotFindSpecifiedImage = new object()
        };
    }

    var columnCountAfterBinning = request.width / Math.Max(1, request.binningX);
    var rowCountAfterBinning = request.height / Math.Max(1, request.binningY);

    var cropColumnCount = columnCountAfterBinning * request.binningX;
    var cropRowCount = rowCountAfterBinning * request.binningY;

    var cropPixels =
        Enumerable.Range(0, cropRowCount)
        .Select(rowIndexInCrop =>
            {
                var originalRow = imagePixels.ElementAtOrDefault(rowIndexInCrop + request.top);

                return
                    Enumerable.Range(0, cropColumnCount)
                    .Select(columnIndexInCrop => originalRow?.ElementAtOrDefault(columnIndexInCrop + request.left) ?? new PixelValue())
                    .ToArray();
            })
        .ToArray();

    var binOffsets =
        Enumerable.Range(0, request.binningY)
        .SelectMany(rowIndexInBin =>
            Enumerable.Range(0, request.binningX)
            .Select(columnIndexInBin => (x: columnIndexInBin, y: rowIndexInBin)))
        .ToArray();

    var binnedPixels =
        Enumerable.Range(0, rowCountAfterBinning)
        .Select(rowIndex =>
            Enumerable.Range(0, columnCountAfterBinning)
            .Select(columnIndex =>
            {
                var pixelsInBin =
                    binOffsets.Select(offset =>
                        cropPixels[rowIndex * request.binningY + offset.x][columnIndex * request.binningX + offset.y])
                        .ToArray();

                PixelValue sum = new PixelValue { red = 0, green = 0, blue = 0 };

                foreach (var sourcePixel in pixelsInBin)
                {
                    sum.red += sourcePixel.red;
                    sum.green += sourcePixel.green;
                    sum.blue += sourcePixel.blue;
                }

                return new PixelValue
                {
                    red = sum.red / pixelsInBin.Length,
                    green = sum.green / pixelsInBin.Length,
                    blue = sum.blue / pixelsInBin.Length,
                };
            })
            .ToArray()).ToArray();

    var binnedPixelsRowsEncoded_R8G8B8_Base64 =
        binnedPixels.Select(pixelRow =>
        {
            var pixelRowR8G8B8 =
                pixelRow
                .SelectMany(pixelValue => new[] { (byte)pixelValue.red, (byte)pixelValue.green, (byte)pixelValue.blue })
                .ToArray();

            return Convert.ToBase64String(pixelRowR8G8B8);
        })
        .ToArray();

    return new Response.GetPixelsFromImageResultStructure
    {
        getPixels2DSuccess = new Response.GetPixels2DSuccessStructure
        {
            pixelsRowsEncoded_R8G8B8_Base64 = binnedPixelsRowsEncoded_R8G8B8_Base64,
        }
    };
}

string SerializeToJsonForBot<T>(T value) =>
    Newtonsoft.Json.JsonConvert.SerializeObject(
        value,
        //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
        new Newtonsoft.Json.JsonSerializerSettings
        {
            //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
            NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

            //	https://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
            ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
        });

"Setup Completed"
"""
