{-# LANGUAGE PatternGuards #-}
{-# OPTIONS_GHC -Wall #-}
module DatabaseDesign.Ampersand.Misc.Options 
        (Options(..),getOptions,defaultFlags,usageInfo'
        ,ParserVersion(..)
        ,verboseLn,verbose,FspecFormat(..),FileFormat(..)
        ,DocTheme(..),allFspecFormats,helpNVersionTexts)
where
import System.Environment    (getArgs, getProgName,getEnvironment)
import DatabaseDesign.Ampersand.Misc.Languages (Lang(..))
import Data.Char (toUpper)
import System.Console.GetOpt
import System.FilePath
import System.Directory
import Data.Time.Clock
import Data.Time.LocalTime
import Control.Monad
import Data.Maybe
import DatabaseDesign.Ampersand.Basics  
import Prelude hiding (writeFile,readFile,getContents,putStr,putStrLn)
import Data.List

fatal :: Int -> String -> a
fatal = fatalMsg "Misc.Options"

data ParserVersion = Current | Legacy deriving Eq

instance Show ParserVersion where
  show Current = "syntax since Ampersand 2.1.1."
  show Legacy = "syntax664"

-- | This data constructor is able to hold all kind of information that is useful to 
--   express what the user would like Ampersand to do. 
data Options = Options { showVersion :: Bool
                       , typeGraphs :: Bool   -- draw a diagram of the type analysis, for educational or debugging purposes.
                       , preVersion :: String
                       , postVersion :: String  --built in to aid DOS scripting... 8-(( Bummer. 
                       , showHelp :: Bool
                       , verboseP :: Bool
                       , development :: Bool
                       , validateSQL :: Bool
                       , genPrototype :: Bool 
                       , autoid :: Bool --implies forall Concept A => value::A->Datatype [INJ]. where instances of A are autogenerated 
                       , dirPrototype :: String  -- the directory to generate the prototype in.
                       , allInterfaces :: Bool
                       , dbName :: String
                       , genAtlas :: Bool
                       , namespace :: String
                       , autoRefresh :: Maybe Int
                       , testRule :: Maybe String                       
                       , customCssFile :: Maybe FilePath                       
                       , importfile :: FilePath --a file with content to populate some (Populated a)
                                                   --class Populated a where populate::a->b->a
                       , fileformat :: FileFormat --file format e.g. of importfile or export2adl
                       , theme :: DocTheme --the theme of some generated output. (style, content differentiation etc.)
                       , genXML :: Bool
                       , genFspec :: Bool   -- if True, generate a functional specification
                       , diag :: Bool   -- if True, generate a diagnosis only
                       , fspecFormat :: FspecFormat
                       , genGraphics :: Bool   -- if True, graphics will be generated for use in Ampersand products like the Atlas or Functional Spec
                       , genEcaDoc :: Bool   -- if True, generate ECA rules in the Functional Spec
                       , proofs :: Bool
                       , haskell :: Bool   -- if True, generate the F-structure as a Haskell source file
                       , dirOutput :: String -- the directory to generate the output in.
                       , outputfile :: String -- the file to generate the output in.
                       , crowfoot :: Bool   -- if True, generate conceptual models and data models in crowfoot notation
                       , blackWhite :: Bool   -- only use black/white in graphics
                       , altGraphics :: Bool   -- Graphics are generated without hinge nodes on edges.    
                       , showPredExpr :: Bool   -- for generated output, show predicate logic?
                       , noDiagnosis :: Bool   -- omit the diagnosis chapter from the functional specification document
                       , diagnosisOnly :: Bool   -- give a diagnosis only (by omitting the rest of the functional specification document)
                       , genLegalRefs :: Bool   -- Generate a table of legal references in Natural Language chapter
                       , genUML :: Bool   -- Generate a UML 2.0 data model
                       , genFPAExcel :: Bool   -- Generate an Excel workbook containing Function Point Analisys
                       , genBericht :: Bool
                       , genMeat :: Bool  -- Generate the meta-population and output it to an .adl file
                       , language :: Lang
                       , dirExec :: String --the base for relative paths to input files
                       , progrName :: String --The name of the adl executable
                       , fileName :: FilePath --the file with the Ampersand context
                       , baseName :: String
                       , logName :: String
                       , genTime :: LocalTime
                       , export2adl :: Bool
                       , test :: Bool
                       , includeRap :: Bool  -- When set, the standard RAP is 'merged' into the generated prototype.(experimental)
                       , pangoFont :: String  -- use specified font in PanDoc. May be used to avoid pango-warnings.
                       , sqlHost :: Maybe String  -- do database queries to the specified host
                       , sqlLogin :: Maybe String  -- pass login name to the database server
                       , sqlPwd :: Maybe String  -- pass password on to the database server
                       , parserVersion :: ParserVersion
                       } deriving Show
  
defaultFlags :: Options 
defaultFlags = Options {genTime       = fatal 81 "No monadic options available."
                      , dirOutput     = fatal 82 "No monadic options available."
                      , outputfile    = fatal 83 "No monadic options available."
                      , autoid        = False
                      , dirPrototype  = fatal 84 "No monadic options available."
                      , dbName        = fatal 85 "No monadic options available."
                      , logName       = fatal 86 "No monadic options available."
                      , dirExec       = fatal 87 "No monadic options available."
                      , preVersion    = fatal 88 "No monadic options available."
                      , postVersion   = fatal 89 "No monadic options available."
                      , theme         = DefaultTheme
                      , showVersion   = False
                      , typeGraphs    = False
                      , showHelp      = False
                      , verboseP      = False
                      , development   = False
                      , validateSQL   = False
                      , genPrototype  = False
                      , allInterfaces = False
                      , genAtlas      = False   
                      , namespace     = []
                      , autoRefresh   = Nothing
                      , testRule      = Nothing
                      , customCssFile = Nothing
                      , importfile    = []
                      , fileformat    = fatal 101 "--fileformat is required for --import."
                      , genXML        = False
                      , genFspec      = False 
                      , diag          = False 
                      , fspecFormat   = fatal 105 $ "Unknown fspec format. Currently supported formats are "++allFspecFormats++"."
                      , genGraphics   = True
                      , genEcaDoc     = False
                      , proofs        = False
                      , haskell       = False
                      , crowfoot      = False
                      , blackWhite    = False
                      , altGraphics   = False
                      , showPredExpr  = False
                      , noDiagnosis   = False
                      , diagnosisOnly = False
                      , genLegalRefs  = False
                      , genUML        = False
                      , genFPAExcel   = False
                      , genBericht    = False
                      , genMeat       = False
                      , language      = Dutch
                      , progrName     = fatal 118 "No monadic options available."
                      , fileName      = fatal 119 "no default value for fileName."
                      , baseName      = fatal 120 "no default value for baseName."
                      , export2adl    = False
                      , test          = False
                      , includeRap    = False
                      , pangoFont     = "Sans"
                      , sqlHost       = Nothing
                      , sqlLogin      = Nothing
                      , sqlPwd        = Nothing
                      , parserVersion = Current
                      }
                
getOptions :: IO Options
getOptions =
   do args     <- getArgs
      progName <- getProgName
      let usage = "\nType '"++ progName++" --help' for usage info."
      let (o,n,errs) = getOpt Permute (each options) args
      when ((not.null) errs) (error $ concat errs ++ usage)
      defaultOpts <- defaultOptionsM (head (n++(error $ "Please supply the name of an ampersand file" ++ usage)))
      let flags = foldl (flip id) defaultOpts o
      if showHelp flags || showVersion flags
      then return flags
      else checkNSetOptionsAndFileNameM (flags,n) usage
        
  where 
     defaultOptionsM :: String -> IO Options 
     defaultOptionsM fName =
           do utcTime <- getCurrentTime
              timeZone <- getCurrentTimeZone
              let localTime = utcToLocalTime timeZone utcTime
              progName <- getProgName
              exePath <- findExecutable progName
              env <- getEnvironment
              return
               defaultFlags
                      { genTime       = localTime
                      , dirOutput     = fromMaybe "."       (lookup envdirOutput    env)
                      , dirPrototype  = fromMaybe "."       (lookup envdirPrototype env) </> (replaceExtension fName ".proto")
                      , dbName        = fromMaybe ""        (lookup envdbName       env)
                      , logName       = fromMaybe "Ampersand.log" (lookup envlogName      env)
                      , dirExec       = case exePath of
                                          Nothing -> fatal 155 $ "Specify the path location of "++progName++" in your system PATH variable."
                                          Just s  -> takeDirectory s
                      , preVersion    = fromMaybe ""        (lookup "CCPreVersion"  env)
                      , postVersion   = fromMaybe ""        (lookup "CCPostVersion" env)
                      , progrName     = progName
                      }



     checkNSetOptionsAndFileNameM :: (Options,[String]) -> String -> IO Options 
     checkNSetOptionsAndFileNameM (flags,fNames) usage= 
          if showVersion flags || showHelp flags 
          then return flags 
          else case fNames of
                []      -> error $ "no file to parse" ++usage
                [fName] -> verboseLn flags "Checking output directories..."
                        >> checkLogName flags
                        >> checkDirOutput flags
                        --REMARK -> checkExecOpts in comments because it is redundant
                        --          it may throw fatals about PATH not set even when you do not need the dir of the executable.
                        --          if you need the dir of the exec, then you should use (dirExec flags) which will throw the fatal about PATH when needed.
                        -- >> checkExecOpts flags
                        >> checkProtoOpts flags
                        >> return flags { fileName    = if hasExtension fName
                                                         then fName
                                                         else addExtension fName "adl" 
                                        , baseName    = takeBaseName fName
                                        , dbName      = case dbName flags of
                                                            ""  -> takeBaseName fName
                                                            str -> str
                                        , genAtlas = not (null(importfile flags)) && fileformat flags==Adl1Format
                                        , importfile  = if null(importfile flags) || hasExtension(importfile flags)
                                                        then importfile flags
                                                        else case fileformat flags of 
                                                                Adl1Format -> addExtension (importfile flags) "adl"
                                                                Adl1PopFormat -> addExtension (importfile flags) "pop"
                                        }
                x:xs    -> error $ "too many files: "++ intercalate ", " (x:xs) ++usage
       
       where
          checkLogName :: Options -> IO ()
          checkLogName   f = createDirectoryIfMissing True (takeDirectory (logName f))
          checkDirOutput :: Options -> IO ()
          checkDirOutput f = createDirectoryIfMissing True (dirOutput f)

          --checkExecOpts :: Options -> IO ()
          --checkExecOpts f = do execPath <- findExecutable (progrName f) 
            --                   when (execPath == Nothing) 
              --                      (fatal 206 $ "Specify the path location of "++(progrName f)++" in your system PATH variable.")
          checkProtoOpts :: Options -> IO ()
          checkProtoOpts f = when (genPrototype f) (createDirectoryIfMissing True (dirPrototype f))
            
data DisplayMode = Public | Hidden 

data FspecFormat = FPandoc| Fasciidoc| Fcontext| Fdocbook| Fhtml| FLatex| Fman| Fmarkdown| Fmediawiki| Fopendocument| Forg| Fplain| Frst| Frtf| Ftexinfo| Ftextile deriving (Show, Eq)
allFspecFormats :: String
allFspecFormats = show (map (tail . show) [FPandoc, Fasciidoc, Fcontext, Fdocbook, Fhtml, FLatex, Fman, Fmarkdown, Fmediawiki, Fopendocument, Forg, Fplain, Frst, Frtf, Ftexinfo, Ftextile])

data FileFormat = Adl1Format | Adl1PopFormat  deriving (Show, Eq) --file format that can be parsed to some b to populate some Populated a
data DocTheme = DefaultTheme   -- Just the functional specification
              | ProofTheme     -- A document with type inference proofs
              | StudentTheme   -- Output for normal students of the business rules course
              | StudentDesignerTheme   -- Output for advanced students of the business rules course
              | DesignerTheme   -- Output for non-students
                 deriving (Show, Eq)
    
usageInfo' :: Options -> String
-- When the user asks --help, then the public options are listed. However, if also --verbose is requested, the hidden ones are listed too.  
usageInfo' flags = usageInfo (infoHeader (progrName flags)) (if verboseP flags then each options else publics options)
          
infoHeader :: String -> String
infoHeader progName = "\nUsage info:\n " ++ progName ++ " options file ...\n\nList of options:"

publics :: [(a, DisplayMode) ] -> [a]
publics flags = [o | (o,Public)<-flags]
each :: [(a, DisplayMode) ] -> [a]
each flags = [o |(o,_) <- flags]

options :: [(OptDescr (Options -> Options), DisplayMode) ]
options = map pp
          [ (Option "v"     ["version"]     (NoArg versionOpt)          "show version and exit.", Public)
          , (Option ""      ["typing"]      (NoArg typeGraphsOpt)       "show the analysis of types in graphical (.png) form.", Hidden)
          , (Option "h?"    ["help"]        (NoArg helpOpt)             "get (this) usage information.", Public)
          , (Option ""      ["verbose"]     (NoArg verboseOpt)          "verbose error message format.", Public)
          , (Option ""      ["dev"]         (NoArg developmentOpt)      "Report and generate extra development information", Hidden)
          , (Option ""      ["validate"]    (NoArg (\flags -> flags{validateSQL = True}))  "Compare results of rule evaluation in Haskell and SQL (requires command line php with MySQL support)", Hidden)
          , (Option "p"     ["proto"]       (OptArg prototypeOpt "dir") ("generate a functional prototype (overwrites environment variable "
                                                                           ++ envdirPrototype ++ ")."), Public)
          , (Option "d"     ["dbName"]      (ReqArg dbNameOpt "name")   ("database name (overwrites environment variable "
                                                                           ++ envdbName ++ ", defaults to filename)"), Public)
          , (Option []      ["theme"]       (ReqArg themeOpt "theme")   "differentiate between certain outputs e.g. student", Public)
          , (Option "x"     ["interfaces"]  (NoArg maxInterfacesOpt)    "generate interfaces.", Public)
          , (Option "e"     ["export"]      (OptArg exportOpt "file") "export as ASCII Ampersand syntax.", Public)
          , (Option "o"     ["outputDir"]   (ReqArg outputDirOpt "dir") ("output directory (dir overwrites environment variable "
                                                                           ++ envdirOutput ++ ")."), Public)
          , (Option []      ["log"]         (ReqArg logOpt "name")      ("log file name (name overwrites environment variable "
                                                                           ++ envlogName  ++ ")."), Hidden)
          , (Option []      ["import"]      (ReqArg importOpt "file")   "import this file as the population of the context.", Public)
          , (Option []      ["fileformat"]  (ReqArg formatOpt "format")("format of import file (format="
                                                                           ++allFileFormats++")."), Public)
          , (Option []      ["namespace"]   (ReqArg namespaceOpt "ns")  "places the population in this namespace within the context.", Public)
          , (Option "f"     ["fspec"]       (ReqArg fspecRenderOpt "format")  
                                                                         ("generate a functional specification document in specified format (format="
                                                                         ++allFspecFormats++")."), Public)
          , (Option []        ["refresh"]     (OptArg autoRefreshOpt "interval") "Experimental auto-refresh feature", Hidden)
          , (Option []        ["testRule"]    (ReqArg (\ruleName flags -> flags{ testRule = Just ruleName }) "rule name")
                                                                          "Show contents and violations of specified rule.", Hidden)
          , (Option []        ["css"]         (ReqArg (\pth flags -> flags{ customCssFile = Just pth }) "file")
                                                                          "Custom.css file to customize the style of the prototype.", Public)
          , (Option []        ["noGraphics"]  (NoArg noGraphicsOpt)       "save compilation time by not generating any graphics.", Public)
          , (Option []        ["ECA"]         (NoArg genEcaDocOpt)        "generate documentation with ECA rules.", Public)
          , (Option []        ["proofs"]      (NoArg proofsOpt)           "generate derivations.", Public)
          , (Option []        ["XML"]         (NoArg xmlOpt)              "generate internal data structure, written in XML (for debugging).", Public)
          , (Option []        ["haskell"]     (NoArg haskellOpt)          "generate internal data structure, written in Haskell (for debugging).", Public)
          , (Option []        ["crowfoot"]    (NoArg crowfootOpt)         "generate crowfoot notation in graphics.", Public)
          , (Option []        ["blackWhite"]  (NoArg blackWhiteOpt)       "do not use colours in generated graphics", Public)
          , (Option []        ["altGraphics"] (NoArg altGraphicsOpt)      "generate graphics in an alternate way. (you may experiment with this option to see the differences for yourself)", Public)
          , (Option []        ["predLogic"]   (NoArg predLogicOpt)        "show logical expressions in the form of predicate logic." , Public)
          , (Option []        ["noDiagnosis"] (NoArg noDiagnosisOpt)      "omit the diagnosis chapter from the functional specification document." , Public)
          , (Option []        ["diagnosis"]   (NoArg diagnosisOpt)        "diagnose your Ampersand script (generates a .pdf file).", Public)
          , (Option []        ["legalrefs"]   (NoArg (\flags -> flags{genLegalRefs = True}))
                                                                          "generate a table of legal references in Natural Language chapter.", Public)
          , (Option []        ["uml"]         (NoArg (\flags -> flags{genUML = True}))
                                                                          "Generate a UML 2.0 data model.", Hidden)
          , (Option []        ["FPA"]         (NoArg (\flags -> flags{genFPAExcel = True}))
                                                                          "Generate a Excel workbook (.xls).", Hidden)
          , (Option []        ["bericht"]     (NoArg (\flags -> flags{genBericht = True}))
                                                                          "Generate definitions for 'berichten' (specific to INDOORS project).", Hidden)
          , (Option []        ["language"]    (ReqArg languageOpt "lang") "language to be used, ('NL' or 'EN').", Public)
          , (Option []        ["test"]        (NoArg testOpt)             "Used for test purposes only.", Hidden)
          , (Option []        ["rap"]         (NoArg (\flags -> flags{includeRap = True}))
                                                                          "Include RAP into the generated artifacts (experimental)", Hidden)
          , (Option []        ["meta"]        (NoArg (\flags -> flags{genMeat = True}))
                                                                          "Generate meta-population in an .adl file (experimental)", Hidden)
          , (Option []        ["pango"]       (OptArg pangoOpt "fontname") "specify font name for Pango in graphics.", Hidden)
          , (Option []        ["sqlHost"]     (OptArg sqlHostOpt "name")  "specify database host name.", Hidden)
          , (Option []        ["sqlLogin"]    (OptArg sqlLoginOpt "name") "specify database login name.", Hidden)
          , (Option []        ["sqlPwd"]      (OptArg sqlPwdOpt "str")    "specify database password.", Hidden)
          , (Option []        ["forceSyntax"] (ReqArg forceSyntaxOpt "versionNumber") "version number of the syntax to be used, ('1' or '2'). Without this, ampersand will guess the version used.", Public) 
          ]
     where pp :: (OptDescr (Options -> Options), DisplayMode) -> (OptDescr (Options -> Options), DisplayMode)
           pp (Option a b' c d,e) = (Option a b' c d',e)
              where d' =  afkappen [] [] (words d) 40
                    afkappen :: [[String]] -> [String] -> [String] -> Int -> String
                    afkappen regels []    []   _ = intercalate "\n" (map unwords regels)
                    afkappen regels totnu []   b = afkappen (regels++[totnu]) [] [] b
                    afkappen regels totnu (w:ws) b 
                          | length (unwords totnu) < b - length w = afkappen regels (totnu++[w]) ws b
                          | otherwise                             = afkappen (regels++[totnu]) [w] ws b     
           
                    
envdirPrototype :: String
envdirPrototype = "CCdirPrototype"
envdirOutput :: String
envdirOutput="CCdirOutput"
envdbName :: String
envdbName="CCdbName"
envlogName :: String
envlogName="CClogName"

versionOpt :: Options -> Options
versionOpt       flags = flags{showVersion  = True}            
typeGraphsOpt :: Options -> Options
typeGraphsOpt    flags = flags{typeGraphs  = True}            
helpOpt :: Options -> Options
helpOpt          flags = flags{showHelp     = True}            
verboseOpt :: Options -> Options
verboseOpt       flags = flags{ verboseP     = True} 
developmentOpt :: Options -> Options
developmentOpt flags = flags{ development   = True}
autoRefreshOpt :: Maybe String -> Options -> Options
autoRefreshOpt (Just interval) flags | [(i,"")] <- reads interval = flags{autoRefresh = Just i}
autoRefreshOpt _               flags                              = flags{autoRefresh = Just 5}
prototypeOpt :: Maybe String -> Options -> Options
prototypeOpt nm flags 
  = flags { dirPrototype = fromMaybe (dirPrototype flags) nm
         , genPrototype = True}
importOpt :: String -> Options -> Options
importOpt nm flags 
  = flags { importfile = nm }
formatOpt :: String -> Options -> Options
formatOpt f flags = case map toUpper f of
     "ADL" -> flags{fileformat = Adl1Format}
     "ADL1"-> flags{fileformat = Adl1Format}
     "POP" -> flags{fileformat = Adl1PopFormat}
     "POP1"-> flags{fileformat = Adl1PopFormat}
     _     -> flags
maxInterfacesOpt :: Options -> Options
maxInterfacesOpt  flags = flags{allInterfaces  = True}                            
themeOpt :: String -> Options -> Options
themeOpt t flags = flags{theme = case map toUpper t of 
                                    "STUDENT" -> StudentTheme
                                    "STUDENTDESIGNER" -> StudentDesignerTheme
                                    "DESIGNER" -> DesignerTheme
                                    "PROOF"   -> ProofTheme
                                    _         -> DefaultTheme}
dbNameOpt :: String -> Options -> Options
dbNameOpt nm flags = flags{dbName = if nm == "" 
                                    then baseName flags
                                    else nm
                        }                          
namespaceOpt :: String -> Options -> Options
namespaceOpt x flags = flags{namespace = x}
xmlOpt :: Options -> Options
xmlOpt          flags = flags{genXML       = True}
fspecRenderOpt :: String -> Options -> Options
fspecRenderOpt w flags = flags{ genFspec=True
                            , fspecFormat= case map toUpper w of
                                  ('A': _ )         -> Fasciidoc
                                  ('C': _ )         -> Fcontext
                                  ('D': _ )         -> Fdocbook
                                  ('H': _ )         -> Fhtml
                                  ('L': _ )         -> FLatex
                                  ('M':'A':'N': _ ) -> Fman
                                  ('M':'A': _ )     -> Fmarkdown
                                  ('M':'E': _ )     -> Fmediawiki
                                  ('O':'P': _ )     -> Fopendocument
                                  ('O':'R': _ )     -> Forg
                                  ('P':'A': _ )     -> FPandoc
                                  ('P':'L': _ )     -> Fplain
                                  ('R':'S': _ )     -> Frst
                                  ('R':'T': _ )     -> Frtf
                                  ('T':'E':'X':'I': _ ) -> Ftexinfo
                                  ('T':'E':'X':'T': _ ) -> Ftextile
                                  _         -> fspecFormat flags

                                                
                            }
allFileFormats :: String
allFileFormats                    = "ADL (.adl), ADL1 (.adl), POP (.pop), POP1 (.pop)"
noGraphicsOpt :: Options -> Options
noGraphicsOpt flags                  = flags{genGraphics   = False}
genEcaDocOpt :: Options -> Options
genEcaDocOpt flags                   = flags{genEcaDoc     = True}
proofsOpt :: Options -> Options
proofsOpt flags                      = flags{proofs        = True}
exportOpt :: Maybe String -> Options -> Options
exportOpt mbnm flags                 = flags{export2adl    = True
                                          ,outputfile    = fromMaybe "Export.adl" mbnm}
haskellOpt :: Options -> Options
haskellOpt flags                     = flags{haskell       = True}
outputDirOpt :: String -> Options -> Options
outputDirOpt nm flags                = flags{dirOutput     = nm}
crowfootOpt :: Options -> Options
crowfootOpt flags                    = flags{crowfoot      = True}
blackWhiteOpt :: Options -> Options
blackWhiteOpt flags                  = flags{blackWhite    = True}
altGraphicsOpt :: Options -> Options
altGraphicsOpt flags                 = flags{altGraphics   = not (altGraphics flags)}
predLogicOpt :: Options -> Options
predLogicOpt flags                   = flags{showPredExpr  = True}
noDiagnosisOpt :: Options -> Options
noDiagnosisOpt flags                 = flags{noDiagnosis   = True}
diagnosisOpt :: Options -> Options
diagnosisOpt flags                   = flags{diagnosisOnly = True}
languageOpt :: String -> Options -> Options
languageOpt l flags                  = flags{language = case map toUpper l of
                                                       "NL"  -> Dutch
                                                       "UK"  -> English
                                                       "US"  -> English
                                                       "EN"  -> English
                                                       _     -> Dutch}
forceSyntaxOpt :: String -> Options -> Options
forceSyntaxOpt s flags               = flags{parserVersion = case s of
                                              "1" -> Legacy
                                              "2" -> Current
                                              "0" -> Current --indicates latest
                                              _   -> error $ "Unknown value for syntax version: "++s++". Known values are 0, 1 or 2. 0 indicates latest."
                                          } 
logOpt :: String -> Options -> Options
logOpt nm flags                      = flags{logName       = nm}
pangoOpt :: Maybe String -> Options -> Options
pangoOpt (Just nm) flags             = flags{pangoFont     = nm}
pangoOpt Nothing  flags              = flags
sqlHostOpt :: Maybe String -> Options -> Options
sqlHostOpt mnm flags           = flags{sqlHost       = mnm}
sqlLoginOpt :: Maybe String -> Options -> Options
sqlLoginOpt mnm flags          = flags{sqlLogin      = mnm}
sqlPwdOpt :: Maybe String -> Options -> Options
sqlPwdOpt mnm flags            = flags{sqlPwd        = mnm}
testOpt :: Options -> Options
testOpt flags                        = flags{test          = True}

verbose :: Options -> String -> IO ()
verbose flags x
   | verboseP flags = putStr x
   | otherwise      = return ()
   
verboseLn :: Options -> String -> IO ()
verboseLn flags x
   | verboseP flags = -- each line is handled separately, so the buffer will be flushed in time. (see ticket #179)
                      mapM_ putStrLn (lines x)
   | otherwise      = return ()
helpNVersionTexts :: String -> Options -> [String]
helpNVersionTexts vs flags          = [preVersion flags++vs++postVersion flags++"\n" | showVersion flags]++
                                      [usageInfo' flags                              | showHelp    flags]
