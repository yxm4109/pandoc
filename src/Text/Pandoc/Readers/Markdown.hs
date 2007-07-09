{-
Copyright (C) 2006-7 John MacFarlane <jgm@berkeley.edu>

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
   Module      : Text.Pandoc.Readers.Markdown
   Copyright   : Copyright (C) 2006-7 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Conversion of markdown-formatted plain text to 'Pandoc' document.
-}
module Text.Pandoc.Readers.Markdown ( 
                                     readMarkdown 
                                    ) where

import Data.List ( findIndex, sortBy, transpose, isSuffixOf, intersect, lookup )
import Data.Char ( isAlphaNum )
import Text.ParserCombinators.Pandoc
import Text.Pandoc.Definition
import Text.Pandoc.Readers.LaTeX ( rawLaTeXInline, rawLaTeXEnvironment )
import Text.Pandoc.Shared 
import Text.Pandoc.Readers.HTML ( rawHtmlBlock, 
                                  anyHtmlBlockTag, anyHtmlInlineTag,
                                  anyHtmlTag, anyHtmlEndTag,
                                  htmlEndTag, extractTagType,
                                  htmlBlockElement )
import Text.Pandoc.Entities ( characterEntity, decodeEntities )
import Text.ParserCombinators.Parsec

-- | Read markdown from an input string and return a Pandoc document.
readMarkdown :: ParserState -> String -> Pandoc
readMarkdown state str = (readWith parseMarkdown) state (str ++ "\n\n")

-- | Parse markdown string with default options and print result (for testing).
testString :: String -> IO ()
testString = testStringWith parseMarkdown 

--
-- Constants and data structure definitions
--

spaceChars = " \t"
endLineChars = "\n"
labelStart = '['
labelEnd = ']'
labelSep = ':'
srcStart = '('
srcEnd = ')'
imageStart = '!'
noteStart = '^'
codeStart = '`'
codeEnd = '`'
emphStart = '*'
emphEnd = '*'
emphStartAlt = '_'
emphEndAlt = '_'
autoLinkStart = '<'
autoLinkEnd = '>'
mathStart = '$'
mathEnd = '$'
bulletListMarkers = "*+-"
escapeChar = '\\'
hruleChars = "*-_"
quoteChars = "'\""
atxHChar = '#'
titleOpeners = "\"'("
setextHChars = ['=','-']
blockQuoteChar = '>'
hyphenChar = '-'
ellipsesChar = '.'
listColSepChar = '|'
entityStart = '&'

-- treat these as potentially non-text when parsing inline:
specialChars = [escapeChar, labelStart, labelEnd, emphStart, emphEnd,
                emphStartAlt, emphEndAlt, codeStart, codeEnd, autoLinkEnd,
                autoLinkStart, mathStart, mathEnd, imageStart, noteStart,
                hyphenChar, ellipsesChar, entityStart] ++ quoteChars

--
-- auxiliary functions
--

-- | Skip a single endline if there is one.
skipEndline = option Space endline

indentSpaces = do
  state <- getState
  let tabStop = stateTabStop state
  try (count tabStop (char ' ')) <|> 
    (do{many (char ' '); string "\t"}) <?> "indentation"

nonindentSpaces = do
  state <- getState
  let tabStop = stateTabStop state
  choice (map (\n -> (try (count n (char ' ')))) (reverse [0..(tabStop - 1)]))

-- | Fail if reader is in strict markdown syntax mode.
failIfStrict = do
    state <- getState
    if stateStrict state then fail "Strict markdown mode" else return ()

-- | Fail unless we're at beginning of a line.
failUnlessBeginningOfLine = do
  pos <- getPosition
  if sourceColumn pos == 1 then return () else fail "not beginning of line"

-- | Fail unless we're in "smart typography" mode.
failUnlessSmart = do
  state <- getState
  if stateSmart state then return () else fail "Smart typography feature"

--
-- document structure
--

titleLine = try (do
  char '%'
  skipSpaces
  line <- manyTill inline newline
  return line)

authorsLine = try (do
  char '%'
  skipSpaces
  authors <- sepEndBy (many1 (noneOf ",;\n")) (oneOf ",;")
  newline
  return (map (decodeEntities . removeLeadingTrailingSpace) authors))

dateLine = try (do
  char '%'
  skipSpaces
  date <- many (noneOf "\n")
  newline
  return (decodeEntities $ removeTrailingSpace date))

