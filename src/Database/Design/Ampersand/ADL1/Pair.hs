module Database.Design.Ampersand.ADL1.Pair
                    ( Paire,Pairs
                    , srcPaire,trgPaire
                    , mkPair
                    ) where

   import Data.Set (Set)

   type Pairs = Set Paire
   srcPaire :: Paire -> String
   trgPaire :: Paire -> String
   type Paire = (String,String)
   mkPair :: String -> String -> Paire
   mkPair a b = (a,b)
   srcPaire = fst
   trgPaire = snd
--   data Paire = Paire {srcPaire ::String
--                      ,trgPaire ::String
--                      } deriving (Show ,Eq)
--   mkPair = Paire

