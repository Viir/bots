module ParseGuiFromScreenshotTest exposing (..)

import Base64
import DecodeBMPImage
import EveOnline.BotFramework exposing (Location2d, PixelValueRGB)
import EveOnline.ParseGuiFromScreenshot
import Expect
import Result.Extra
import Test


readButtonLabelTests : Test.Test
readButtonLabelTests =
    readButtonLabelTestScenarios
        |> List.indexedMap
            (\testIndex testCase ->
                Test.describe ("Scenario " ++ String.fromInt testIndex)
                    (testCase.imageFileBase64
                        |> decodeBmpImageFromFileBase64
                        |> Result.Extra.unpack
                            ((++) "Failed to decode the image: "
                                >> Expect.fail
                                >> always
                                >> Test.test "decode image"
                                >> List.singleton
                            )
                            (\image ->
                                let
                                    searchRegion =
                                        { x = image.bitmapWidthInPixels // 4 - 1
                                        , y = image.bitmapHeightInPixels // 4 - 1
                                        , width = 3
                                        , height = 3
                                        }
                                in
                                image
                                    |> buildScreenshotCommonVariationsFromBmpImage
                                    |> List.indexedMap
                                        (\variationIndex screenshot ->
                                            Test.test ("Screenshot variation " ++ String.fromInt variationIndex) <|
                                                \_ ->
                                                    { pixels_2x2 = screenshot.pixels_2x2 }
                                                        |> EveOnline.ParseGuiFromScreenshot.readButtonLabel searchRegion
                                                        |> Expect.equal [ testCase.expectedLabel ]
                                        )
                            )
                    )
            )
        |> Test.describe "read button label"


