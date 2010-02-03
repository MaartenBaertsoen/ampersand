  {-# OPTIONS_GHC -Wall #-}
  module ADL2Fspec (makeFspec,actSem, delta, allClauses, conjuncts)
  where
   import Collection     (Collection(rd,rd',uni,isc,(>-)))
   import Strings        (firstCaps)
   import CommonClasses  (ABoolAlg(..))
   import Adl
   import Auxiliaries    (naming, eqCl, eqClass, sort')
   import Data.Fspec
   import Options        (Options)
   import NormalForms(conjNF,disjNF,normPA,simplify)
   import Data.Plug
   import Char
   import ShowADL
   import FPA
   
   makeFspec :: Options -> Context -> Fspc
   makeFspec _ context = fSpec where
        allQuads = quads (\_->True) (rules context)
        fSpec =
            Fspc { fsName       = firstCaps (name context)
                   -- serviceS contains the services defined in the ADL-script.
                   -- services are meant to create user interfaces, programming interfaces and messaging interfaces.
                   -- A generic user interface (the Lonneker interface) is already available.
                 , vplugs       = definedplugs
                 , plugs        = allplugs
                 , serviceS     = attributes context -- services specified in the ADL script
                 , serviceG     = [ o| o<-serviceGen, not (objctx o `elem` map objctx (serviceS fSpec))]   -- generated services
                 , services     = [ makeFservice context allQuads a | a <-serviceS fSpec++serviceG fSpec]
                 , vrules       = rules context++signals context
                 , vconjs       = rd [conj| Quad _ ccrs<-allQuads, (conj,_)<-cl_conjNF ccrs]
                 , vquads       = allQuads
--                 , ecaRules     = []
                 , vrels        = allDecs
                 , fsisa        = ctxisa context
                 , vpatterns    = patterns context
                 , vgens        = gens context
                 , vkeys        = keyDefs context
                 , pictPatts    = Nothing
                 , vConceptDefs = conceptDefs context
                 , themes       = themes'
                 , vctxenv      = ctxenv context
                 }
        testgmi = error$show$ concs context -- ([(name r,concs r)|r<-rules context++signals context]
                 -- ,[(decexpl(d),d)|d<-(declarations (ctxpats context)`uni` ctxds context)])
                 -- ,[(decexpl(d),d,concs d)|d<-declarations context])
   
        allDecs = [ d{decprps = decprps d `uni` [Tot|m<-totals, d==makeDeclaration m, inline m]
                                          `uni` [Sur|m<-totals, d==makeDeclaration m, not (inline m)]}
                  | d<-declarations context, deciss d || decusr d
                  ]
        definedplugs = vsqlplugs ++ vphpplugs
-- maybe useful later...
--        conc2plug :: Concept -> Plug
--        conc2plug c = PlugSql {plname=name c, fields = [field (name c) (Tm (mIs c)) Nothing False True], plfpa = ILGV Eenvoudig}

-- mor2plug creates associations between plugs that represent wide tables.
-- this concerns relations that are not univalent nor injective,
-- Univalent and injective relations cannot be associations, as they are used as attributes in wide tables.
        mor2plug :: Morphism -> Plug
        mor2plug  m'
         = if Inj `elem` mults || Uni `elem` mults then error ("!Fatal (module ADL2Fspec 64): unexpected call of mor2plug("++show m'++"), because it is injective or univalent.") else
           if is_Tot
           then PlugSql { plname = name m'
                        , fields = [field (name (source m')) (Tm (mIs (source m'))(-1)) Nothing (not is_Sur) False {- isUni -}
                                   ,field (name (target m')) (Tm m' (-1)) Nothing (not is_Tot) False {- isInj -}]
                        , plfpa  = NO
                        }
           else if is_Sur then mor2plug (flp m')
           else PlugSql { plname = name m'
                        , fields = [field (name (source m')) (Fi [Tm (mIs (source m'))(-1),F [Tm m'(-1),flp (Tm m'(-1))]]   -- WAAROM (SJ) is dit de expressie in dit veld?
                                                           )      Nothing (not is_Sur) False {- isUni -}
                                   ,field (name (target m')) (Tm m'(-1)) Nothing (not is_Tot) False {- isInj -}]
                        , plfpa  = NO
                        }
           where
             mults = multiplicities m'
             is_Tot = Tot `elem` mults || m' `elem` totals
             is_Sur = Sur `elem` mults || flp m' `elem` totals
        totals :: Morphisms
        totals
         = rd [ m | q<-quads visible (rules fSpec), isIdent (qMorph q)
                  , (_,hcs)<-cl_conjNF (qClauses q), Fu fus<-hcs
                  , antc<-[(conjNF.Fi) [notCp f| f<-fus, isNeg f]], isIdent antc
                  , f<-fus, isPos f
                  , m<-tots f
                  ]
           where tots (F fs) = [m| Tm m _<-take 1 fs]++[flp m| Tm m _<-take 1 (reverse fs)]
                 tots _ = []
                 visible _ = True -- for computing totality, we take all quads into account.

        allplugs = uniqueNames []
                    (definedplugs ++      -- all plugs defined by the user
                     gPlugs       ++      -- all plugs generated by the compiler
                     relPlugs             -- all plugs for relations not touched by definedplugs and gplugs
                    )
          where
           gPlugs   = makePlugs context allDecs definedplugs
           relPlugs = [ mor2plug (makeMph d)
                      | d<-allDecs
                      , not (Inj `elem` multiplicities d)
                      , not (Uni `elem` multiplicities d)]

        uniqueNames :: [String]->[Plug]->[Plug]
        -- Some target systems may be case insensitive! For example MySQL.
        -- So, unique names are made in a case insensitive manner.
        uniqueNames given plgs = naming (\x y->x{plname=y}) -- renaming function for plugs
                                        (map ((.) lowerCase) -- functions that name a plug (lowercase!)
                                             (name:n1:n2:[(\x->lowerCase(name x ++ show n))
                                                         |n<-[(1::Integer)..]])
                                        )
                                        (map lowerCase given) -- the plug-names taken
                                        (map uniqueFields plgs)
          where n1 p = name p ++ plsource p
                n2 p = name p ++ pltarget p
                plsource p = name (source (fldexpr (head (fields (p)))))
                pltarget p = name (target (fldexpr (last (fields (p)))))
                uniqueFields plug = plug{fields = naming (\x y->x{fldname=y}) -- renaming function for fields
                                                  (map ((.) lowerCase) -- lowercase-yielding
                                                       (fldname:[(\x->fldname x ++ show n)
                                                                |n<-[(1::Integer)..]])
                                                  )
                                                  [] -- no field-names are taken
                                                  (fields plug)
                                        }
                lowerCase = map toLower -- from Char
        vsqlplugs = map makeSqlPlug (ctxsql context)
        vphpplugs = map makePhpPlug (ctxphp context)
        -- services (type ObjectDef) can be generated from a basic ontology. That is: they can be derived from a set
        -- of relations together with multiplicity constraints. That is what serviceG does.
        -- This is meant to help a developer to build his own list of services, by providing a set of services that works.
        -- The developer will want to assign his own labels and maybe add or rearrange attributes.
        -- This is easier than to invent a set of services from scratch.

        -- Rule: a service must be large enough to allow the required transactions to take place within that service.
        -- TODO: afdwingen dat attributen van elk object unieke namen krijgen.

--- generation of services:
--  Step 1: select and arrange all declarations to obtain a set cRels of total relations
--          to ensure insertability of entities
        cRels = [     morph d | d<-declarations context, decusr d, isTot d]++
                [flp (morph d)| d<-declarations context, decusr d, not (isTot d) && isSur d]
--  Step 1: select and arrange all declarations to obtain a set cRels of injective relations
--          to ensure deletability of entities
        dRels = [     morph d | d<-declarations context, decusr d, isInj d]++
                [flp (morph d)| d<-declarations context, decusr d, not (isInj d) && isUni d]
--  Step 3: compute maximally total expressions and maximally injective expressions.
        maxTotExprs = clos cRels
        maxInjExprs = clos dRels
--  Step 4: generate services from the maximally total expressions and maximally injective expressions.
        serviceGen
         = [ Obj (name c)        -- objnm
                 Nowhere         -- objpos
                 (Tm (mIs c)(-1))    -- objctx
                 (recur [] cl)   -- objats
                 []              -- objstrs
           | cl <- eqCl source (maxTotExprs `uni` maxInjExprs), e0<-take 1 cl, c<-[source e0]]
--  Auxiliaries for generating services:
        morph d = Mph (name d) (pos d) [] (source d,target d) True d
--    Warshall's transitive closure algorithm, adapted for this purpose:
        clos :: Morphisms -> Expressions
        clos xs
         = f [F [Tm x (-1)]| x<-xs] (rd (map source xs) `isc` rd (map target xs))
           where
            f q (x:xs') = f (q ++ [F (ls++rs)| l@(F ls)<-q, x<=target l
                                             , r@(F rs)<-q, x<=source r
                                             , null (ls `isc` rs)
                                             ]) xs'
            f q []      = q
       
        recur trace es
         = [ Obj (showADLcode fSpec t)     -- objnm
                 Nowhere                   -- objpos
                 t                         -- objctx
                 (recur (trace++[c]) cl)   -- objats
                 []                        -- objstrs
           | cl<-eqCl (\(F ts)->head ts) es, F ts<-take 1 cl, t<-[head ts], c<-[source t], c `notElem` trace ]
        --TODO -> assign themerules to themes and remove them from the Anything theme
        themes' = FTheme{tconcept=Anything,tfunctions=[],trules=themerules}
                  :(map maketheme$orderby [(wsopertheme oper, oper)
                                          |oper<-themeoperations, wsopertheme oper /= Nothing])
        --TODO -> by default CRUD operations of datasets, possibly overruled by ECA or PHP plugs
        themeoperations = phpoperations++sqloperations
        phpoperations =[makeDSOperation$makePhpPlug phpplug | phpplug<-(ctxphp context)]
        sqloperations =[oper|obj<-ctxsql context, oper<-makeDSOperations (vkeys fSpec) obj]
        --query copied from FSpec.hs revision 174
        themerules = [r|p<-patterns context, r<-rules p++signals p]
        maketheme (Just c,fs) = FTheme{tconcept=c,tfunctions=fs,trules=[]}
        maketheme _ = error("!Fatal (module ADL2Fspec 235): function makeFspec.maketheme: The theme must involve a concept.")
        orderby :: (Eq a) => [(a,b)] ->  [(a,[b])]
        orderby xs =  [(x,[y|(x',y)<-xs,x==x']) |x<-rd [dx|(dx,_)<-xs] ]

{- makePlugs computes a set of plugs to obtain wide tables with minimal redundancy.
   First, we determine classes of concepts that are related by bijective relations.   Code:   cl<-eqClass bi (concs context)
   Secondly, we choose one concept, c, as the kernel of that plug. If there is any choice, we choose the most generic one.
   This implies that no concept in cl is more generic than c.  Code: null [y|y<-cl, x<y]
   Thirdly, we need all univalent relations that depart from this class to be the attributes. Code:   dss cl
   Then, all these morphisms are made into fields. Code: [mph2fld m | m<- mIs c: dss cs ]
   Now we have plugs. However, some are redundant. If there is a surjective relation from the kernel of plug p
   to the kernel of plug p' and there are no univalent relations departing from p',
   then plug p can serve as kernel for plug p'. Hence p' is redundant and can be removed. It is absorbed by p.
   So, we sort the plugs on length, the longest first. Code:   sort' ((0-).length.fields)
   Finally, we filter out all shorter plugs that can be represented by longer ones. Code: absorb
   The parameter allDecs contains all relations that are declared in context, enriched with extra multiplicities. It was added to avoid recomputation of the extra multiplicities.
-}
   makePlugs :: Context -> Declarations -> [Plug] -> [Plug]
   makePlugs context allDecs currentPlugs
    = {- diagnostic
         error (show (eqClass bi nonCurrConcs)): 
      -}
      (absorb . sort' ((0-).length.fields))
       [ PlugSql [mph2fld m | m<- mIs c: dss cl]    -- fields
                 (name c)                           -- plname
                 (ILGV Eenvoudig)                   -- plfpa 
       | cl<-eqClass bi nonCurrConcs
       , let c=head [x| x<-cl, null [y|y<-cl, x<y]] -- SJ om een of andere reden was dit voorheen:  let c=minimum [g|g<-nonCurrConcs,g<=head cl]
       ]
      where
       nonCurrDecls = allDecs >- concat (map decls currentPlugs)
       nonCurrConcs = [c| c@C{}<-concs context] >- concat (map concs currentPlugs)
       mph2fld m = Fld (name m)                                     -- fldname : 
                       (Tm m (-1))                                       -- fldexpr :
                       (if isSQLId then SQLId else SQLVarchar 255)  -- fldtype :
                       (not (isTot m))                              -- fldnull : can there be empty field-values? 
                       (isInj m)                                    -- flduniq : are all field-values unique?
                       isAuto                                       -- fldauto : is the field auto increment?
                   where isSQLId = isIdent m && isAuto
                         isAuto  = isIdent m
                                    && not (null [key| key<-keyDefs context, kdcpt key==target m]) -- if there are any keys around, make this plug autoincrement.
                                    && null (contents m) -- and the the field may not contain any strings
 -- bi means that there is a bijective relation between two concepts. 
       c `bi` c' = not (null [mph| mph<-nonCurrDecls, isFunction mph, isFunction (flp mph)
                                 , source mph<=c && target mph<=c'  -- WAAROM (SJ) Bas, waarom is dit correct? Ik zou verwachten: source mph==c && target mph==c'
                                   || source mph<=c' && target mph<=c])
{- The attributes of a plug are determined by the univalent relations that depart from the kernel. -}
       dss cl = [     makeMph d | d<-nonCurrDecls, isUni      d , source d `elem` cl]++
                [flp (makeMph d)| d<-nonCurrDecls, isUni (flp d), target d `elem` cl]

{- Absorb
If a concept is represented by plug p, and there is a surjective path between concept c' and c, then c' can be represented in the same table.
Hence, we do not need a separate plug for c' and it will be skipped.
-}
       absorb []     = []
       absorb (p:ps) = p: absorb [p'| p'<-ps
                                    , kernel p' `notElem` [target m| f<-fields p
                                                                   , Tm m _<-[fldexpr f]
                                                                   , isSur m]]

       kernel :: Plug -> Concept -- determines the core concept of p. The plug serves as concept table for (kernel p).
       kernel p@(PlugSql{}) = source (fldexpr (head (fields p)))
       kernel _ = error("!Fatal (module ADL2Fspec 293): function \"kernel\"")


   makeSqlPlug :: ObjectDef -> Plug
   makeSqlPlug obj = PlugSql{fields=makeFields
                             ,plname=name obj
                             ,plfpa=ILGV Eenvoudig}
      where
      makeFields ::  [SqlField]
      makeFields =
        [Fld{fldname = name att
            ,fldexpr = objctx att
            ,fldtype = sqltp att
            ,fldnull = nul att
            ,flduniq = uniq att
            ,fldauto = att `elem` autoFields
            }
        | att<-objats obj
        ]
        where nul  att = not (isTot (objctx att))
              uniq att = null [a' | a' <- objats obj
                                  , not (isUni (disjNF$F[flp$objctx att,objctx a']))]
              autoFields = take 1 [a'| a'<-objats obj
                                     , sqltp a'==SQLId, isTot (objctx a')
                                     , uniq a', isIdent $ objctx a' ]
      sqltp :: ObjectDef -> SqlType
      sqltp att = head $ [makeSqltype sqltp' | strs<-objstrs att,('S':'Q':'L':'T':'Y':'P':'E':'=':sqltp')<-strs]
                         ++[SQLVarchar 255]
      makeSqltype :: String -> SqlType
      makeSqltype str = case str of
          ('V':'a':'r':'c':'h':'a':'r':_) -> SQLVarchar 255 --TODO number
          ('P':'a':'s':'s':_) -> SQLPass
          ('C':'h':'a':'r':_) -> SQLChar 255 --TODO number
          ('B':'l':'o':'b':_) -> SQLBlob
          ('S':'i':'n':'g':'l':'e':_) -> SQLSingle
          ('D':'o':'u':'b':'l':'e':_) -> SQLDouble
          ('u':'I':'n':'t':_) -> SQLuInt 4 --TODO number
          ('s':'I':'n':'t':_) -> SQLsInt 4 --TODO number
          ('I':'d':_) -> SQLId 
          ('B':'o':'o':'l':_) -> SQLBool
          _ -> SQLVarchar 255 --TODO number

   makePhpPlug :: ObjectDef -> Plug
   makePhpPlug plug = PlugPhp{args=makeArgs,returns=makeReturns,function=PhpAction{action=makeActiontype,on=[]}
                             ,phpfile="phpPlugs.inc.php",plname=name plug,plfpa=KGV Eenvoudig}
      where
      makeActiontype = head $ [case str of {"SELECT"->Read;
                                            "CREATE"->Create;
                                            "UPDATE"->Update;
                                            "DELETE"->Delete;
                                            _ -> error $ "!Fatal (module ADL2Fspec 341): Choose from ACTION=[SELECT|CREATE|UPDATE|DELETE].\n"  
                                                         ++ show (objpos plug)
                                           }
                     | strs<-objstrs plug,'A':'C':'T':'I':'O':'N':'=':str<-strs]
                     ++ [error $ "!Fatal (module ADL2Fspec 345): Specify ACTION=[SELECT|CREATE|UPDATE|DELETE] on phpplug.\n"  ++ show (objpos plug)]
      makeReturns = head $ [PhpReturn {retval=PhpObject{objectdf=oa,phptype=makePhptype oa}}
                           | oa<-objats plug, strs<-objstrs oa,"PHPRETURN"<-strs]
                           ++ [PhpReturn {retval=PhpNull}]
      makeArgs = [(i,PhpObject{objectdf=oa,phptype=makePhptype oa})
                 | (i,oa)<-zip [1..] (objats plug), strs<-(objstrs oa), elem "PHPARG" strs]
   makePhptype :: ObjectDef -> PhpType
   makePhptype objat = head $ [case str of {"String"->PhpString;
                                            "Int"->PhpInt;
                                            "Float"->PhpFloat;
                                            "Array"->PhpArray;
                                            _ -> error $ "!Fatal (module ADL2Fspec 356): Choose from PHPTYPE=[String|Int|Float|Array].\n"  
                                                        ++ show (objpos objat)
                                           }
                     | strs<-objstrs objat,'P':'H':'P':'T':'Y':'P':'E':'=':str<-strs]
                     ++ [error $ "!Fatal (module ADL2Fspec 360): Specify PHPTYPE=[String|Int|Float|Array] on PHPARG or PHPRETURN.\n"
                                 ++ show (objpos objat)]

   --DESCR -> Use for plugs that describe a single operation like PHP plugs
   makeDSOperation :: Plug -> WSOperation
   makeDSOperation PlugSql{} = error $ "!Fatal (module ADL2Fspec 365): function makeDSOperation: ECA plugs do not describe a single operation."
   makeDSOperation p@PlugPhp{} = 
       let nullval val = case val of
                         PhpNull    -> True
                         PhpObject{}-> False
           towsaction x = case x of {Create->WSCreate;Read->WSRead;Update->WSUpdate;Delete->WSDelete}
       in WSOper{wsaction=towsaction$action$function p
                 ,wsmsgin=[objectdf arg|(_,arg)<-args p,nullval$arg]
                 ,wsmsgout=[objectdf$retval$returns p|nullval$retval$returns p]
                 }
   --DESCR -> Use for objectdefs that describe all four CRUD operations like ECA plugs
   makeDSOperations :: [KeyDef] -> ObjectDef -> [WSOperation]
   makeDSOperations kds obj = 
       [WSOper{wsaction=WSCreate,wsmsgin=[obj],wsmsgout=[]}
       ,WSOper{wsaction=WSUpdate,wsmsgin=[obj],wsmsgout=[]}
       ,WSOper{wsaction=WSDelete,wsmsgin=[obj],wsmsgout=[]}]
     ++(if null keydefs then [readby []] else map readby keydefs)
       where
       keydefs = [kdats kd|kd<-kds,objtheme obj==keytheme kd]
       readby keyobj = WSOper{wsaction=WSRead,wsmsgin=keyobj,wsmsgout=[obj]}
   wsopertheme :: WSOperation -> Maybe Concept
   wsopertheme oper = 
      let msgthemes = map objtheme (wsmsgin oper++wsmsgout oper)
      in if samethemes msgthemes then Just$head msgthemes else Nothing
   
   --REMARK -> called samethemes because only used in this context
   samethemes :: (Eq a) => [a] -> Bool
   samethemes [] = False
   samethemes (_:[]) = True
   samethemes (c:c':cs) = if c==c' then samethemes (c':cs) else False

   --DESCR -> returns the concept on which the objectdef acts 
   objtheme :: ObjectDef -> Concept
   objtheme obj = case source$objctx obj of
      S -> let objattheme = [objtheme objat|objat<-objats obj]
           in if (not.null) objattheme then head objattheme
              else S
      c -> c

   --DESCR -> returns the concept on which the keydef is defined 
   keytheme :: KeyDef -> Concept
   keytheme kd = kdcpt kd

   editable :: Expression -> Bool   --TODO deze functie staat ook in Calc.hs...
   editable (Tm Mph{} _)  = True
   editable (Tm I{} _)    = True
   editable _           = False

   editMph :: Expression -> Morphism  --TODO deze functie staat ook in Calc.hs...
   editMph (Tm m@Mph{} _) = m
   editMph (Tm m@I{} _)   = m
   editMph e            = error("!Fatal (module ADL2Fspec 417): cannot determine an editable declaration in a composite expression: "++show e)

   makeFservice :: Context -> [Quad] -> ObjectDef -> Fservice
   makeFservice context allQuads object
    = let s = Fservice{ fsv_objectdef = object  -- the object from which the service is drawn
-- The relations that may be edited by the user of this service are represented by fsv_rels. Editing means that tuples can be added to or removed from the population of the relation.
                      , fsv_rels      = rels
-- The rules that may be affected by this service
                      , fsv_rules     = invariants
                      , fsv_quads     = qs
-- The ECA-rules that may be used by this service to restore invariants.
                      , fsv_ecaRules  = nECArules
-- All signals that are visible in this service
                      , fsv_signals   = []
-- All fields/parameters of this service
                      , fsv_fields    = srvfields
-- All concepts of which this service can create new instances
                      , fsv_creating  = [c| c<-rd (map target rels), t<-fsv_ecaRules s, ecaTriggr (t arg)==On Ins (mIs c)]
-- All concepts of which this service can delete instances
                      , fsv_deleting  = [c| c<-rd (map target rels), t<-fsv_ecaRules s, ecaTriggr (t arg)==On Del (mIs c)]
                      , fsv_fpa       = case depth object of -- Valideren in de FPA-wereld
                                          0 -> NO
                                          1 -> IF Eenvoudig
                                          2 -> IF Eenvoudig
                                          3 -> IF Gemiddeld
                                          _ -> IF Moeilijk 
                      } in s
    where
        rels = rd (recur object)
         where recur obj = [editMph (objctx o)| o<-objats obj, editable (objctx o)]++[m| o<-objats obj, m<-recur o]
        vis        = rd (map makeInline rels++map (mIs.target) rels)
        visible m  = makeInline m `elem` vis
        qs         = quads visible invariants
        invariants = [rule| rule<-rules context, not (null (map makeInline (mors rule) `isc` vis))]
        ecaRs      = assembleECAs visible qs
        depth :: ObjectDef -> Int
        depth obj  = foldr max 0 [depth o| o<-objats obj]+1
        normECA :: ECArule -> Declaration -> ECArule    -- TODO: hier nog naar kijken: er gebeurt nog niets met het argument!
        normECA e _ = e{ecaAction=normPA (ecaAction e)}
        nECArules  = [normECA e| e<-ecaRs]
        trigs :: ObjectDef -> [Declaration->ECArule]
        trigs _  = [] -- [c | editable (objctx obj), c<-nECArules {- ,not (isBlk (ecaAction (c arg))), not (isDry (ecaAction (c arg))) -} ]
        arg = error("!Todo (module ADL2Fspec 463): declaratie Delta invullen")
        srvfields = [fld 0 o| o<-objats object]
        fld :: Int -> ObjectDef -> Field
        fld sLevel obj
         = Att { fld_name     = objnm obj
               , fld_sub      = [fld (sLevel +1) o| o<-objats obj]
               , fld_expr     = objctx obj
               , fld_mph      = if editable (objctx obj)
                                then editMph (objctx obj)
                                else error("!Fatal (module ADL2Fspec 461): cannot edit a composite expression: "++show (objctx obj)++"\nPlease test editability of field "++objnm obj++" by means of fld_editable first!")
               , fld_editable = editable (objctx obj)      -- can this field be changed by the user of this service?
               , fld_list     = not (isUni (objctx obj))   -- can there be multiple values in this field?
               , fld_must     = isTot (objctx obj)         -- is this field obligatory?
               , fld_new      = True                       -- can new elements be filled in? (if no, only existing elements can be selected)
               , fld_sLevel   = sLevel                     -- The (recursive) depth of the current servlet wrt the entire service. This is used for documentation.
               , fld_insAble  = not (null insTrgs)         -- can the user insert in this field?
               , fld_onIns    = case insTrgs of
                                 []  ->  error("!Fatal (module ADL2Fspec 469): no insert functionality found in field "++objnm obj++" of service "++name obj++" on line: "++show (pos (objctx obj)))
                                 [t] ->  t
                                 _   ->  error("!Fatal (module ADL2Fspec 471): multiple insert triggers found in field "++objnm obj++" of service "++name obj++" on line: "++show (pos (objctx obj)))
               , fld_delAble  = not (null delTrgs)         -- can the user delete this field?
               , fld_onDel    = case delTrgs of
                                 []  ->  error("!Fatal (module ADL2Fspec 474): no delete functionality found in field "++objnm obj++" of service "++name obj++" on line: "++show (pos (objctx obj)))
                                 [t] ->  t
                                 _   ->  error("!Fatal (module ADL2Fspec 476): multiple delete triggers found in field "++objnm obj++" of service "++name obj++" on line: "++show (pos (objctx obj)))
               }
           where triggers = trigs obj
                 insTrgs  = [c | c<-triggers, ecaTriggr (c arg)==On Ins (makeInline (editMph (objctx obj))) ]
                 delTrgs  = [c | c<-triggers, ecaTriggr (c arg)==On Del (makeInline (editMph (objctx obj))) ]


-- Comment on fld_new:
-- Consider this: New elements cannot be filled in
--    if there is a total relation r with type obj==source r  (i.e. r comes from obj),
--    which is outside the scope of this service.
-- Why? If you were to insert a new obj, x, then r would require a new link (x,y).
--    However, since r is out of scope, you cannot insert (x,y) into r.
-- More generally, if there is an ECA rule with I[type obj] in its left hand side,
--    and a right hand side that is out of scope of this service,
--    you may not insert a new element in obj.


--   fst3 :: (a,b,c) -> a
--   fst3 (a,_,_) = a
--   snd3 :: (a,b,c) -> b
--   snd3 (_,b,_) = b

   -- Quads embody the "switchboard" of rules. A quad represents a "proto-rule" with the following meaning:
   -- whenever Morphism m is affected (i.e. tuples in m are inserted or deleted),
   -- the rule may have to be restored using functionality from one of the clauses.
   -- The rule is taken along for traceability.
   quads :: (Morphism->Bool) -> Rules  -> [Quad]
   quads visible rs
    = [ Quad m (Clauses [ (conj,allShifts conj)
                        | conj <- conjuncts rule
      --                , (not.null.lambda Ins (Tm m)) conj  -- causes infinite loop
      --                , not (checkMono conj Ins m)         -- causes infinite loop
                        , conj'<- [subst (m, actSem Ins m (delta (sign m))) conj]
                        , (not.isTrue.conjNF) (Fu[Cp conj,conj']) -- the system must act to restore invariance     
                        ]
                        rule)
      | rule<-rs
      , m<-rd (map makeInline (mors rule))
      , visible m
      ]

-- The function allClauses yields an expression which has constructor Fu in every case.
   allClauses :: Rule -> Clauses
   allClauses rule = Clauses [(conj,allShifts conj)| conj<-conjuncts rule] rule

   allShifts :: Expression -> Expressions
   allShifts conjunct = rd [simplify (normFlp e')| e'<-shiftL conjunct++shiftR conjunct, not (isTrue e')]
    where
       normFlp (Fu []) = Fu []
       normFlp (Fu fs) = if length [m| f<-fs, m<-morlist f, inline m] <= length [m| f<-fs, m<-morlist f, not (inline m)]
                         then Fu (map flp fs) else (Fu fs)
       normFlp _ = error ("!Fatal (module Calc 61): normFlp must be applied to Fu expressions only, look for mistakes in shiftL or shiftR")

   shiftL :: Expression -> Expressions
   shiftL r
    | length antss+length conss /= length fus = error ("!Fatal (module Calc 65): shiftL will not handle argument of the form "++showADL r)
    | null antss || null conss                = [disjuncts r|not (null fs)] --  shiftL doesn't work here.
    | idsOnly antss                           = [Fu ([Cp (F [Tm (mIs srcA)(-1)])]++map F conss)]
    | otherwise                               = [Fu ([ Cp (F (if null ts then id' css else ts))
                                                     | ts<-ass++if null ass then [id' css] else []]++
                                                     [ F (if null ts then id' ass else ts)
                                                     | ts<-css++if null css then [id' ass] else []])
                                                | (ass,css)<-rd(move antss conss)
                                                , if null css then error "!Fatal (module Calc 73): null css in shiftL" else True
                                                , if null ass then error "!Fatal (module Calc 74): null ass in shiftL" else True
                                                ]
    where
     Fu fs = disjuncts r
     fus = filter (not.isIdent) fs
     antss = [ts | Cp (F ts)<-fus]
     conss = [ts | F ts<-fus]
     srcA = -- if null antss  then error ("!Fatal (module Calc 81): empty antecedent in shiftL ("++showHS options "" r++")") else
            if length (eqClass order [ source (head ants) | ants<-antss])>1 then error ("!Fatal (module Calc 82): shiftL ("++showADL r++")\nin calculation of srcA\n"++show (eqClass order [ source (head ants) | ants<-antss])) else
            foldr1 lub [ source (head ants) | ants<-antss]
     id' ass = [Tm (mIs c) (-1)]
      where a = (source.head.head) ass
            c = if not (a `order` b) then error ("!Fatal (module Calc 86): shiftL ("++showADL r++")\nass: "++show ass++"\nin calculation of c = a `lub` b with a="++show a++" and b="++show b) else
                a `lub` b
            b = (target.last.last) ass
   -- It is imperative that both ass and css are not empty.
     move :: [Expressions] -> [Expressions] -> [([Expressions],[Expressions])]
     move ass [] = [(ass,[])]
     move ass css
      = (ass,css):
        if and ([not (idsOnly (F cs))| cs<-css]) -- idsOnly (F [])=True, so:  and [not (null cs)| cs<-css]
        then [ts| length (eqClass (==) (map head css)) == 1
                , isUni h
                , ts<-move [[flp h]++as|as<-ass] (map tail css)]++
             [ts| length (eqClass (==) (map last css)) == 1
                , isInj l
                , ts<-move [as++[flp l]|as<-ass] (map init css)]
        else []
        where h=head (map head css); l=head (map last css)

   shiftR :: Expression -> Expressions
   shiftR r
    | length antss+length conss /= length fus = error ("!Fatal (module Calc 106): shiftR will not handle argument of the form "++showADL r)
    | null antss || null conss                = [disjuncts r|not (null fs)] --  shiftR doesn't work here.
    | idsOnly conss                           = [Fu ([Cp (F [Tm (mIs srcA)(-1)])]++map F antss)]
    | otherwise                               = [Fu ([ Cp (F (if null ts then id' css else ts))
                                                     | ts<-ass++if null ass then [id' css] else []]++
                                                     [ F (if null ts then id' ass else ts)
                                                     | ts<-css++if null css then [id' ass] else []])
                                                | (ass,css)<-rd(move antss conss)]
    where
     Fu fs = disjuncts r
     fus = filter (not.isIdent) fs
     antss = [ts | Cp (F ts)<-fus]
     conss = [ts | F ts<-fus]
     srcA = if null conss then error ("!Fatal (module Calc 119): empty consequent in shiftR ("++showADL r++")") else
            if length (eqClass order [ source (head cons) | cons<-conss])>1
            then error ("Fatal (module Calc120): shiftR ("++showADL r++")\nin calculation of srcA\n"++show (eqClass order [ source (head cons) | cons<-conss]))
            else foldr1 lub [ source (head cons) | cons<-conss]
     id' css = [Tm (mIs c) (-1)]
      where a = (source.head.head) css
            c = if not (a `order` b)
                then error ("!Fatal (module Calc 126): shiftR ("++showADL r++")\nass: "++show css++"\nin calculation of c = a `lub` b with a="++show a++" and b="++show b)
                else a `lub` b
            b = (target.last.last) css
     move :: [Expressions] -> [Expressions] -> [([Expressions],[Expressions])]
     move [] css = [([],css)]
     move ass css
      = (ass,css):
        if and [not (null as)| as<-ass]
        then [ts| length (eqClass (==) (map head ass)) == 1
                , isSur h
                , ts<-move (map tail ass) [[flp h]++cs|cs<-css]]++
             [ts| length (eqClass (==) (map last ass)) == 1
                , isTot l
                , ts<-move (map init ass) [cs++[flp l]|cs<-css]]
        else []
        where h=head (map head ass); l=head (map last ass)



-- assembleECAs :: [Quad] -> [ECArule]
-- Deze functie neemt verschillende clauses samen met het oog op het genereren van code.
-- Hierdoor kunnen grotere brokken procesalgebra worden gegenereerd.
   assembleECAs :: (Morphism->Bool) -> [Quad] -> [ECArule]
   assembleECAs visible qs = [ecarule i| (ecarule,i) <- zip ecas [1..]]
      where
       ecas
        = [ ECA (On ev m) delt action
          | mphEq <- eqCl fst4 [(m,shifts,conj,cl_rule ccrs)| Quad m ccrs<-qs, (conj,shifts)<-cl_conjNF ccrs]
          , m <- map fst4 (take 1 mphEq), Tm delt _<-[delta (sign m)]
          , ev<-[Ins,Del]
          , action <- [ All
                        [ Chc [ (if isTrue  clause'   then Nop else
                                 if isFalse clause'   then Blk else
--                               if not (visible m) then Blk else
                                 doCode visible ev toExpr viols)
                                 [(conj,causes)]  -- the motivation for these actions
                              | clause@(Fu fus) <- shifts
                              , clause' <- [ conjNF (subst (m, actSem Ins m (delta (sign m))) clause)]
                              , viols <- [ conjNF (notCp clause')]
                              , frExpr  <- [ if ev==Ins
                                             then Fu [f| f<-fus, isNeg f]
                                             else Fu [f| f<-fus, isPos f] ]
                              , m `elem` map makeInline (mors frExpr)
                              , toExpr  <- [ if ev==Ins
                                             then Fu [      f| f<-fus, isPos f]
                                             else Fi [notCp f| f<-fus, isNeg f] ]
                              ]
                              [(conj,causes)]  -- to supply motivations on runtime
                        | conjEq <- eqCl snd3 [(shifts,conj,rule)| (_,shifts,conj,rule)<-mphEq]
                        , causes  <- [ (map thd3 conjEq) ]
                        , conj <- map snd3 (take 1 conjEq), shifts <- map fst3 (take 1 conjEq)
                        ]
                        [(conj,rd' nr [r|(_,_,_,r)<-cl])| cl<-eqCl thd4 mphEq, (_,_,conj,_)<-take 1 cl]  -- to supply motivations on runtime
                      ]
          ]
       fst4 (w,_,_,_) = w
       fst3 (x,_,_) = x
       snd3 (_,y,_) = y
       thd3 (_,_,z) = z
       thd4 (_,_,z,_) = z

   conjuncts :: Rule -> Expressions
   conjuncts = fiRule.conjNF.normExpr
    where fiRule (Fi fis) = {- map disjuncts -} fis
          fiRule r        = [ {- disjuncts -} r]

-- The function disjuncts yields an expression which has constructor Fu in every case.
   disjuncts :: Expression -> Expression
   disjuncts = fuRule
    where fuRule (Fu cps) = (Fu . rd . map cpRule) cps
          fuRule r        = Fu [cpRule r]
          cpRule (Cp r)   = Cp (fRule r)
          cpRule r        = fRule r
          fRule (F ts)    = F ts
          fRule  r        = F [r]

   actSem :: InsDel -> Morphism -> Expression -> Expression
   actSem Ins m (Tm d _) | makeInline m==makeInline d = Tm m (-1)
                       | otherwise                  = Fu[Tm m (-1),Tm d (-1)]
   actSem Ins m delt   = disjNF (Fu[Tm m (-1),delt])
   actSem Del m (Tm d _) | makeInline m==makeInline d = Fi[]
                       | otherwise                  = Fi[Tm m (-1), Cp (Tm d (-1))]
   actSem Del m delt   = conjNF (Fi[Tm m (-1),Cp delt])
 --  actSem Del m delt = Fi[m,Cp delt]

   delta :: (Concept, Concept) -> Expression
   delta (a,b)  = Tm (makeMph (Sgn { decnm   = "Delta"
                                   , desrc   = a
                                   , detrg   = b
                                   , decprps = []
                                   , decprL  = ""
                                   , decprM  = ""
                                   , decprR  = ""
                                   , decpopu = []
                                   , decexpl = ""
                                   , decfpos = Nowhere
                                   , decid   = 0
                                   , deciss  = True
                                   , decusr  = False
                                   , decpat  = ""
                                   })) (-1)

   -- | de functie doCode beschrijft de voornaamste mogelijkheden om een expressie delta' te verwerken in expr (met tOp'==Ins of tOp==Del)
   doCode :: (Morphism->Bool)        --  the morphisms that may be changed
          -> InsDel
          -> Expression              --  the expression in which a delete or insert takes place
          -> Expression              --  the delta to be inserted or deleted
          -> [(Expression,Rules )]   --  the motivation, consisting of the conjuncts (traced back to their rules) that are being restored by this code fragment.
          -> PAclause
   doCode editable tOp' expr1 delta1 motive = doCod delta1 tOp' expr1 motive
    where
      doCod deltaX tOp exprX motiv =
        case (tOp, exprX) of
          (_ ,  Fu [])   -> Blk motiv
          (_ ,  Fi [])   -> Nop motiv
          (_ ,  F [])    -> error ("!Fatal (module Calc 366): doCod ("++showADL deltaX++") "++show tOp++" "++showADL (F [])++",\n"++
                                     "within function doCode "++show tOp'++" ("++showADL expr1++") ("++showADL delta1++").")
          (_ ,  Fd [])   -> error ("!Fatal (module Calc 368): doCod ("++showADL deltaX++") "++show tOp++" "++showADL (Fd [])++",\n"++
                                     "within function doCode "++show tOp'++" ("++showADL expr1++") ("++showADL delta1++").")
          (_ ,  Fu [t])  -> doCod deltaX tOp t motiv
          (_ ,  Fi [t])  -> doCod deltaX tOp t motiv
          (_ ,  F [t])   -> doCod deltaX tOp t motiv
          (_ ,  Fd [t])  -> doCod deltaX tOp t motiv
          (Ins, Cp x)    -> doCod deltaX Del x motiv
          (Del, Cp x)    -> doCod deltaX Ins x motiv
          (Ins, Fu fs)   -> Chc [ doCod deltaX Ins f motiv | f<-fs{-, not (f==expr1 && Ins/=tOp') -}] motiv -- the filter prevents self compensating PA-clauses.
          (Ins, Fi fs)   -> All [ doCod deltaX Ins f []    | f<-fs ] motiv
          (Ins, F ts)    -> Chc [ if F ls==flp (F rs)
                                  then Chc [ New c fLft motiv
                                           , Sel c (F ls) fLft motiv
                                           ] motiv
                                  else Chc [ New c (\x->All [fLft x, fRht x] motiv) motiv
                                           , Sel c (F ls) fLft motiv
                                           , Sel c (flp(F rs)) fRht motiv
                                           ] motiv
                                | (ls,rs)<-chop ts, c<-[source (F rs) `lub` target (F ls)]
                                , fLft<-[(\atom->doCod (disjNF (Fu[F [Tm (Mp1 atom [] c)(-1),v (c,source deltaX),deltaX],Cp (F rs)])) Ins (F rs) [])]
                                , fRht<-[(\atom->doCod (disjNF (Fu[F [deltaX,v (target deltaX,c),Tm (Mp1 atom [] c)(-1)],Cp (F ls)])) Ins (F ls) [])]
                                ] motiv
          (Del, F ts)    -> Chc [ if F ls==flp (F rs)
                                  then Chc [ Sel c (F ls) (\_->Rmv c fLft motiv) motiv
                                           , Sel c (F ls) fLft motiv
                                           ] motiv
                                  else Chc [ Sel c (Fi [F ls,flp(F rs)]) (\_->Rmv c (\x->All [fLft x, fRht x] motiv) motiv) motiv
                                           , Sel c (Fi [F ls,flp(F rs)]) fLft motiv
                                           , Sel c (Fi [F ls,flp(F rs)]) fRht motiv
                                           ] motiv
                                | (ls,rs)<-chop ts, c<-[source (F rs) `lub` target (F ls)]
                                , fLft<-[(\atom->doCod (disjNF (Fu[F [Tm (Mp1 atom [] c)(-1),v (c,source deltaX),deltaX],Cp (F rs)])) Del (F rs) [])]
                                , fRht<-[(\atom->doCod (disjNF (Fu[F [deltaX,v (target deltaX,c),Tm (Mp1 atom [] c)(-1)],Cp (F ls)])) Del (F ls) [])]
                                ] motiv
          (Del, Fu fs)   -> All [ doCod deltaX Del f []    | f<-fs{-, not (f==expr1 && Del/=tOp') -}] motiv -- the filter prevents self compensating PA-clauses.
          (Del, Fi fs)   -> Chc [ doCod deltaX Del f motiv | f<-fs ] motiv
-- Op basis van de Morgan is de procesalgebra in het geval van (Ins, Fd ts)  afleidbaar uit uit het geval van (Del, F ts) ...
          (_  , Fd ts)   -> doCod deltaX tOp (Cp (F (map Cp ts))) motiv
          (_  , K0 x)    -> doCod (deltaK0 deltaX tOp x) tOp x motiv
          (_  , K1 x)    -> doCod (deltaK1 deltaX tOp x) tOp x motiv
          (_  , Tm m _)  -> (if editable m then Do tOp exprX (disjNF deltaX) motiv else Blk [(Tm m (-1),rd' nr [r|(_,rs)<-motiv, r<-rs])])
          (_ , _)        -> error ("!Fatal (module Calc 418): Non-exhaustive patterns in the recursive call doCod ("++showADL deltaX++") "++show tOp++" ("++showADL exprX++"),\n"++
                                   "within function doCode "++show tOp'++" ("++showADL exprX++") ("++showADL delta1++").")

   chop :: [t] -> [([t], [t])]
   chop []     = []
   chop [_]    = []
   chop (x:xs) = ([x],xs): [(x:l, r)| (l,r)<-chop xs]

   deltaK0 :: t -> InsDel -> t1 -> t
   deltaK0 delta' Ins _ = delta'  -- error! (tijdelijk... moet berekenen welke paren in x gezet moeten worden zodat delta |- x*)
   deltaK0 delta' Del _ = delta'  -- error! (tijdelijk... moet berekenen welke paren uit x verwijderd moeten worden zodat delta/\x* leeg is)
   deltaK1 :: t -> InsDel -> t1 -> t
   deltaK1 delta' Ins _ = delta'  -- error! (tijdelijk... moet berekenen welke paren in x gezet moeten worden zodat delta |- x+)
   deltaK1 delta' Del _ = delta'  -- error! (tijdelijk... moet berekenen welke paren uit x verwijderd moeten worden zodat delta/\x+ leeg is)

