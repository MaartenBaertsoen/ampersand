{-# OPTIONS_GHC -Wall #-}
module Main where

import Control.Monad
import System.Exit
import Prelude hiding (readFile,writeFile)
import Data.List (intersperse)
import Database.Design.Ampersand (getOptions, showErr, showVersion, showHelp, helpNVersionTexts, ampersandVersionStr, createFspec, Guarded(..), generateAmpersandOutput)

main :: IO ()
main =
 do flags <- getOptions
    if showVersion flags || showHelp flags
    then mapM_ putStr (helpNVersionTexts ampersandVersionStr flags)
    else do gFspec <- createFspec flags
            case gFspec of
              Errors err -> do Prelude.putStrLn $ "Error(s) found:"
                               mapM_ putStrLn (intersperse  (replicate 30 '=') (map showErr err))
                               exitWith $ ExitFailure 10
              Checked fspc -> generateAmpersandOutput flags fspc
