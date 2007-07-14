{-
Copyright (C) 2007 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module      : Text.Pandoc.Writers.ConTeXt
   Copyright   : Copyright (C) 2006-7 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha 
   Portability : portable

Conversion of 'Pandoc' format into ConTeXt.
-}
module Text.Pandoc.Writers.ConTeXt ( 
                                  writeConTeXt 
                                 ) where
import Text.Pandoc.Definition
import Text.Pandoc.Shared
import Text.Printf ( printf )
import Data.List ( (\\) )

-- | Convert Pandoc to ConTeXt.
writeConTeXt :: WriterOptions -> Pandoc -> String
writeConTeXt options (Pandoc meta blocks) = 
  let body = (writerIncludeBefore options) ++ 
             (concatMap blockToConTeXt blocks) ++
             (writerIncludeAfter options)
      head = if writerStandalone options
                then latexHeader options meta
                else ""
      toc  = if writerTableOfContents options
                then "\\placecontent\n\n"
                else "" 
      foot = if writerStandalone options
                then "\n\\stoptext\n"
                else ""
  in  head ++ toc ++ body ++ foot

-- | Insert bibliographic information into ConTeXt header.
latexHeader :: WriterOptions -- ^ Options, including ConTeXt header
            -> Meta          -- ^ Meta with bibliographic information
            -> String
latexHeader options (Meta title authors date) =
  let titletext = if null title
                     then "" 
                     else inlineListToConTeXt title
      authorstext = if null authors
                       then ""
                       else if length authors == 1
                            then stringToConTeXt $ head authors
                            else stringToConTeXt $ (joinWithSep ", " $
                                 init authors) ++ " & " ++ last authors
      datetext   = if date == ""
                       then "" 
                       else stringToConTeXt date
      titleblock = "\\doctitle{" ++ titletext ++ "}\n\
                   \ \\author{" ++ authorstext ++ "}\n\
                   \ \\date{" ++ datetext ++ "}\n\n"
      secnumline = if (writerNumberSections options)
                      then "\\setupheads[sectionnumber=yes]\n" 
                      else "\\setupheads[sectionnumber=no]\n"
      header     = writerHeader options in
  header ++ secnumline ++ titleblock ++ "\\starttext\n\\maketitle\n\n"

-- escape things as needed for ConTeXt

escapeCharForConTeXt :: Char -> String
escapeCharForConTeXt ch =
 case ch of
    '{'  -> "\\letteropenbrace{}"
    '}'  -> "\\letterclosebrace{}"
    '\\' -> "\\letterbackslash{}"
    '$'  -> "\\$"
    '|'  -> "\\letterbar{}"
    '^'  -> "\\letterhat{}"
    '%'  -> "\\%"
    '~'  -> "\\lettertilde{}"
    '&'  -> "\\&"
    '#'  -> "\\#"
    '<'  -> "\\letterless{}"
    '>'  -> "\\lettermore{}"
    '_'  -> "\\letterunderscore{}"
    x    -> [x]

-- | Escape string for ConTeXt
stringToConTeXt :: String -> String
stringToConTeXt = concatMap escapeCharForConTeXt

-- | Convert Pandoc block element to ConTeXt.
blockToConTeXt :: Block -> String 
blockToConTeXt Null = ""
blockToConTeXt (Plain lst) = inlineListToConTeXt lst ++ "\n"
blockToConTeXt (Para lst) = (inlineListToConTeXt lst) ++ "\n\n"
blockToConTeXt (BlockQuote lst) = "\\startquotation\n" ++ 
    (concatMap blockToConTeXt lst) ++ "\\stopquotation\n\n"
blockToConTeXt (CodeBlock str) = "\\starttyping\n" ++ str ++ 
    "\n\\stoptyping\n"
blockToConTeXt (RawHtml str) = ""
blockToConTeXt (BulletList lst) = "\\startltxitem\n" ++ 
    concatMap listItemToConTeXt lst ++ "\\stopltxitem\n"
blockToConTeXt (OrderedList lst) = "\\startltxenum\n" ++
    concatMap listItemToConTeXt lst ++ "\\stopltxenum\n"
