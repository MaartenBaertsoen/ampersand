module Database.Design.Ampersand.Classes.ViewPoint (Language(..)) where
import Database.Design.Ampersand.Core.ParseTree
import Database.Design.Ampersand.Core.AbstractSyntaxTree
import Prelude hiding (Ord(..))
import Database.Design.Ampersand.ADL1.Rule
import Database.Design.Ampersand.Classes.Relational  (Relational(multiplicities))
import Database.Design.Ampersand.Basics
import Database.Design.Ampersand.Misc.Explain
import Data.Maybe

fatal :: Int -> String -> a
fatal = fatalMsg "Classes.ViewPoint"

-- Language exists because there are many data structures that behave like an ontology, such as Pattern, P_Context, and Rule.
-- These data structures are accessed by means of a common set of functions (e.g. rules, relations, etc.)

class Language a where
  relsDefdIn :: a -> [Declaration]   -- ^ all relations that are declared in the scope of this viewpoint.
                                     --   These are user defined relations and all generated relarations,
                                     --   i.e. one relation for each GEN and one for each signal rule.
                                     --   Don't confuse relsDefdIn with relsUsedIn, which gives the relations that are
                                     --   used in a.)
  udefrules :: a -> [Rule]           -- ^ all user defined rules that are maintained within this viewpoint,
                                     --   which are not multiplicity- and not identity rules.
  multrules :: a -> [Rule]           -- ^ all multiplicityrules that are maintained within this viewpoint.
  multrules x   = catMaybes [rulefromProp p d |d<-relsDefdIn x, p<-multiplicities d]
  identityRules :: a -> [Rule]       -- all identity rules that are maintained within this viewpoint.
  identityRules x    = concatMap rulesFromIdentity (identities x)
  allRules :: a -> [Rule]
  allRules x = udefrules x ++ multrules x ++ identityRules x
  identities :: a -> [IdentityDef]   -- ^ all keys that are defined in a
  viewDefs :: a -> [ViewDef]         -- ^ all views that are defined in a
  gens :: a -> [A_Gen]               -- ^ all generalizations that are valid within this viewpoint
  patterns :: a -> [Pattern]         -- ^ all patterns that are used in this viewpoint

 
rulesFromIdentity :: IdentityDef -> [Rule]
rulesFromIdentity identity
 = [ if null (identityAts identity) then fatal 81 ("Moving into foldr1 with empty list (identityAts identity).") else
     mkKeyRule
      ( foldr1 (./\.) [  expr .:. flp expr | IdentityExp att <- identityAts identity, let expr=objctx att ]
        .|-. EDcI (idCpt identity)) ]
 {-    diamond e1 e2 = (flp e1 .\. e2) ./\. (e1 ./. flp e2)  -}
 where ruleName = "identity_" ++ name identity
       meaningEN = "Identity rule" ++ ", following from identity "++name identity
       meaningNL = "Identiteitsregel" ++ ", volgend uit identiteit "++name identity
       mkKeyRule expression =
         Ru { rrnm   = ruleName
            , rrexp  = expression
            , rrfps  = origin identity     -- position in source file
            , rrmean = AMeaning
                         [ A_Markup English ReST (string2Blocks ReST meaningEN)
                         , A_Markup Dutch ReST (string2Blocks ReST meaningNL)
                         ]
            , rrmsg  = []
            , rrviol = Nothing
            , rrtyp  = sign expression
            , rrdcl  = Nothing        -- This rule was not generated from a property of some declaration.
            , r_env  = ""             -- For traceability: The name of the pattern. Unknown at this position but it may be changed by the environment.
            , r_usr  = Identity            -- This rule was not specified as a rule in the Ampersand script, but has been generated by a computer
            , isSignal  = False          -- This is not a signal rule
            }

instance Language a => Language [a] where
  relsDefdIn  = concatMap relsDefdIn
  udefrules   = concatMap udefrules
  identities  = concatMap identities
  viewDefs    = concatMap viewDefs
  gens        = concatMap gens
  patterns    = concatMap patterns

instance Language A_Context where
  relsDefdIn context = uniteRels (concatMap relsDefdIn (patterns context)
                                ++ ctxds context)
     where
      -- relations with the same name, but different properties (decprps,pragma,decpopu,etc.) may exist and need to be united
      -- decpopu, decprps and decprps_calc are united, all others are taken from the head.
      uniteRels :: [Declaration] -> [Declaration]
      uniteRels [] = []
      uniteRels ds = [ d | cl<-eqClass (==) ds
                         , let d=(head cl){ decprps      = (foldr1 uni.map decprps) cl
                                          , decprps_calc = Nothing -- Calculation is only done in ADL2Fspc. -- was:(foldr1 uni.map decprps_calc) cl
                                          }]
  udefrules    context = concatMap udefrules  (ctxpats context) ++ ctxrs context
  identities   context = concatMap identities (ctxpats context) ++ ctxks context
  viewDefs     context = concatMap viewDefs   (ctxpats context) ++ ctxvs context
  gens         context = concatMap gens       (ctxpats context) ++ ctxgs context
  patterns             = ctxpats

instance Language Pattern where
  relsDefdIn pat = ptdcs pat
  udefrules      = ptrls   -- all user defined rules in this pattern
--  invariants pat = [r |r<-ptrls pat, not (isSignal r)]
  identities     = ptids
  viewDefs       = ptvds
  gens           = ptgns
  patterns   pat = [pat]