readButtonLabelTestScenarios : List { imageFileBase64 : String, expectedLabel : String }
readButtonLabelTestScenarios =
    [ { imageFileBase64 = "Qk1GAwAAAAAAADYAAAAoAAAAEgAAAA4AAAABABgAAAAAAAAAAADDDgAAww4AAAAAAAAAAAAAUkgtUkgtUUctUUgtT0UrTkQrTkQrTkMrTkQrT0UsUEUrTUQqT0YrUEUrT0QqUEYrUUctUUctAABSSC1SSC1QRStORCpLQSlLQSlKQChKQSlKQSlLQSlNQilJQCdMQilMQilMQypMQylRRy1RRy0AAFJILVJHLU9FK56ZjtDOzNTT0szLyIyFeUlAKH94adfX1Ug/J0pBKImEddXT0XZvXVFHLVFHLQAAUkctUkctZ11I2NfWmpWLUkgxrqyjzcvIRz4mfXho19fVRj0lSUAnycjEq6mgTUIqUUcsUUcsAABSRy1RRiyAeWnX19VHPiZKQCh+eGjV1dNGPSZ9d2jX19VEOiWkoJfNzMlVSzZNQipRRyxRRywAAFJHLFFGLIB6atfX1UU9Jkk/KH12Z9XV00U8JX13Z9va2qyootTT0pOPg0g/J0xCKVFHLFFHLAAAUkcsUEYsgHlp19fVRj0mSkAofndn1dXTRTwlfXZn2djX19bVwL+6Rz4mSUAoTUMqUUYtUUctAABSRyxQRiyAemrX19VGPSZKQCh+d2fV1dNFPSV9d2fX1tWmopvLycZORS9KQChOQytSRy1SSC0AAFJHLFFGLIB6atfX1Uc+J0lAKH54aNXV00c+Jn53aNfW1UY9JcfFwa2poEpAKE5DK1JILVJILQAAUkctUUYsZlxI2NfWmZSJUUcxramizMvISUAofnhp19fVSD4ngHhq1NTShH1tTUMqUkgtUkgtAABSRy1SRy1QRSygm5DQzszU1NLMyseNh3lNQyqAemrX19VMQilOQyqsqJ/KyMRRRixSSC1SSC0AAFJILVJHLVJHLVFGLFFGLFBGLFBGLFBFLFBFLFBGLFBGLFFGLFFGLFJHLFJHLVJILVJILlJILgAAUkgtUkgtUkctUkctUkcsUkYsUkYsUUYsUUYsUUcsUUcsUkcsUkcsUkcsUkgtUkgtUkguUkguAABSSC5SSC5SSC1SSC1SSC1SRy1SRy1SRy1SRy1SSC1SSC1SSC1SSC1SSC1SSC1SSC5TSC5TSC4AAA=="
      , expectedLabel = "OK"
      }
    , { imageFileBase64 = "Qk32CgAAAAAAADYAAAAoAAAAOQAAABAAAAABABgAAAAAAAAAAADDDgAAww4AAAAAAAAAAAAAKCMbKCMbKCMbKCMbJyIaKCMbKCMbJyIbKCMbKCMbKCMbJyIaKCMbKCMbJyIbKCMbQj44YV5YJiEZJyIaJyIaJyIaJyIaKCMbKCMbJyIaJyIaKCMbJyIaJyIaKCMbKCMbJyIbKCMbKCMbJyIbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbJyIaKCMbJyIbKCMbJyIbKCMbKCMbJyIbKCMbKCMbJyIbKCMbACgjGygjGygjGygjGyciGiciGyciGyciGigjGygjGygjGyciGiciGiciGiciGigjG2FeWcXDwSUhGSYiGiciGiciGiciGigjGygjGyciGiciGiciGiciGiciGigjGygjGyciGigjGygjGyciGigjGygjGygjGygjGygjGygjGygjGygjGygjGyciGiciGiciGiciGiciGigjGygjGyciGigjGygjGyciGigjGwAoIxsoIxsnIhonIholIRknIhonIhomIRomIRomIRknIhomIRomIRomIRomIRomIhphXVfEw8ElIBkmIRklIRkmIRomIRomIRknIhomIRomIRklIRkmIRolIRknIhomIRomIRooIxsnIhsmIRooIxsoIxsoIxsoIxsoIxsoIxsoIxsnIhsnIholIRkmIhonIhomIRomIRomIRonIhsmIRomIRomIRsmIRonIhoAKCMbKCMbYV5ZxcPBJSEZJiIacm5pvbu5JiEaJiEag4B8u7m3wL+9u7q3hIF9JyIaYV5YxsXDtrWywb+9uri2endyJiEZJyIbkI2Jvr26wb+9t7Wzt7WyPjozYl5ZxMPBJiEaYV5YxcPBJiEaJyIaKCMbKCMbKCMbKCMbKCMbKCMbYV5ZxcPBJSEZJiEaYV5Yw8G/JiEZJyIar62qoZ6bJyIarqyqoZ6bJyIaACgjGygjG2FeWMXDwSUgGSYhGqGfnKSiniYhGkM/OcbFw4WDfiYhGl1aVGhkXyciGmFeWMjHxXd1cCYhGo6LiLy6uCUhGU5KQ8fGxG5rZiYhGZCNicPBvyUgGWJeWMTDwSUhGWFdV8XDwSUhGSciGiciGiciGygjGygjGygjGygjG2FeWMXEwiUgGSUgGWNgWsLBvyUgGV5aVcXEwi4pIV5aVcXEwi4pISciGgAoIxsoIxthXljEw8ElIBk3MyzBv716d3IlIRlgXVfEw8ElIBklIRklIRklIRkmIRphXVfEw8ElIBkmIRphXVjDwb8lIRlVUUvHxsRjYFolIRllYl3Cwb8lIBlhXVjEw8ElIRlhXVfFw8ElIRknIhonIhonIhooIxsoIxsoIxsoIxtWUkvJyMa9vLq8u7m/vrvAv7wlIRlhXVfFw8ElIRlhXVfEw8ElIRknIhoAKCMbKCMbYV5YyMfFvLu5v767w8LAMy8nJiEaYV1YyMfFvLu5vby6tbOxeHVwJiEaYV1XxcPBJSAZJiEaYV1Yw8G/JSEZJyIamZeTvLu4vLq4ubi1w8G/JSEZYl5YxMPBJSEZYV1XxcPBJSEZJyIaJyIaJyIaKCMbKCMbKCMbKCMbJyIbwcC9d3VwJSEZj42JsrCuJSEZYV1XxcPBJSEZYV1XxMPBJSEZJyIaACgjGygjG2FeWMXDwSolHTw3MZ6cmZ2blyUhGWFdWMXDwTMvJzQvKI2Kh727uSYhGmFdWMXDwSUhGSYhGmFdWMPBvyYhGSciGygjGyYiGiYiGmJfWcTDwCklHWJeWcTDwSUhGWFdWMXDwSUhGSciGiciGiciGigjGygjGygjGygjGyciGq2rqJ2blyUhGayrqJqYlSYhGWFdV8XDwSsmHmRgWsTDwSUhGSciGgAoIxsoIxthXljFw8EuKSEsJx5lYVy/vrslIRlBPTbFw8FybmomIRqFg36+vbsmIRphXVfJyMZ1c24mIRqPjIi7ubcmIRomIRljYFpNSUMmIRqQjYm+vLorJx5iXljEw8EmIRliX1rIx8VvbWcmIRo7NzAnIhonIhooIxsoIxsoIxsnIhuIhYC8urhGQzzFxMJoZV8mIRphXVfFw8EvKiJlYVvEw8ElIRknIhoAKSQbKSQbY19ZxcPBJSEZJiEaY2Bbw8G/JyIaKCMciIWAvbu5wL+9vLu4gn96JyIacW1otbOwvLq3wcC9uri1eXZxKCMbKCMbj4yIvLu4wL+9uri1eXZxJyIaZGBaxcPBJyIacm9qvr26v768wL+9k5CMJyIbKCMbKCMbKCMbKCMbJyIbRD85xcPBnJqWubi1JiEZJyIaYV1YxcPBJiEZYV1YxMPBJiEZJyIaACgjGygjG2FeWMXDwSUhGSYhGpeVkbm4tSYhGigjGigjGygjGygjGygjGygjGygjGygjGygjGykjGygjGygjGykkGykkGygjGygjGygjGygjGygjGygjGygjGykkGygjGyYhGigjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGyciG6qopcfGxJmXkyYhGiciGmFeWcXDwSYhGmFeWcXDwSYhGiciGwAoIxsoIxtiX1nIx8W/vbvAv726uLV2c24nIhooIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxtiX1nBv70nIhooIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxuBfnrJyMZlYVwnIhooIxtiX1nFw8EnIhpiX1nFw8EnIhooIxsAKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbUExGmJaSJyIbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbQDw1iIWBJyIaQDw1iIWBJyIaKCMbACgjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGygjGwAoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsoIxsAKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbKCMbAA=="
      , expectedLabel = "Repair All"
      }
    ]


