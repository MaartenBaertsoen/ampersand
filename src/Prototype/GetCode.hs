module Prototype.GetCode (getCodeFor) where
 import Prototype.CodeStatement (Statement(..),CodeQuery(..),UseVar(..))
 import Prototype.CodeVariables (CodeVar(..))
 import Prototype.CodeAuxiliaries (Named(..),atleastOne,reName,nameFresh)
 import Adl (Concept(..),Expression(..),Morphism(..),mIs,source,target,Identified(..),singleton)
 import Prototype.RelBinGenSQL(selectExpr,sqlExprTrg,sqlExprSrc)
 import Strings(noCollide)
 import Data.Fspec (Fspc)
 import Prototype.CodeVariables (newVarFor,freshSingleton,pairSourceExpr,pairTargetExpr,singletonCV)-- manipulating variables
 
 getCodeFor :: Fspc->[Named CodeVar]->[Named CodeVar]->(Maybe [Statement])
 getCodeFor fSpec pre post
    = if null new then Just [] else
       case next of
        (a:_,Just as) -> Just (a ++ as)
        _ -> Nothing
  where
   new  = [p|p<-post,notElem p pre]
   next = (getCodeForSingle fSpec pre (head new),getCodeFor fSpec ((head new):pre) post)
 
  
 getCodeForSingle :: Fspc->[Named CodeVar]->Named CodeVar->[[Statement]]
 getCodeForSingle _ pre post | elem post pre = [[]] -- allready known info
 getCodeForSingle fSpec pre o
  | singleton (source e) -- als dit niet waar is, kan de variabele niet gevuld worden!!
 -- TODO: make sure that newVarFor variables are read OK
  = atleastOne (" getCodeForSingle did not return anything for an object of expression ("++show e++")["++(show$ source e)++"*"++(show$ target e)++"]")
     -- to get code, we can try different strategies. Just concattenate all attempts
     -- Put the things you want most first (efficient stuff first)
     ([ -- here we try to find a partial overlap in pre:
        -- we already know pre, and it might be just what we're looking for
        -- there is no need to calculate it twice
      ]++ -- if that does not work, find Expression and iterate over it
      -- let's first try to find a singleton, those values we know already
      [ code |
        code<-case e of
         (Tm (V{mphtyp=(_,t)}) _) -- source is al automatisch een singleton
          -> getAllTarget t
         (Tm mph _)
          -> [ [ --(F$ reverse fs)
               -- 
               ]
             | p<-pre
             --, name p == v
             , False
             ]
      ]
     )
  | otherwise = error "getCodeForSingle requires that source(cvExpression o) is a singleton"
  where e = cvExpression obj
        obj = (nObject o)
        getAllTarget (DExp e') -- this makes the object very predicatble: it will have a source (0) and a target (1) relation
         = atleastOne ("getAllTarget did not return something for (DExp e') with e'="++show e')
           [galines ++ renaming
           | tmpvar<-[newVarFor (map nName (o:pre)) e']
           , galines<-getCodeForSingle fSpec pre tmpvar
           , renaming<-[[Iteration (tmpvar:pre) (o:tmpvar:pre) (use tmpvar) s t'
                        [Iteration (o:s:t:tmpvar:pre) (o:s:t:tmpvar:pre) (use t') t'' t
                                   [Assignment (s:t:t':tmpvar:pre)
                                               (s:t:t':o:tmpvar:pre)
                                               (Named (nName o) (UseVar [Right (Named "" (UseVar []))]))
                                               (CQCompose (map (\x->Named (fst x) (CQPlain (snd x))) fromTo))
                                   ]]
                        ]
                       | let c = case obj of
                                   CodeVar{cvContent=Right []} -> [o]
                                   CodeVar{cvContent=Right x} -> (x)
                                   _ -> []
                       , let s = freshSingleton (tmpvar:pre) "source" (source e')
                       , let t' = nameFresh (s:tmpvar:pre) "t" singletonCV
                       , let t = freshSingleton (s:t':tmpvar:pre) "target" (target e')
                       , let t'' = nameFresh (s:t:tmpvar:pre) "i" singletonCV
                       , let fromTo = [ (nName f, to)
                                      | f <- c 
                                      , to <-    [use s|cvExpression (nObject f)==pairSourceExpr e']
                                              ++ [use t|cvExpression (nObject f)==pairTargetExpr e']
                                      ]
                       , (length fromTo == length c) || error ("Length does not match in Code.hs: "++show (fromTo,c))
                       ]
           ]
        getAllTarget tp
         = [[Assignment pre (o:pre) (use o) (SQLComposed (source expr) [Named (name$ source expr) expr] sql)]
           | let expr=Tm (mIs(tp)) (-1)
           , CodeVar{cvContent=Right []} <-[obj]
           , Just sql <- [selectExpr fSpec 0 "" (sqlExprTrg fSpec expr) expr]
           ]++
           [ l
           | CodeVar{cvContent=Left c}<-[obj]
           , l<-getAllInExpr fSpec pre (use o) (cvExpression c)
           ]++
           [ error ("TODO: create complex objects for getAllTarget in Code.hs "++show c)
           | CodeVar{cvContent=Right (c:_)}<-[obj]
           ]
 
 -- | Create code to fill a single variable with some expression
 getAllInExpr :: Fspc            -- ^ contains information on what's in a DB and what's in a different kind of plug
              -> [Named CodeVar] -- ^ preknowledge (for administrative purposes)
              -> Named UseVar    -- ^ variable to assign Expression to (see Assignment for details)
              -> Expression      -- ^ expression we'd like to know
              -> [[Statement]]   -- ^ list of possible chunks of code that get Expression into Named CodeVar, sorted from most efficient to least efficient (fastest way to get Expression)
 getAllInExpr fSpec pre var (Tc   e ) = getAllInExpr fSpec pre var e
 getAllInExpr fSpec pre var (F   [e]) = getAllInExpr fSpec pre var e
 getAllInExpr fSpec pre var (Fix [e]) = getAllInExpr fSpec pre var e
 getAllInExpr fSpec pre var (Fux [e]) = getAllInExpr fSpec pre var e
 getAllInExpr fSpec pre var (Fdx [e]) = getAllInExpr fSpec pre var e
 getAllInExpr fSpec pre var composed
  = -- we try to get the whole thing via SQL
    ( [[Assignment pre (obj:pre) (var) (SQLBinary composed sql)]
      | Just sql<-[sqlQuery fSpec composed]
      ] ++
      -- if we don't succeed, try and get it via PHP
      {- -- does not work
      [[Assignment pre (obj:pre) (var) (php)]
      | Just php<-[phpQuery fSpec composed]
      ] ++
      -}
      -- divide: we try to get both sides of some operator, and then use a binary PHP composition
      [get1++get2++join++forget
      | (e1,e2,opr) <- case composed of (Fix (a:Cpx b:x)) -> [(F (a:x),b,PHPIsectComp)]
                                        (Fix (Cpx b:a:x)) -> [(F (a:x),b,PHPIsectComp)]
                                        (F   (f:fs))      -> [(f,(F   fs),PHPJoin)]
                                        (Fix (f:fs))      -> [(f,(Fix fs),PHPIntersect)]
                                        (Fux (f:fs))      -> [(f,(Fix fs),PHPUnion)]
                                        _ -> [] -- error ("Failed composed namely "++show composed)
      , let var1=newVarFor (map nName (obj:pre)) e1
      , let var2=newVarFor (map nName (obj:var1:pre)) e2
      -- code below is correct, and should work when getCodeForSingle is OK
      , get1<- getCodeForSingle fSpec pre var1
      , get2<- getCodeForSingle fSpec (var1:pre) var2
      --, get1<-getAllInExpr fSpec pre var1 e1
      --, get2<-getAllInExpr fSpec (var1:pre) var2 e2
      , let join=[Assignment (var1:var2:pre) (var1:var2:obj:pre) var (opr (CQPlain$use var1) (CQPlain$use var2))]
      , let forget=[Forget (var1:var2:obj:pre) (obj:pre)]
      ]
    )
  where obj =reName (nName var) (newVarFor (map nName pre) composed)
 -- | use a variable
 use :: Named CodeVar -> Named UseVar
 use s = Named (nName s) (UseVar [])
 {- -- not used in first example, so not built here
 -- | will get a straight-forward php expression (binary)
 phpQuery :: Fspc -> [Named CodeVar] -> Expression -> Maybe (String)
 phpQuery fSpec pre expr
  = listToMaybe
      [  PHPPlug {cqinput=in -- ^ list of arguments passed to the plug
                 ,cqoutput=out
                 ,cqphpplug::plname plug
                 ,cqphpfile::phpfile plug
                 }
      | plug <- takeTypedPlug$ plugs fspec
      , 
        -- check if out is of the right form (binary)
      ]
  -}
 -- | will get a straight-forward sql expression (binary) with a nice name for source and target
 -- | if, of course, such a sql expression exists
 sqlQuery :: Fspc -> Expression -> Maybe String
 sqlQuery fSpec expr
  = selectExpr fSpec 0 src (noCollide [src] (sqlExprTrg fSpec expr)) expr
  where src = sqlExprSrc fSpec expr