titleBlock = try (do
  failIfStrict
  title <- option [] titleLine
  author <- option [] authorsLine
  date <- option "" dateLine
  option "" blanklines
  return (title, author, date))

parseMarkdown = do
  updateState (\state -> state { stateParseRaw = True }) -- markdown allows raw HTML
  (title, author, date) <- option ([],[],"") titleBlock
  -- go through once just to get list of reference keys
  refs <- manyTill (referenceKey <|> (do l <- lineClump
                                         return (LineClump l))) eof 
  let keys = map (\(KeyBlock label target) -> (label, target)) $ 
                 filter isKeyBlock refs
  let rawlines = map (\(LineClump ln) -> ln) $ filter isLineClump refs
  setInput $ concat rawlines -- with keys stripped out 
  updateState (\state -> state { stateKeys = keys })
  -- now go through for notes
  refs <- manyTill (noteBlock <|> (do l <- lineClump
                                      return (LineClump l))) eof 
  let notes = map (\(NoteBlock label blocks) -> (label, blocks)) $ 
                   filter isNoteBlock refs
  let rawlines = map (\(LineClump ln) -> ln) $ filter isLineClump refs
  setInput $ concat rawlines -- with note blocks and keys stripped out 
  updateState (\state -> state { stateNotes = notes })
  blocks <- parseBlocks  -- go through again, for real
  let blocks' = filter (/= Null) blocks
  return (Pandoc (Meta title author date) blocks')

-- 
-- initial pass for references
--

referenceKey = try $ do
  nonindentSpaces
  label <- reference
  char labelSep
  skipSpaces
  option ' ' (char autoLinkStart)
  src <- many (noneOf [autoLinkEnd, '\n', '\t', ' '])
  option ' ' (char autoLinkEnd)
  tit <- option "" title 
  blanklines 
  return $ KeyBlock label (removeTrailingSpace src,  tit)

noteMarker = try (do
  char labelStart
  char noteStart
  manyTill (noneOf " \t\n") (char labelEnd))

rawLine = try (do
  notFollowedBy' blankline
  notFollowedBy' noteMarker
  contents <- many1 nonEndline
  end <- option "" (do
                      newline
                      option "" (try indentSpaces)
                      return "\n")
  return (contents ++ end))

rawLines = do
    lines <- many1 rawLine
    return (concat lines)

noteBlock = try $ do
  failIfStrict
  ref <- noteMarker
  char ':'
  option ' ' (try blankline)
  option "" (try indentSpaces)
  raw <- sepBy rawLines (try (do {blankline; indentSpaces}))
  option "" blanklines
  -- parse the extracted text, which may contain various block elements:
  rest <- getInput
  setInput $ (joinWithSep "\n" raw) ++ "\n\n"
  contents <- parseBlocks
  setInput rest
  return (NoteBlock ref contents)

--
-- parsing blocks
--

parseBlocks = manyTill block eof

block = choice [ header 
               , table
               , codeBlock
               , hrule
               , list
               , blockQuote
               , htmlBlock
               , rawLaTeXEnvironment'
               , para
               , plain
               , nullBlock ] <?> "block"

--
-- header blocks
--

header = choice [ setextHeader, atxHeader ] <?> "header"

atxHeader = try (do
  lead <- many1 (char atxHChar)
  skipSpaces
  txt <- manyTill inline atxClosing
  return (Header (length lead) (normalizeSpaces txt)))

atxClosing = try (do
  skipMany (char atxHChar)
  skipSpaces
  newline
  option "" blanklines)

setextHeader = choice $ 
               map (\x -> setextH x) (enumFromTo 1 (length setextHChars))

setextH n = try (do
  txt <- many1Till inline newline
  many1 (char (setextHChars !! (n-1)))
  skipSpaces
  newline
  option "" blanklines
  return (Header n (normalizeSpaces txt)))

--
-- hrule block
--

hruleWith chr = try (do
  skipSpaces
  char chr
  skipSpaces
  char chr
  skipSpaces
  char chr
  skipMany (oneOf (chr:spaceChars))
  newline
  option "" blanklines
  return HorizontalRule)

hrule = choice (map hruleWith hruleChars) <?> "hrule"

--
-- code blocks
--

indentedLine = try (do
  indentSpaces
  result <- manyTill anyChar newline
  return (result ++ "\n"))

-- two or more indented lines, possibly separated by blank lines
indentedBlock = try (do 
  res1 <- indentedLine
  blanks <- many blankline 
  res2 <- choice [indentedBlock, indentedLine]
  return (res1 ++ blanks ++ res2))

codeBlock = do
  result <- choice [indentedBlock, indentedLine]
  option "" blanklines
  return (CodeBlock (stripTrailingNewlines result))

--
-- block quotes
--

emacsBoxQuote = try (do
  failIfStrict
  string ",----"
  manyTill anyChar newline
  raw <- manyTill (try (do 
                          char '|'
                          option ' ' (char ' ')
                          result <- manyTill anyChar newline
                          return result))
                   (string "`----")
  manyTill anyChar newline
  option "" blanklines
  return raw)

emailBlockQuoteStart = try (do
  nonindentSpaces
  char blockQuoteChar
  option ' ' (char ' ')
  return "> ")

emailBlockQuote = try (do
  emailBlockQuoteStart
  raw <- sepBy (many (choice [nonEndline, 
                              (try (do 
                                      endline
                                      notFollowedBy' emailBlockQuoteStart
                                      return '\n'))]))
               (try (do {newline; emailBlockQuoteStart}))
  newline <|> (do{ eof; return '\n' })
  option "" blanklines
  return raw)

blockQuote = do 
  raw <- choice [ emailBlockQuote, emacsBoxQuote ]
  -- parse the extracted block, which may contain various block elements:
  rest <- getInput
  setInput $ (joinWithSep "\n" raw) ++ "\n\n"
  contents <- parseBlocks
  setInput rest
  return (BlockQuote contents)
 
--
-- list blocks
--

list = choice [ bulletList, orderedList, definitionList ] <?> "list"

bulletListStart = try (do
  option ' ' newline -- if preceded by a Plain block in a list context
  nonindentSpaces
  notFollowedBy' hrule  -- because hrules start out just like lists
  oneOf bulletListMarkers
  spaceChar
  skipSpaces)

standardOrderedListStart = try (do
  many1 digit
  char '.')

extendedOrderedListStart = try (do
  failIfStrict
  oneOf ['a'..'n']
  oneOf ".)")

orderedListStart = try $ do
  option ' ' newline -- if preceded by a Plain block in a list context
  nonindentSpaces
  standardOrderedListStart <|> extendedOrderedListStart
  oneOf spaceChars
  skipSpaces

-- parse a line of a list item (start = parser for beginning of list item)
listLine start = try (do
  notFollowedBy' start
  notFollowedBy blankline
  notFollowedBy' (do 
                    indentSpaces
                    many (spaceChar)
                    choice [bulletListStart, orderedListStart])
  line <- manyTill anyChar newline
  return (line ++ "\n"))

