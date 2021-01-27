# Elm Programming Language - Forward Pipe (`|>`) and Function Composition (`>>`) Operators

When getting started with programming in Elm, reading the program code of typical real-world projects can be challenging. Two related language elements often confuse newcomers:

+ Forward pipe operator, written as `|>`
+ Forward function composition operator, written as `>>`

To understand how they work, a good start is looking at their description in the official docs at https://package.elm-lang.org/packages/elm/core/latest/Basics# and https://elm-lang.org/docs/syntax#operators

These operators don't do anything that we couldn't achieve with other language elements. They only allow us to write a function differently. We can rewrite any program without them. But, if these are not even strictly necessary, why do we even use them? The reason is that they can help improve the readability of the program code. Just like abbreviations in natural language, they act as shortcuts to consolidate common patterns in our code.

An excellent way to learn how a language element works is to look at an alternative implementation that does the same without that unknown element. We will look at different program codes that all do the same—one version with the operator and one version without the operator.

Suppose our program does some parsing, and we want to extract a substring from a string after the first comma character. This table of inputs and outputs illustrates the behavior we are looking for:

| input       | output    |
| ----------- | --------- |
| `"a, b, c"` | `" b, c"` |
| `"test"`    | `""`      |

We can implement this function with the following syntax:

```Elm
get_substring_after_first_comma : String -> String
get_substring_after_first_comma originalString =
    String.join "," (List.drop 1 (String.split "," originalString))
```

I am not going into the details of the functions we combine here. These are all part of the core library, and you can read more about them at https://package.elm-lang.org/packages/elm/core/latest/String and https://package.elm-lang.org/packages/elm/core/latest/List

If we had a more complex function, the expression's code line would become longer. To counteract long lines, we could format the expression over multiple lines:

```Elm
get_substring_after_first_comma : String -> String
get_substring_after_first_comma originalString =
    String.join ","
        (List.drop 1
            (String.split "," originalString)
        )
```

## `|>` Operator

So far, so simple. But when you read actual projects code, you might see this function expressed using the forward pipe operator like this:

```Elm
get_substring_after_first_comma : String -> String
get_substring_after_first_comma originalString =
    originalString
        |> String.split ","
        |> List.drop 1
        |> String.join ","
```

This way, we get rid of the parentheses and the indentation that grows with the number of processing steps.
But another difference is more important in my opinion: The piped variant better visualizes the direction of data flow: The functions appear in the same order as we apply them to our data: First `String.split`, then `List.drop`, then `String.join`.

## `>>` Operator

The `>>` operator lets us combine two functions into one, in this enables a more concise representation of our string processing function:

```Elm
get_substring_after_first_comma : String -> String
get_substring_after_first_comma =
    String.split ","
        >> List.drop 1
        >> String.join ","
```

The function composition operator helps us to clarify that we use the argument only once. In cases where we use small functions inline, it saves us from writing a lambda expression.
Here is an example from a current project:

```Elm
getSubstringBetweenXmlTagsAfterMarker : String -> String -> Maybe String
getSubstringBetweenXmlTagsAfterMarker marker xmlString =
    String.split marker xmlString
        |> List.drop 1
        |> List.head
        |> Maybe.andThen (String.split ">" >> List.drop 1 >> List.head)
        |> Maybe.andThen (String.split "<" >> List.head)
```

And here is how we could write it without the `>>` operator: 

```Elm
getSubstringBetweenXmlTagsAfterMarker : String -> String -> Maybe String
getSubstringBetweenXmlTagsAfterMarker marker xmlString =
    String.split marker xmlString
        |> List.drop 1
        |> List.head
        |> Maybe.andThen (\s -> s |> String.split ">" |> List.drop 1 |> List.head)
        |> Maybe.andThen (\s -> s |> String.split "<" |> List.head)
```

For more guides on programming, see the overview at https://to.botengine.org/guide/overview
