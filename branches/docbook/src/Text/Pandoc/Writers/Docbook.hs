{-
Copyright (C) 2006 John MacFarlane <jgm at berkeley dot edu>

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
   Module      : Text.Pandoc.Writers.Docbook
   Copyright   : Copyright (C) 2006 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm at berkeley dot edu>
   Stability   : alpha
   Portability : portable

Conversion of 'Pandoc' documents to Docbook XML.
-}
module Text.Pandoc.Writers.Docbook ( 
                                     writeDocbook
                                   ) where
import Text.Pandoc.Definition
import Text.Pandoc.Shared
import Text.Pandoc.Writers.HTML ( stringToSmartHtml, stringToHtml )
import Text.Html ( stringToHtmlString )
import Text.Regex ( mkRegex, matchRegex )
import Data.Char ( toLower )
import Data.List ( isPrefixOf, partition )
import Text.PrettyPrint.HughesPJ hiding ( Str )

data Element = Blk Block 
             | Sec [Inline] [Element] deriving (Eq, Read, Show)

-- | Returns true on Header block with level at least 'level'
headerAtLeast :: Int -> Block -> Bool
headerAtLeast level (Header x _) = x <= level
headerAtLeast level _ = False

-- | Convert list of Pandoc blocks into list of Elements (hierarchical) 
hierarchicalize :: [Block] -> [Element]
hierarchicalize [] = []
hierarchicalize (block:rest) = 
  case block of
    (Header level title)  -> let (thisSection, rest') = break (headerAtLeast level) rest in
                             (Sec title (hierarchicalize thisSection)):(hierarchicalize rest') 
    x                     -> (Blk x):(hierarchicalize rest)

authorToDocbook options name = indentedInTags options "author" $ 
  if ',' `elem` name
    then -- last name first
      let (lastname, rest) = break (==',') name 
          firstname = removeLeadingSpace rest in
      inTags "firstname" (text $ stringToXML options firstname) <> 
      inTags "surname" (text $ stringToXML options lastname) 
    else -- last name last
      let namewords = words name
          lengthname = length namewords 
          (firstname, lastname) = case lengthname of
            0  -> ("","") 
            1  -> ("", name)
            n  -> (joinWithSep " " (take (n-1) namewords), last namewords) in
       inTags "firstname" (text $ stringToXML options firstname) $$ 
       inTags "surname" (text $ stringToXML options lastname) 

-- | Convert Pandoc document to string in Docbook format.
writeDocbook :: WriterOptions -> Pandoc -> String
writeDocbook options (Pandoc (Meta title authors date) blocks) = 
  let head = if (writerStandalone options)
                then text (writerHeader options)
                else empty
      meta = if (writerStandalone options)
                then indentedInTags options "articleinfo" $
                     (inTags "title" (inlinesToDocbook options title)) $$ 
                     (vcat (map (authorToDocbook options) authors)) $$ 
                     (inTags "date" (text date)) 
                else empty
      blocks' = replaceReferenceLinks blocks
      (noteBlocks, blocks'') = partition isNoteBlock blocks' 
      options' = options {writerNotes = noteBlocks}
      elements = hierarchicalize blocks''
      body = text (writerIncludeBefore options') <>
             vcat (map (elementToDocbook options') elements) $$
             text (writerIncludeAfter options')
      body' = if writerStandalone options'
                then indentedInTags options' "article" (meta $$ body)
                else body in  
  render $ head $$ body' <> text "\n"


inTags tagType contents = text ("<" ++ tagType ++ ">") <> 
  contents <> text ("</" ++ tagType ++ ">") 

indentedInTags options tagType contents = text ("<" ++ tagType ++ ">") $$
  nest (writerTabStop options) contents $$ text ("</" ++ tagType ++ ">") 

elementToDocbook options (Blk block) = blockToDocbook options block 
elementToDocbook options (Sec title elements) = 
  indentedInTags options "section" $
  inTags "title" (wrap options title) $$
  vcat (map (elementToDocbook options) elements) 

blockToDocbook options Blank = text ""
blockToDocbook options Null = empty
blockToDocbook options (Plain lst) = wrap options lst
blockToDocbook options (Para lst) = 
  indentedInTags options "para" (wrap options lst)
blockToDocbook options _ = indentedInTags options "para" (text "Unknown block type")

-- | Take list of inline elements and return wrapped doc.
wrap :: WriterOptions -> [Inline] -> Doc
wrap options lst = fsep $ map (fcat . (map (inlineToDocbook options))) (splitBySpace lst)

-- fill in XML/HTML differences later!
stringToXML options = if writerSmart options
                        then stringToHtml
                        else stringToSmartHtml

inlinesToDocbook options lst = hcat (map (inlineToDocbook options) lst)

inlineToDocbook options (Str str) = text $ stringToXML options str 
inlineToDocbook options Space = char ' '
inlineToDocbook options _ = char '?'

{-
-- | Escape code string as needed for HTML.
codeStringToHtml :: String -> String
codeStringToHtml [] = []
codeStringToHtml (x:xs) = case x of
  '&' -> "&amp;" ++ codeStringToHtml xs
  '<' -> "&lt;"  ++ codeStringToHtml xs
  _   -> x:(codeStringToHtml xs) 

-- | Escape string to HTML appropriate for attributes
attributeStringToHtml :: String -> String
attributeStringToHtml = gsub "\"" "&quot;"

-- | Convert Pandoc block element to HTML.
blockToHtml :: WriterOptions -> Block -> String
blockToHtml options Blank = "\n" 
blockToHtml options Null = ""
blockToHtml options (Plain lst) = inlineListToHtml options lst 
blockToHtml options (Para lst) = "<p>" ++ (inlineListToHtml options lst) ++ "</p>\n"
blockToHtml options (BlockQuote blocks) = 
  if (writerS5 options)
     then  -- in S5, treat list in blockquote specially
           -- if default is incremental, make it nonincremental; 
           -- otherwise incremental
           let inc = not (writerIncremental options) in
           case blocks of 
              [BulletList lst] -> blockToHtml (options {writerIncremental = 
                                                        inc}) (BulletList lst)
              [OrderedList lst] -> blockToHtml (options {writerIncremental =
                                                       inc}) (OrderedList lst)
              otherwise         -> "<blockquote>\n" ++ 
                                   (concatMap (blockToHtml options) blocks) ++
                                   "</blockquote>\n"
     else "<blockquote>\n" ++ (concatMap (blockToHtml options) blocks) ++ 
          "</blockquote>\n"
blockToHtml options (Note ref lst) = 
  let contents = (concatMap (blockToHtml options) lst) in
  "<li id=\"fn" ++ ref ++ "\">" ++ contents ++ " <a href=\"#fnref" ++ ref ++ 
  "\" class=\"footnoteBacklink\" title=\"Jump back to footnote " ++ ref ++ 
  "\">&#8617;</a></li>\n" 
blockToHtml options (Key _ _) = ""
blockToHtml options (CodeBlock str) = 
  "<pre><code>" ++ (codeStringToHtml str) ++ "\n</code></pre>\n"
blockToHtml options (RawHtml str) = str 
blockToHtml options (BulletList lst) = 
  let attribs = if (writerIncremental options)
                   then " class=\"incremental\"" 
                   else "" in
  "<ul" ++ attribs ++ ">\n" ++ (concatMap (listItemToHtml options) lst) ++ 
  "</ul>\n"
blockToHtml options (OrderedList lst) = 
  let attribs = if (writerIncremental options)
                   then " class=\"incremental\""
                   else "" in
  "<ol" ++ attribs ++ ">\n" ++ (concatMap (listItemToHtml options) lst) ++ 
  "</ol>\n"
blockToHtml options HorizontalRule = "<hr />\n"
blockToHtml options (Header level lst) = 
  let contents = inlineListToHtml options lst in
  if ((level > 0) && (level <= 6))
      then "<h" ++ (show level) ++ ">" ++ contents ++ 
           "</h" ++ (show level) ++ ">\n"
      else "<p>" ++ contents ++ "</p>\n"
listItemToHtml options list = 
  "<li>" ++ (concatMap (blockToHtml options) list) ++ "</li>\n"

-- | Convert list of Pandoc inline elements to HTML.
inlineListToHtml :: WriterOptions -> [Inline] -> String
inlineListToHtml options lst = 
  -- consolidate adjacent Str and Space elements for more intelligent 
  -- smart typography filtering
  let lst' = consolidateList lst in
  concatMap (inlineToHtml options) lst'

-- | Convert Pandoc inline element to HTML.
inlineToHtml :: WriterOptions -> Inline -> String
inlineToHtml options (Emph lst) = 
  "<em>" ++ (inlineListToHtml options lst) ++ "</em>"
inlineToHtml options (Strong lst) = 
  "<strong>" ++ (inlineListToHtml options lst) ++ "</strong>"
inlineToHtml options (Code str) =  
  "<code>" ++ (codeStringToHtml str) ++ "</code>"
inlineToHtml options (Str str) = 
  if (writerSmart options) then stringToSmartHtml str else stringToHtml str
inlineToHtml options (TeX str) = (codeStringToHtml str)
inlineToHtml options (HtmlInline str) = str
inlineToHtml options (LineBreak) = "<br />\n"
inlineToHtml options Space = " "
inlineToHtml options (Link text (Src src tit)) = 
  let title = attributeStringToHtml tit in
  if (isPrefixOf "mailto:" src)
     then obfuscateLink options text src 
     else "<a href=\"" ++ (codeStringToHtml src) ++ "\"" ++ 
          (if tit /= "" then " title=\"" ++ title  ++ "\">" else ">") ++ 
          (inlineListToHtml options text) ++ "</a>"
inlineToHtml options (Link text (Ref ref)) = 
  "[" ++ (inlineListToHtml options text) ++ "][" ++ 
  (inlineListToHtml options ref) ++ "]"  
  -- this is what markdown does, for better or worse
inlineToHtml options (Image alt (Src source tit)) = 
  let title = attributeStringToHtml tit
      alternate = inlineListToHtml options alt in 
  "<img src=\"" ++ source ++ "\"" ++ 
  (if tit /= "" then " title=\"" ++ title ++ "\"" else "") ++ 
  (if alternate /= "" then " alt=\"" ++ alternate ++ "\"" else "") ++ ">"
inlineToHtml options (Image alternate (Ref ref)) = 
  "![" ++ (inlineListToHtml options alternate) ++ "][" ++ 
  (inlineListToHtml options ref) ++ "]"
inlineToHtml options (NoteRef ref) = 
  "<sup class=\"footnoteRef\" id=\"fnref" ++ ref ++ "\"><a href=\"#fn" ++ 
  ref ++ "\">" ++ ref ++ "</a></sup>"
-}