-- parse raw text for one list item, excluding start marker and continuations
rawListItem start = try (do
  start
  result <- many1 (listLine start)
  blanks <- many blankline
  return ((concat result) ++ blanks))

-- continuation of a list item - indented and separated by blankline 
-- or (in compact lists) endline.
-- note: nested lists are parsed as continuations
listContinuation start = try (do
  lookAhead indentSpaces
  result <- many1 (listContinuationLine start)
  blanks <- many blankline
  return ((concat result) ++ blanks))

listContinuationLine start = try (do
  notFollowedBy' blankline
  notFollowedBy' start
  option "" (try indentSpaces)
  result <- manyTill anyChar newline
  return (result ++ "\n"))

listItem start = try (do 
  first <- rawListItem start
  continuations <- many (listContinuation start)
  -- parsing with ListItemState forces markers at beginning of lines to
  -- count as list item markers, even if not separated by blank space.
  -- see definition of "endline"
  state <- getState
  let oldContext = stateParserContext state
  setState $ state {stateParserContext = ListItemState}
  -- parse the extracted block, which may contain various block elements:
  rest <- getInput
  let raw = concat (first:continuations)
  setInput raw
  contents <- parseBlocks
  setInput rest
  updateState (\st -> st {stateParserContext = oldContext})
  return contents)

