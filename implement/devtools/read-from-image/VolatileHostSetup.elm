module VolatileHostSetup exposing
    ( ReadFileContentResultStructure(..)
    , RequestToVolatileHost(..)
    , ResponseFromVolatileHost(..)
    , buildRequestStringToGetResponseFromVolatileHost
    , deserializeResponseFromVolatileHost
    , setupScript
    )

import Json.Decode
import Json.Encode


type RequestToVolatileHost
    = ReadFileContent ReadFileContentRequest


type alias ReadFileContentRequest =
    { filePath : String }


type ResponseFromVolatileHost
    = ReadFileContentResult ReadFileContentResultStructure


type ReadFileContentResultStructure
    = DidNotFindFileAtSpecifiedPath
    | ExceptionAsString String
    | FileContentAsBase64 String


buildRequestStringToGetResponseFromVolatileHost : RequestToVolatileHost -> String
buildRequestStringToGetResponseFromVolatileHost =
    encodeRequestToVolatileHost
        >> Json.Encode.encode 0


encodeRequestToVolatileHost : RequestToVolatileHost -> Json.Encode.Value
encodeRequestToVolatileHost request =
    case request of
        ReadFileContent readFileContent ->
            Json.Encode.object
                [ ( "readFileContent"
                  , Json.Encode.object [ ( "filePath", readFileContent.filePath |> Json.Encode.string ) ]
                  )
                ]


deserializeResponseFromVolatileHost : String -> Result Json.Decode.Error ResponseFromVolatileHost
deserializeResponseFromVolatileHost =
    Json.Decode.decodeString decodeResponseFromVolatileHost


decodeResponseFromVolatileHost : Json.Decode.Decoder ResponseFromVolatileHost
decodeResponseFromVolatileHost =
    Json.Decode.oneOf
        [ Json.Decode.field "readFileContentResult" decodeReadFileContentResultStructure
            |> Json.Decode.map ReadFileContentResult
        ]


decodeReadFileContentResultStructure : Json.Decode.Decoder ReadFileContentResultStructure
decodeReadFileContentResultStructure =
    Json.Decode.oneOf
        [ Json.Decode.field "didNotFindFileAtSpecifiedPath" (Json.Decode.succeed DidNotFindFileAtSpecifiedPath)
        , Json.Decode.field "exceptionAsString" Json.Decode.string |> Json.Decode.map ExceptionAsString
        , Json.Decode.field "fileContentAsBase64" Json.Decode.string |> Json.Decode.map FileContentAsBase64
        ]


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


class Request
{
    public ReadFileContent readFileContent;

    public class ReadFileContent
    {
        public string filePath;
    }
}

class Response
{
    public ReadFileContentResult readFileContentResult;

    public class ReadFileContentResult
    {
        public object didNotFindFileAtSpecifiedPath;

        public string exceptionAsString;

        public string fileContentAsBase64;
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

    return null;
}

string SerializeToJsonForBot<T>(T value) =>
    Newtonsoft.Json.JsonConvert.SerializeObject(
        value,
        //  Use settings to get same derivation as at https://github.com/Arcitectus/Sanderling/blob/ada11c9f8df2367976a6bcc53efbe9917107bfa7/src/Sanderling/Sanderling.MemoryReading.Test/MemoryReadingDemo.cs#L91-L97
        new Newtonsoft.Json.JsonSerializerSettings
        {
            //  Bot code does not expect properties with null values, see https://github.com/Viir/bots/blob/880d745b0aa8408a4417575d54ecf1f513e7aef4/explore/2019-05-14.eve-online-bot-framework/src/Sanderling_Interface_20190514.elm
            NullValueHandling = Newtonsoft.Json.NullValueHandling.Ignore,

            //\thttps://stackoverflow.com/questions/7397207/json-net-error-self-referencing-loop-detected-for-type/18223985#18223985
            ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
        });

string InterfaceToHost_Request(string request)
{
    return serialRequest(request);
}

"""
