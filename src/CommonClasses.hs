{-# OPTIONS_GHC -Wall #-}
  module CommonClasses
  (  Identified(name) , showSign
   , ABoolAlg(glb,lub,order)
   , SelfExplained(..)
   , Conceptual(conts)
   , Morphics(anything)
   )

  where

   import Collection(rd)
   import Strings(chain)
   import Data.Explain
   ----------------------------------------------
   class Identified a where
    name   :: a->String

   showSign :: Identified a => [a] -> String
   showSign cs = "["++(chain "*".rd.map name) cs++"]"

   instance Identified a => Identified [a] where
    name [] = ""
    name (i:_) = name i

   class (Show a,Ord a) => ABoolAlg a where
    glb,lub :: a -> a -> a
    order :: a -> a -> Bool
    glb a b | b <= a = b
            | a <= b = a
            | otherwise  = error "!Fatal (module CommonClasses 34): glb undefined"
    lub a b | a <= b = b
            | b <= a = a
            | otherwise = error "!Fatal (module CommonClasses 37): lub undefined"
    order a b | a <= b = True
              | b <= a = True
              | otherwise = False

   instance (ABoolAlg a,ABoolAlg b) => ABoolAlg (a,b) where
    glb a b | a <= b = a
            | b <= a = b
            | otherwise = error ("!Fatal (module CommonClasses 45): glb undefined: a="++show a++", b="++show b)
    lub a b | b <= a = a
            | a <= b = b
            | otherwise = error ("!Fatal (module CommonClasses 48): lub undefined: a="++show a++", b="++show b)

   class SelfExplained a where
    --TODO: Samenvoegen met Explained
    autoExplain :: a -> [AutoExplain]  -- List of inner (generated) explanations of the object (like Rule, Morphism, ..)

   class Conceptual a where
    conts :: a -> [String]                   -- the set of all instances in a concept

   instance Conceptual a => Conceptual [a] where
    conts = rd . concat . map conts

   class Morphics a where
    anything       :: a -> Bool

   instance Morphics a => Morphics [a] where
    anything xs = and (map anything xs)
   instance (Morphics a,Morphics b) => Morphics (a,b) where
    anything (x,y) = anything x && anything y