orderedList = try (do
  items <- many1 (listItem orderedListStart)
  let items' = compactify items
  return (OrderedList items'))

bulletList = try (do
  items <- many1 (listItem bulletListStart)
  let items' = compactify items
  return (BulletList items'))

-- definition lists

definitionListItem = try $ do
  notFollowedBy blankline
  notFollowedBy' indentSpaces
  term <- manyTill inline newline
  raw <- many1 defRawBlock
  state <- getState
  let oldContext = stateParserContext state
  -- parse the extracted block, which may contain various block elements:
  rest <- getInput
  setInput (concat raw)
  contents <- parseBlocks
  setInput rest
  updateState (\st -> st {stateParserContext = oldContext})
  return ((normalizeSpaces term), contents)

defRawBlock = try $ do
  char ':'
  state <- getState
  let tabStop = stateTabStop state
  try (count (tabStop - 1) (char ' ')) <|> (do{many (char ' '); string "\t"})
  firstline <- anyLine
  rawlines <- many (do {notFollowedBy' blankline; indentSpaces; anyLine})
  trailing <- option "" blanklines
  return $ firstline ++ "\n" ++ unlines rawlines ++ trailing

definitionList = do
  failIfStrict
  items <- many1 definitionListItem
  let (terms, defs) = unzip items
  let defs' = compactify defs
  let items' = zip terms defs'
  return $ DefinitionList items'

--
-- paragraph block
--

para = try (do 
  result <- many1 inline
  newline
  st <- getState
  if stateStrict st
     then choice [lookAhead blockQuote, lookAhead header, 
                  (do{blanklines; return Null})]
     else choice [(do{lookAhead emacsBoxQuote; return Null}), 
                  (do{blanklines; return Null})]
  let result' = normalizeSpaces result
  return (Para result'))

plain = do
  result <- many1 inline
  let result' = normalizeSpaces result
  return (Plain result')

-- 
-- raw html
--

htmlElement = choice [strictHtmlBlock,
                      htmlBlockElement] <?> "html element"

htmlBlock = do
  st <- getState
  if stateStrict st
    then do
           failUnlessBeginningOfLine
           first <- htmlElement
           finalSpace <- many (oneOf spaceChars)
           finalNewlines <- many newline
           return (RawHtml (first ++ finalSpace ++ finalNewlines))
    else rawHtmlBlocks

-- True if tag is self-closing
isSelfClosing tag = 
  isSuffixOf "/>" $ filter (\c -> (not (c `elem` " \n\t"))) tag

strictHtmlBlock = try (do
  tag <- anyHtmlBlockTag 
  let tag' = extractTagType tag
  if isSelfClosing tag || tag' == "hr" 
     then return tag
     else do
            contents <- many (do{notFollowedBy' (htmlEndTag tag'); 
                                 htmlElement <|> (count 1 anyChar)})
            end <- htmlEndTag tag'
            return $ tag ++ (concat contents) ++ end)

rawHtmlBlocks = try (do
  htmlBlocks <- many1 rawHtmlBlock    
  let combined = concatMap (\(RawHtml str) -> str) htmlBlocks
  let combined' = if (last combined == '\n')
                     then init combined  -- strip extra newline 
                     else combined 
  return (RawHtml combined'))

--
-- LaTeX
--

rawLaTeXEnvironment' = do
  failIfStrict
  rawLaTeXEnvironment

--
-- Tables
-- 

-- Parse a dashed line with optional trailing spaces; return its length
-- and the length including trailing space.
dashedLine ch = do
    dashes <- many1 (char ch)
    sp     <- many spaceChar
    return $ (length dashes, length $ dashes ++ sp)

-- Parse a table header with dashed lines of '-' preceded by 
-- one line of text.
simpleTableHeader = do
    rawContent  <- anyLine
    initSp      <- nonindentSpaces
    dashes      <- many1 (dashedLine '-')
    newline
    let (lengths, lines) = unzip dashes
    let indices  = scanl (+) (length initSp) lines
    let rawHeads = tail $ splitByIndices (init indices) rawContent
    let aligns   = zipWith alignType (map (\a -> [a]) rawHeads) lengths
    return $ (rawHeads, aligns, indices)

-- Parse a table footer - dashed lines followed by blank line.
tableFooter = try $ do
    nonindentSpaces
    many1 (dashedLine '-')
    blanklines

-- Parse a table separator - dashed line.
tableSep = try $ do
    nonindentSpaces
    many1 (dashedLine '-')
    string "\n"

-- Parse a raw line and split it into chunks by indices.
rawTableLine indices = do
    notFollowedBy' (blanklines <|> tableFooter)
    line <- many1Till anyChar newline
    return $ map removeLeadingTrailingSpace $ tail $ 
             splitByIndices (init indices) line

-- Parse a table line and return a list of lists of blocks (columns).
tableLine indices = try $ do
    rawline <- rawTableLine indices
    mapM (parseFromStr (many plain)) rawline

-- Parse a multiline table row and return a list of blocks (columns).
multilineRow indices = try $ do
    colLines <- many1 (rawTableLine indices)
    option "" blanklines
    let cols = map unlines $ transpose colLines
    mapM (parseFromStr (many plain)) cols

-- Calculate relative widths of table columns, based on indices
widthsFromIndices :: Int     -- Number of columns on terminal
                  -> [Int]   -- Indices
                  -> [Float] -- Fractional relative sizes of columns
widthsFromIndices _ [] = []  
widthsFromIndices numColumns indices = 
    let lengths = zipWith (-) indices (0:indices)
        totLength = sum lengths
        quotient = if totLength > numColumns
                     then fromIntegral totLength
                     else fromIntegral numColumns
        fracs = map (\l -> (fromIntegral l) / quotient) lengths in
    tail fracs

-- Parses a table caption:  inlines beginning with 'Table:'
-- and followed by blank lines.
tableCaption = try $ do
    nonindentSpaces
    string "Table:"
    result <- many1 inline
    blanklines
    return $ normalizeSpaces result

-- Parse a table using 'headerParser', 'lineParser', and 'footerParser'.
tableWith headerParser lineParser footerParser = try $ do
    (rawHeads, aligns, indices) <- headerParser
    lines <- many1Till (lineParser indices) footerParser
    caption <- option [] tableCaption
    heads <- mapM (parseFromStr (many plain)) rawHeads
    state <- getState
    let numColumns = stateColumns state
    let widths = widthsFromIndices numColumns indices
    return $ Table caption aligns widths heads lines

-- Parse a simple table with '---' header and one line per row.
simpleTable = tableWith simpleTableHeader tableLine blanklines

-- Parse a multiline table:  starts with row of '-' on top, then header
-- (which may be multiline), then the rows,
-- which may be multiline, separated by blank lines, and
-- ending with a footer (dashed line followed by blank line).
multilineTable = tableWith multilineTableHeader multilineRow tableFooter

multilineTableHeader = try $ do
    tableSep 
    rawContent  <- many1 (do{notFollowedBy' tableSep; 
                             many1Till anyChar newline})
    initSp      <- nonindentSpaces
    dashes      <- many1 (dashedLine '-')
    newline
    let (lengths, lines) = unzip dashes
    let indices  = scanl (+) (length initSp) lines
    let rawHeadsList = transpose $ map 
                       (\ln -> tail $ splitByIndices (init indices) ln)
                       rawContent
    let rawHeads = map (joinWithSep " ") rawHeadsList
    let aligns   = zipWith alignType rawHeadsList lengths
    return $ ((map removeLeadingTrailingSpace rawHeads),
             aligns, indices)

-- Returns the longest of a list of strings.
longest :: [String] -> String
longest [] = ""
longest [x] = x
longest (x:xs) =
    if (length x) >= (maximum $ map length xs)
      then x
      else longest xs

-- Returns an alignment type for a table, based on a list of strings
-- (the rows of the column header) and a number (the length of the
-- dashed line under the rows.
alignType :: [String] -> Int -> Alignment
alignType []  len = AlignDefault
alignType strLst len =
    let str        = longest $ map removeTrailingSpace strLst
        leftSpace  = if null str then False else ((str !! 0) `elem` " \t")
        rightSpace = (length str < len || (str !! (len - 1)) `elem` " \t") in
    case (leftSpace, rightSpace) of
        (True,  False)   -> AlignRight
        (False, True)    -> AlignLeft
        (True, True)     -> AlignCenter
        (False, False)   -> AlignDefault

table = do
    failIfStrict
    result <- simpleTable <|> multilineTable <?> "table"
    return result

-- 
-- inline
--

inline = choice [ rawLaTeXInline'
                , escapedChar
                , entity
                , note
                , inlineNote
                , link
                , referenceLink
                , rawHtmlInline'
                , autoLink
                , image
                , escapedChar
                , math
                , strong
                , emph
                , smartPunctuation
                , code
                , ltSign
                , symbol
                , str
                , linebreak
                , tabchar
                , whitespace
                , endline ] <?> "inline"

escapedChar = try $ do
  char '\\'
  state <- getState
  result <- if stateStrict state 
              then oneOf "\\`*_{}[]()>#+-.!"
              else satisfy (not . isAlphaNum)
  return (Str [result])

ltSign = try (do
  notFollowedBy (noneOf "<")   -- continue only if it's a <
  notFollowedBy' rawHtmlBlocks -- don't return < if it starts html
  char '<'
  return (Str ['<']))

specialCharsMinusLt = filter (/= '<') specialChars

symbol = do 
  result <- oneOf specialCharsMinusLt
  return (Str [result])

-- parses inline code, between n codeStarts and n codeEnds
code = try (do 
  starts <- many1 (char codeStart)
  let num = length starts
  result <- many1Till anyChar (try (count num (char codeEnd)))
  -- get rid of any internal newlines
  let result' = removeLeadingTrailingSpace $ joinWithSep " " $ lines result
  return (Code result'))

mathWord = many1 (choice [ (noneOf (" \t\n\\" ++ [mathEnd])), 
                           (try (do
                                   c <- char '\\'
                                   notFollowedBy (char mathEnd)
                                   return c))])

math = try (do
  failIfStrict
  char mathStart
  notFollowedBy space
  words <- sepBy1 mathWord (many1 space)
  char mathEnd
  return (TeX ("$" ++ (joinWithSep " " words) ++ "$")))

emph = do
  result <- choice [ (enclosed (char emphStart) (char emphEnd) inline), 
                     (enclosed (char emphStartAlt) (char emphEndAlt) inline) ]
  return (Emph (normalizeSpaces result))

strong = do
  result <- (enclosed strongStart strongEnd inline) <|> 
            (enclosed strongStartAlt strongEndAlt inline)
  return (Strong (normalizeSpaces result))
  where strongStart = count 2 (char emphStart)
        strongEnd = try strongStart
        strongStartAlt = count 2 (char emphStartAlt)
        strongEndAlt = try strongStartAlt

smartPunctuation = do
  failUnlessSmart
  choice [ quoted, apostrophe, dash, ellipses ]

apostrophe = do
  char '\'' <|> char '\8217'
  return Apostrophe

quoted = do
  doubleQuoted <|> singleQuoted 

withQuoteContext context parser = do
  oldState <- getState
  let oldQuoteContext = stateQuoteContext oldState
  setState oldState { stateQuoteContext = context }
  result <- parser
  newState <- getState
  setState newState { stateQuoteContext = oldQuoteContext }
  return result

singleQuoted = try $ do
  singleQuoteStart
  withQuoteContext InSingleQuote $ do
    result <- many1Till inline singleQuoteEnd
    return $ Quoted SingleQuote $ normalizeSpaces result

doubleQuoted = try $ do 
  doubleQuoteStart
  withQuoteContext InDoubleQuote $ do
    result <- many1Till inline doubleQuoteEnd
    return $ Quoted DoubleQuote $ normalizeSpaces result

failIfInQuoteContext context = do
  st <- getState
  if (stateQuoteContext st == context)
    then fail "already inside quotes"
    else return ()

singleQuoteStart = try $ do 
  failIfInQuoteContext InSingleQuote
  char '\8216' <|> do 
                     char '\''  
                     notFollowedBy (oneOf ")!],.;:-? \t\n")
                     notFollowedBy (try (do  -- possessive or contraction
                                           oneOfStrings ["s","t","m","ve","ll","re"]
                                           satisfy (not . isAlphaNum)))
                     return '\''

singleQuoteEnd = try $ do
  char '\'' <|> char '\8217'
  notFollowedBy alphaNum

doubleQuoteStart = try $ do
  failIfInQuoteContext InDoubleQuote
  char '"' <|> char '\8220'
  notFollowedBy (oneOf " \t\n")

doubleQuoteEnd = char '"' <|> char '\8221'

ellipses = try (do
  oneOfStrings ["...", " . . . ", ". . .", " . . ."]
  return Ellipses)

dash = enDash <|> emDash

enDash = try (do
  char '-'
  notFollowedBy (noneOf "0123456789")
  return EnDash) 

emDash = try (do
  skipSpaces
  oneOfStrings ["---", "--"]
  skipSpaces
  return EmDash)

whitespace = do
  many1 (oneOf spaceChars) <?> "whitespace"
  return Space

tabchar = do
  tab
  return (Str "\t")

-- hard line break
linebreak = try (do
  oneOf spaceChars
  many1 (oneOf spaceChars) 
  endline
  return LineBreak )

nonEndline = noneOf endLineChars

entity = do
  ent <- characterEntity
  return $ Str [ent]

strChar = noneOf (specialChars ++ spaceChars ++ endLineChars)

str = do 
  result <- many1 strChar
  return (Str result)

-- an endline character that can be treated as a space, not a structural break
endline = try (do
  newline
  notFollowedBy blankline
  st <- getState
  if stateStrict st 
    then do
           notFollowedBy' emailBlockQuoteStart
           notFollowedBy (char atxHChar)  -- atx header
           notFollowedBy (try (do{manyTill anyChar newline; 
                                  oneOf setextHChars}))  -- setext header
    else return () 
  -- parse potential list-starts differently if in a list:
  if (stateParserContext st) == ListItemState
     then notFollowedBy' (orderedListStart <|> bulletListStart)
     else return ()
  return Space)

--
-- links
--

rawLabel = try $ do
  char labelStart
  -- allow for embedded brackets:
  raw <- manyTill (do{res <- rawLabel; return ("[" ++ res ++ "]")} <|> 
                   count 1 anyChar) (char labelEnd)
  return $ concat raw 

-- a reference label for a link
reference = try $ do
  raw <- rawLabel
  oldInput <- getInput
  setInput raw
  label <- many inline
  setInput oldInput
  return (normalizeSpaces label)
 
-- source for a link, with optional title
source = try $ do 
  char srcStart
  option ' ' (char autoLinkStart)
  src <- many (noneOf [srcEnd, autoLinkEnd, ' ', '\t', '\n'])
  option ' ' (char autoLinkEnd)
  tit <- option "" title
  skipSpaces
  char srcEnd
  return (removeTrailingSpace src, tit)

titleWith startChar endChar = try (do
  leadingSpace <- many1 (oneOf " \t\n")
  if length (filter (=='\n') leadingSpace) > 1
    then fail "title must be separated by space and on same or next line"
    else return ()
  char startChar
  tit <- manyTill anyChar (try (do
                                  char endChar
                                  skipSpaces
                                  notFollowedBy (noneOf ")\n")))
  return $ decodeEntities tit)

title = choice [ titleWith '(' ')', 
                 titleWith '"' '"', 
                 titleWith '\'' '\''] <?> "title"

link = choice [explicitLink, referenceLink] <?> "link"

explicitLink = try (do
  label <- reference
  src <- source 
  return (Link label src)) 

-- a link like [this][ref] or [this][] or [this]
referenceLink = try $ do
  label <- reference
  ref <- option [] (try (do skipSpaces
                            option ' ' newline
                            skipSpaces
                            reference))
  let ref' = if null ref then label else ref
  state <- getState
  case lookupKeySrc (stateKeys state) ref' of
     Nothing -> fail "no corresponding key" 
     Just target -> return (Link label target)

autoLink = autoLinkEmail <|> autoLinkRegular

-- a link <like@this.com>
autoLinkEmail = try $ do
  char autoLinkStart
  name <- many1Till (noneOf "/:<> \t\n") (char '@')
  domain <- sepBy1 (many1 (noneOf "/:.@<> \t\n")) (char '.')
  let src = name ++ "@" ++ (joinWithSep "." domain)
  char autoLinkEnd
  return $ Link [Str src] (("mailto:" ++ src), "")

-- a link <http://like.this.com>
autoLinkRegular = try $ do
  char autoLinkStart
  prot <- oneOfStrings ["http:", "ftp:", "mailto:"]
  rest <- many1Till (noneOf " \t\n<>") (char autoLinkEnd)
  let src = prot ++ rest
  return $ Link [Str src] (src, "")

image = try (do
  char imageStart
  (Link label src) <- link
  return (Image label src)) 

note = try $ do
  failIfStrict
  ref <- noteMarker
  state <- getState
  let notes = stateNotes state
  case lookup ref notes of
    Nothing -> fail "note not found"
    Just contents -> return (Note contents)

inlineNote = try $ do
  failIfStrict
  char noteStart
  char labelStart
  contents <- manyTill inline (char labelEnd)
  return (Note [Para contents])

rawLaTeXInline' = do
  failIfStrict
  rawLaTeXInline

rawHtmlInline' = do
  st <- getState
  result <- if stateStrict st
              then choice [htmlBlockElement, anyHtmlTag, anyHtmlEndTag] 
              else choice [htmlBlockElement, anyHtmlInlineTag]
  return (HtmlInline result)
