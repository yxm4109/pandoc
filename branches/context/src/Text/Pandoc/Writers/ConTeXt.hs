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
                      then "" 
                      else "\\setcounter{secnumdepth}{0}\n" 
      header     = writerHeader options in
  header ++ secnumline ++ titleblock ++ "\\starttext\n\\maketitle\n\n"

-- escape things as needed for ConTeXt (also ldots, dashes, quotes, etc.) 

escapeBrackets  = backslashEscape "{}"
escapeSpecial   = backslashEscape "$%&~_#"

escapeBackslash = substitute "\\" "\\textbackslash{}" 
fixBackslash    = substitute "\\textbackslash\\{\\}" "\\textbackslash{}"
escapeHat       = substitute "^" "\\^{}"
escapeBar       = substitute "|" "\\textbar{}"
escapeLt        = substitute "<" "\\textless{}"
escapeGt        = substitute ">" "\\textgreater{}"

-- | Escape string for ConTeXt
stringToConTeXt :: String -> String
stringToConTeXt = escapeGt . escapeLt . escapeBar . escapeHat . 
                escapeSpecial . fixBackslash . escapeBrackets . 
                escapeBackslash 

-- | Remove all code elements from list of inline elements
-- (because it's illegal to have a \\verb inside a command argument)
deVerb :: [Inline] -> [Inline]
deVerb [] = []
deVerb ((Code str):rest) = (Str str):(deVerb rest)
deVerb (other:rest) = other:(deVerb rest)

-- | Convert Pandoc block element to ConTeXt.
blockToConTeXt :: Block     -- ^ Block to convert
             -> String 
blockToConTeXt Null = ""
blockToConTeXt (Plain lst) = inlineListToConTeXt lst ++ "\n"
blockToConTeXt (Para lst) = (inlineListToConTeXt lst) ++ "\n\n"
blockToConTeXt (BlockQuote lst) = "\\begin{quote}\n" ++ 
    (concatMap blockToConTeXt lst) ++ "\\end{quote}\n"
blockToConTeXt (CodeBlock str) = "\\begin{verbatim}\n" ++ str ++ 
    "\n\\end{verbatim}\n"
blockToConTeXt (RawHtml str) = ""
blockToConTeXt (BulletList lst) = "\\begin{itemize}\n" ++ 
    (concatMap listItemToConTeXt lst) ++ "\\end{itemize}\n"
blockToConTeXt (OrderedList lst) = "\\begin{enumerate}\n" ++ 
    (concatMap listItemToConTeXt lst) ++ "\\end{enumerate}\n"
blockToConTeXt (DefinitionList lst) = 
    let defListItemToConTeXt (term, def) = "\\item[" ++ 
           substitute "]" "\\]" (inlineListToConTeXt term) ++ "] " ++
           concatMap blockToConTeXt def
    in  "\\begin{description}\n" ++ concatMap defListItemToConTeXt lst ++ 
        "\\end{description}\n"
blockToConTeXt HorizontalRule = 
    "\\begin{center}\\rule{3in}{0.4pt}\\end{center}\n\n"
blockToConTeXt (Header level lst) = 
    if (level > 0) && (level <= 3)
       then "\\" ++ (concat (replicate (level - 1) "sub")) ++ "section{" ++ 
            (inlineListToConTeXt (deVerb lst)) ++ "}\n\n"
       else (inlineListToConTeXt lst) ++ "\n\n"
blockToConTeXt (Table caption aligns widths heads rows) =
    let colWidths = map printDecimal widths
        colDescriptors = concat $ zipWith
                                  (\width align -> ">{\\PBS" ++ 
                                  (case align of 
                                         AlignLeft -> "\\raggedright"
                                         AlignRight -> "\\raggedleft"
                                         AlignCenter -> "\\centering"
                                         AlignDefault -> "\\raggedright") ++
                                  "\\hspace{0pt}}p{" ++ width ++ 
                                  "\\textwidth}")
                                  colWidths aligns
        headers        = tableRowToConTeXt heads 
        captionText    = inlineListToConTeXt caption 
        tableBody      = "\\begin{tabular}{" ++ colDescriptors ++ "}\n" ++
                         headers ++ "\\hline\n" ++ 
                         (concatMap tableRowToConTeXt rows) ++ 
                         "\\end{tabular}\n" 
        centered str   = "\\begin{center}\n" ++ str ++ "\\end{center}\n" in
    if null captionText
      then centered tableBody ++ "\n"
      else "\\begin{table}[h]\n" ++ centered tableBody ++ "\\caption{" ++
           captionText ++ "}\n" ++ "\\end{table}\n\n" 

printDecimal :: Float -> String
printDecimal = printf "%.2f" 

tableColumnWidths cols = map (length . (concatMap blockToConTeXt)) cols

tableRowToConTeXt cols = joinWithSep " & " (map (concatMap blockToConTeXt) cols) ++ "\\hfil\\break\n"

listItemToConTeXt list = "\\item " ++ 
    (concatMap blockToConTeXt list) 

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
inlineToConTeXt (Emph lst) = "\\emph{" ++ 
    (inlineListToConTeXt (deVerb lst)) ++ "}"
inlineToConTeXt (Strong lst) = "\\textbf{" ++ 
    (inlineListToConTeXt (deVerb lst)) ++ "}"
inlineToConTeXt (Code str) = "\\verb" ++ [chr] ++ stuffing ++ [chr]
                     where stuffing = str 
                           chr      = ((enumFromTo '!' '~') \\ stuffing) !! 0
inlineToConTeXt (Quoted SingleQuote lst) =
  let s1 = if (not (null lst)) && (isQuoted (head lst)) then "\\," else ""
      s2 = if (not (null lst)) && (isQuoted (last lst)) then "\\," else "" in
  "`" ++ s1 ++ inlineListToConTeXt lst ++ s2 ++ "'"
inlineToConTeXt (Quoted DoubleQuote lst) =
  let s1 = if (not (null lst)) && (isQuoted (head lst)) then "\\," else ""
      s2 = if (not (null lst)) && (isQuoted (last lst)) then "\\," else "" in
  "``" ++ s1 ++ inlineListToConTeXt lst ++ s2 ++ "''"
inlineToConTeXt Apostrophe = "'"
inlineToConTeXt EmDash = "---"
inlineToConTeXt EnDash = "--"
inlineToConTeXt Ellipses = "\\ldots{}"
inlineToConTeXt (Str str) = stringToConTeXt str
inlineToConTeXt (TeX str) = str
inlineToConTeXt (HtmlInline str) = ""
inlineToConTeXt (LineBreak) = "\\hfil\\break\n"
inlineToConTeXt Space = " "
inlineToConTeXt (Link text (src, tit)) = 
    "\\href{" ++ src ++ "}{" ++ (inlineListToConTeXt (deVerb text)) ++ "}"
inlineToConTeXt (Image alternate (source, tit)) = 
    "\\includegraphics{" ++ source ++ "}" 
inlineToConTeXt (Note contents) = 
    "\\footnote{" ++ (stripTrailingNewlines $ concatMap blockToConTeXt contents)  ++ "}"