blockToConTeXt (DefinitionList lst) = 
    let defListItemToConTeXt (term, def) = "\\startdescr{" ++
           inlineListToConTeXt term ++ "}\n" ++
           concatMap blockToConTeXt def ++ "\n\\stopdescr\n"
    in  concatMap defListItemToConTeXt lst ++ "\n"
blockToConTeXt HorizontalRule = 
    "\\thinrule\n\n"
blockToConTeXt (Header level lst) = 
    if (level > 0) && (level <= 3)
       then "\\" ++ (concat (replicate (level - 1) "sub")) ++ "section{" ++ 
            (inlineListToConTeXt lst) ++ "}\n\n"
       else (inlineListToConTeXt lst) ++ "\n\n"
blockToConTeXt (Table caption aligns widths heads rows) =
    let colWidths = map printDecimal widths
        colDescriptor colWidth alignment = (case alignment of
                                               AlignLeft    -> "l"
                                               AlignRight   -> "r"
                                               AlignCenter  -> ""
                                               AlignDefault -> "l") ++
                                           "p(" ++ colWidth ++ "\\textwidth)|"
        colDescriptors = "|" ++ (concat $ 
                                 zipWith colDescriptor colWidths aligns)
        headers        = tableRowToConTeXt heads 
        captionText    = inlineListToConTeXt caption 
        captionCode    = if null captionText
                            then ""
                            else "\\placetable[here]{" ++ captionText ++ "}\n"
        tableBody      = "\\starttable[" ++ colDescriptors ++ "]\n" ++
                         "\\HL\n" ++ headers ++ "\\HL\n" ++ 
                         (concatMap tableRowToConTeXt rows) ++ "\\HL\n" ++
                         "\\stoptable\n" 
    in  captionCode ++ tableBody ++ "\n"

printDecimal :: Float -> String
printDecimal = printf "%.2f" 

tableColumnWidths cols = map (length . (concatMap blockToConTeXt)) cols

tableRowToConTeXt cols = concatMap (("\\NC " ++) . (concatMap blockToConTeXt)) cols ++ "\\NC\\AR\n"

listItemToConTeXt list = "\\item " ++ concatMap blockToConTeXt list

-- | Convert list of inline elements to ConTeXt.
inlineListToConTeXt :: [Inline]  -- ^ Inlines to convert
                    -> String
inlineListToConTeXt lst = 
  concatMap inlineToConTeXt lst

isQuoted :: Inline -> Bool
isQuoted (Quoted _ _) = True
isQuoted Apostrophe = True
isQuoted _ = False

-- | Convert inline element to ConTeXt
inlineToConTeXt :: Inline    -- ^ Inline to convert
              -> String
inlineToConTeXt (Emph lst) = "{\\em " ++ 
    (inlineListToConTeXt lst) ++ "}"
inlineToConTeXt (Strong lst) = "{\\bf{ " ++ 
    (inlineListToConTeXt lst) ++ "}"
inlineToConTeXt (Code str) = "\\type{" ++ str ++ "}"
inlineToConTeXt (Quoted SingleQuote lst) = 
  "\\quote{" ++ inlineListToConTeXt lst ++ "}"
inlineToConTeXt (Quoted DoubleQuote lst) =
  "\\quotation{" ++ inlineListToConTeXt lst ++ "}"
inlineToConTeXt Apostrophe = "'"
inlineToConTeXt EmDash = "---"
inlineToConTeXt EnDash = "--"
inlineToConTeXt Ellipses = "\\ldots{}"
inlineToConTeXt (Str str) = stringToConTeXt str
inlineToConTeXt (TeX str) = str
inlineToConTeXt (HtmlInline str) = ""
inlineToConTeXt (LineBreak) = "\\hfil\\break\n"
inlineToConTeXt Space = " "
inlineToConTeXt (Link text (src, _)) = 
  "\\useurl[x][" ++ src ++ "][][" ++ inlineListToConTeXt text ++ "]\\from[x]" 
inlineToConTeXt (Image alternate (src, tit)) = 
  "\\placefigure\n[]\n[fig:" ++ inlineListToConTeXt alternate ++ "]\n{" ++
  tit ++ "\n{\\externalfigure[" ++ src ++ "]}" 
inlineToConTeXt (Note contents) = 
    "\\footnote{" ++ concatMap blockToConTeXt contents ++ "}"