decodeBmpImageFromFileBase64 : String -> Result String DecodeBMPImage.DecodeBMPImageResult
decodeBmpImageFromFileBase64 imageFileBase64 =
    imageFileBase64
        |> Base64.toBytes
        |> Result.fromMaybe "Base64 decode error"
        |> Result.andThen DecodeBMPImage.decodeBMPImageFile


buildScreenshotCommonVariationsFromBmpImage :
    DecodeBMPImage.DecodeBMPImageResult
    -> List EveOnline.BotFramework.ReadingFromGameClientScreenshot
buildScreenshotCommonVariationsFromBmpImage image =
    [ { x = 0, y = 0 }
    , { x = 1, y = 0 }
    , { x = 0, y = 1 }
    , { x = 1, y = 1 }
    ]
        |> List.map
            (\offset ->
                deriveImageRepresentationFromNestedListOfPixelsAndOffset
                    offset
                    image.pixels
            )


deriveImageRepresentationFromNestedListOfPixelsAndOffset :
    Location2d
    -> List (List PixelValueRGB)
    -> EveOnline.BotFramework.ReadingFromGameClientScreenshot
deriveImageRepresentationFromNestedListOfPixelsAndOffset offset =
    List.map ((++) (List.repeat offset.x { red = 0, green = 0, blue = 0 }))
        >> (++) (List.repeat offset.y [])
        >> deriveImageRepresentationFromNestedListOfPixels


deriveImageRepresentationFromNestedListOfPixels :
    List (List PixelValueRGB)
    -> EveOnline.BotFramework.ReadingFromGameClientScreenshot
deriveImageRepresentationFromNestedListOfPixels pixelsRows =
    let
        pixels_1x1 ( x, y ) =
            pixelsRows
                |> List.drop y
                |> List.head
                |> Maybe.andThen (List.drop x >> List.head)

        pixels_2x2 =
            bin_pixels_2x2 pixels_1x1

        pixels_4x4 =
            bin_pixels_2x2 pixels_2x2

        width =
            pixelsRows
                |> List.map List.length
                |> List.maximum
                |> Maybe.withDefault 0
    in
    { pixels_1x1 = pixels_1x1
    , pixels_2x2 = pixels_2x2

    {-
       , pixels_4x4 = pixels_4x4
       , bounds =
           { left = 0
           , top = 0
           , right = width
           , bottom = List.length pixelsRows
           }
    -}
    }


bin_pixels_2x2 : (( Int, Int ) -> Maybe PixelValueRGB) -> ( Int, Int ) -> Maybe PixelValueRGB
bin_pixels_2x2 getPixel ( x, y ) =
    let
        originalPixels =
            [ ( 0, 0 )
            , ( 0, 1 )
            , ( 1, 0 )
            , ( 1, 1 )
            ]
                |> List.filterMap (\( offsetX, offsetY ) -> getPixel ( x * 2 + offsetX, y * 2 + offsetY ))

        componentAverage component =
            List.sum (List.map component originalPixels) // List.length originalPixels
    in
    if List.length originalPixels < 1 then
        Nothing

    else
        Just { red = componentAverage .red, green = componentAverage .green, blue = componentAverage .blue }
