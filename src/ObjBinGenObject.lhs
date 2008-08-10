> module ObjBinGenObject where
>  import Char
>  import Auxiliaries
>  import Calc(informalRule, shrink, disjNF, computeOrder, ComputeRule, triggers)
>  import CC_aux
>  import CommonClasses
>  import ERmodel
>  import PredLogic -- (for error messages by dbCorrect)
>  import Hatml     -- (for converting error messages to HTML)
>  import Atlas     -- (for converting error messages to HTML)
>  import RelBinGenBasics

The service "getobject" communicates metadata to the interface.

>  generateService_getobject :: Context -> ObjectDef -> String
>  generateService_getobject context object
>   = "function getobject_"++ name object ++"(){\n  "
>     ++ chain "\n  " (addFstLst "  return " ";" (map ((++) "  ") (getObject context object))) ++
>     "\n  }\n"

>  objectServices :: Context -> String -> ObjectDef -> String
>  objectServices context filename object
>   = (chain "\n  "
>     ([ "<?php // generated with "++adlVersion
>      , ""
>      , "/********* on "++(show (pos object))
>      ] ++ (map ((++) " * ") (
>                showObjDef object )) ++
>      [" *********/"
>      , ""
>      , generateService_getobject context object   -- generate metadata for "object"
>      ] ++ showClasses context [] object ++
>      [ generateService_getEach context capname object
>      , generateService_create  context capname object
>      , generateService_read    context capname object
>      , generateService_update  context capname object
>      , generateService_delete  context capname object]
>     )) ++ "\n?>"
>    where
>     showObjDef a | null (attributes a) =
>      [  (name a)++"["++(name (concept a))++"] : "++ (showADL (ctx a))
>       ]
>     showObjDef a =
>      (  (name a)++"["++(name (concept a))++"] : "++ (showADL (ctx a))
>       ):(concat (mapHeadTail (mapHeadTail ((++) " = [ ")
>                                           ((++) "     "))
>                              (mapHeadTail ((++) "   , ")
>                                           ((++) "     "))
>                              [ (showObjDef as)
>                              | as <- attributes a
>                              ]
>                 )
>         ) ++ ["  ]"]
>     capname = (toUpper (head (name object))):(tail (name object))

The service "getEach<concept>" returns the set of all instances of <concept> that are in the CSL.

>  generateService_getEach :: Context -> String -> ObjectDef -> String
>  generateService_getEach context capname object
>   = "function getEach"++capname++"(){"++
>     "\n      return DB_doquer('"++(selectExpr context
>                                            25
>                                            (sqlAttConcept context (concept object))
>                                            (sqlAttConcept context (concept object))
>                                            (Tm (I [] (concept object) (concept object) True))
>                                )++"');\n  }"

The service "create<concept>" creates a new instance of <concept> in the CSL.

>  generateService_create :: Context -> String -> ObjectDef -> String
>  generateService_create context capname object
>   = "function create"++capname++"("++(name object)++" &$obj){\n  "++
>     "    return update"++capname++"($obj,true);\n  }"

The service "read<concept>" reads the instance of <concept> with identity $id from the CSL.

>  generateService_read :: Context -> String -> ObjectDef -> String
>  generateService_read context capname object
>   = chain "\n  "
>     (["function read"++capname++"($id){"
>      ,"    // check existence of $id"
>      ,"    $ctx = DB_doquer('"++(doesExistQuer context object "$id")++"');"
>      ,"    if(count($ctx)==0) return false;"
>      ,"    $obj = new "++(name object)++"($id" ++ (concat [", array()" | a<-attributes object]) ++ ");"
>      ]
>      ++ (concat (map (map ((++) "    "))
>             [ [ "$ctx = DB_doquer('"++ (selectExprForAttr context a object "$id") ++"');"
>               , "foreach($ctx as $i=>$v){"
>               , "  $obj->read_"++name a++"($v['" ++ sqlExprTrg (ctx a) ++ "']);"
>               , "}"]
>             | a <-attributes object
>             ]
>            )) ++
>      ["    return $obj;"
>      ,"}"])

The service "update<concept>" reads the instance of <concept> with identity $id from the CSL,
interacts with the user to update the concept, and writes the result to the CSL.

>  generateService_update :: Context -> String -> ObjectDef -> String
>  generateService_update context capname object
>   = chain "\n  "
>     (["function update"++capname++"("++(name object)++" $"++(name object)++",$new=false){"
>      ,"    global $DB_link,$DB_err,$DB_lastquer;"
>      ,"    $preErr= $new ? 'Cannot create new "++(addslashes (name (concept object)))++": ':'Cannot update "++(addslashes (name (concept object)))++": ';"
>      ,"    DB_doquer('START TRANSACTION');"
>      ,"    if($new){ // create a new object"
>      ,"      if(!isset($"++(name object)++"->id)){ // find a unique id"
>      ,"         $nextNum = DB_doquer('"++(autoIncQuer context (concept object))++"');"
>      ,"         $"++(name object)++"->id = @$nextNum[0][0]+0;"
>      ,"      }"
>      ,"      if(DB_plainquer('" ++
>          (insertConcept context (concept object) ("$"++(name object)++"->id") False)
>                               ++"',$errno)===false){"
>      ,"          $DB_err=$preErr.(($errno==1062) ? '"
>         ++(addslashes (name (concept object))) ++" \\''.$"++(name object)++
>         "->id.'\\' allready exists' : 'Error '.$errno.' in query '.$DB_lastquer);"
>      ,"          DB_doquer('ROLLBACK');"
>      ,"          return false;"
>      ,"      }"
>      ,"    }else"]
>      ++ updateObject context [name object] object
>      ++ checkRuls context object ++
>      ["    if(true){ // all rules are met"
>      ,"        DB_doquer('COMMIT');"
>      ,"        return $"++(name object)++"->id;"
>      ,"    }"
>      ,"    DB_doquer('ROLLBACK');"
>      ,"    return false;"
>      ,"}"])

The service "delete<concept>" deletes the instance of <concept> with identity $id from the CSL.

>  generateService_delete :: Context -> String -> ObjectDef -> String
>  generateService_delete context capname object
>   = chain "\n  "
>     (["function delete"++capname++"($id){"
>      ,"  global $DB_err;"
>      ,"  $preErr= 'Cannot delete "++(addslashes (name (concept object)))++": ';"
>      ,"  DB_doquer('START TRANSACTION');"
>      ,"  "] ++
>      concat (map (map ((++) "    "))
>             [ ["$taken = DB_doquer('"++(selectExprWithF context (Tm m) cpt "$id")++"');"
>               ,"if(count($taken)) {"
>               ,"  $DB_err = 'Cannot delete "++(name object)++": "
>                ++(prag d "\\''.addslashes($id).'\\'" "\\''.addslashes($taken[0]['"
>                ++(sqlExprTrg (Tm m))++"']).'\\'" )++"';" -- pragma
>               ,"  DB_doquer('ROLLBACK');"
>               ,"  return false;"
>               ,"}"
>               ]
>             | cpt <- [concept object]
>             , m@(Mph _ _ _ _ _ d) <- morsWithCpt context cpt
>             , not (elem (makeInline m) (mors (map ctx (termAtts object))))  -- mors yields all morphisms inline.
>             ])
>      ++["/*"]
>      ++ map show (mors (map ctx (termAtts object)))
>      ++["*************"]
>      ++ map show (mors (morsWithCpt context (concept object)))
>      ++["*/"]
>      ++ deleteObject context object ++ checkRuls context object ++
>      ["  if(true) {"
>      ,"    DB_doquer('COMMIT');"
>      ,"    return true;"
>      ,"  }"
>      ,"  DB_doquer('ROLLBACK');"
>      ,"  return false;"
>      ,"}"
>      ])

>  prag (Sgn _ _ _ _ p1 p2 p3 _ _ _ _ _) s1 s2 = (addslashes p1) ++ s1 ++ (addslashes p2) ++ s2 ++ (addslashes p3)
>  morsWithCpt context cpt = rd ([m|m<-mors context, source m == cpt] ++ [flp m|m<-mors context, target m==cpt])

> --Precondition: ctx a  contains precisely one morphism.
>  deleteExprForAttr context a parent id
>   = "DELETE FROM "++sqlMorName context ((head.mors.ctx) a)++" WHERE "++(sqlExprSrc (ctx a))++"=\\''.addslashes("++id++").'\\'"

>  updateObject :: Object a => Context -> [String] -> a -> [String]
>  updateObject context nms o =
>      ["    if(!$new){"
>      ,"      // destroy old attribute values"
>      ] ++ (concat (map (map ((++) "      "))
>             [ [ "$effected = DB_doquer('"++ (selectExprForAttr context a o ("$"++nm++"->id")) ++"');"
>               , "$arr=array();"
>               , "foreach($effected as $i=>$v){"
>               , "    $arr[]='\\''.addslashes($v['"++(sqlExprTrg (ctx a))++"']).'\\'';"
>               , "}"
>               , ("$"++nm++"_"++(name a)++"_str")++"=join(',',$arr);"
>               , "DB_doquer( '"++(deleteExprForAttr context a o ("$"++nm++"->id"))++"');"
>               ]
>             | a <- termAtts o -- door de definitie van termAtts heeft de expressie "ctx a" precies ��n morfisme.
>             ]
>            )) ++
>      ["    }"
>      ]  ++ (concat (map (map ((++) "    "))
>             [ [ "foreach($"++nm++"->"++(name a)++" as $i=>$"++nm++"_"++(name a)++"){"
>               ] ++ (concat (map (map ((++) "  "))
>                     [ [ "if(isset($"++nm++"_"++(name a)++"->"++(name as)++"[0]->id)){"
>                       , "  if(count(DB_doquer('"++doesExistQuer context a ("$"++nm++"_"++(name a)++"->"++(name as)++"[0]->id")++"'))==0)"
>                       , "    DB_doquer('"++(insertConcept context (concept a) ("$"++nm++"_"++(name a)++"->id") True)++"');"
>                       ] ++ updateObject context (nms++[name a,name as]) as ++
>                       [ "}"
>                       , "$"++nm++"_"++(name a)++"->id = @$"++nm++"_"++(name a)++"->"++(name as)++"[0]->id;"
>                       ]
>                     | as <- attributes a -- De expressie ctx a bevat precies ��n morfisme.
>                     , (Tm (I _ _ _ _)) <- [ctx as]   -- De morfismen uit 'mors' zijn allemaal inline.
>                     ]
>                    ))
>                ++
>               [ "  if(!isset($"++nm++"_"++(name a)++"->id)){"
>               , "     $nextNum = DB_doquer('"++autoIncQuer context (concept a)++"');"
>               , "     $"++nm++"_"++(name a)++"->id = @$nextNum[0][0]+0;"
>               , "  }"
>               , "  DB_doquer('"++(insertConcept context (concept a) ("$"++nm++"_"++(name a)++"->id") True)++"');"
>               , "  DB_doquer('INSERT IGNORE INTO "
>                 ++(sqlMorName context (head (mors m)))++" ("++(sqlExprSrc m)++","++(sqlExprTrg m)++")"
>                 ++" VALUES (\\''.addslashes($"++nm++"->id).'\\'"
>                 ++        ",\\''.addslashes($"++nm++"_"++(name a)++"->id).'\\')');"
>               ] ++ updateObject context (nms++[name a]) a ++
>               [ "}"
>               ]
>             | a <- termAtts o -- De expressie ctx a bevat precies ��n morfisme.
>             , m <- [ctx a]   -- De morfismen uit 'mors' zijn allemaal inline.
>             ]
>            ))
>      ++ concat (map (map ((++) "    "))
>                     [ [ "if(!$new && strlen($"++nm++"_"++(name a)++"_str))"
>                       ] ++ (do_del_quer context a ("$"++nm++"_"++(name a)++"_str"))
>                     | a <- termAtts o
>                     ]
>                )
>      where nm = chain "_" nms

>--  deleteObject :: Context -> a -> [String]
>  deleteObject context object =
>      (concat (map (map ((++) "      "))
>             [ [ "$effected = DB_doquer('"++ (selectExprForAttr context a object "$id") ++"');"
>               , "$arr=array();"
>               , "foreach($effected as $i=>$v){"
>               , "    $arr[]='\\''.addslashes($v['"++(sqlExprTrg (ctx a))++"']).'\\'';"
>               , "}"
>               , "$"++(name a)++"_str=join(',',$arr);"
>               , "DB_doquer ('"++(deleteExprForAttr context a object "$id")++"');"
>               ]
>             | a <- termAtts object
>             ]
>            )) ++
>      ["  DB_doquer('DELETE FROM "++(sqlConcept context (concept object))
>       ++" WHERE "++(sqlAttConcept context (concept object))++"=\\''.addslashes($id).'\\'');"
>      ] ++ (concat (map (map ((++) "  "))
>             [ [ "if(strlen($"++(name a)++"_str))"
>               ] ++ (do_del_quer context a ("$"++(name a)++"_str"))
>             | a <- termAtts object
>             ])) 

>  andNEXISTquer context e m
>   = [ "      AND NOT EXISTS (SELECT * FROM "++(sqlMorName context m)
>     , "                       WHERE "
>       ++ (sqlConcept context (target e))++"."++(sqlAttConcept context (target e))++" = "
>       ++ (sqlMorName context m)++"."++(sqlMorSrc context m)
>     , "                     )"
>     ]

>  autoIncQuer context cpt
>   = "SELECT max(1+"++(sqlAttConcept context cpt)
>     ++") FROM "++(sqlConcept context cpt)++" GROUP BY \\'1\\'"

>  insertConcept context cpt var ignore
>   = "INSERT "++(if ignore then "IGNORE " else "") ++ "INTO "++(sqlConcept context cpt)++" ("
>     ++(sqlAttConcept context cpt)++") VALUES (\\''.addslashes("++var++").'\\')"

>  checkRuls context object
>   = (concat
>     [ ["  if (!checkRule"++show (nr rul)++"()){"
>       ,"    $DB_err=$preErr.'"++(addslashes (show(explain rul)))++"';"
>       ,"  } else"
>       ]
>     | rul <- (rules context)++(multRules context),
>       or (map (\m -> elem m (mors rul)) -- rule contains an element
>               (mors object) -- effected mors  ; SJ: mors yields all morphisms inline.
>          )
>     ])

>  doesExistQuer context object id
>   = ( selectExpr context
>                  25
>                  (sqlAttConcept context (concept object))
>                  (sqlAttConcept context (concept object))
>                  (Fi [ Tm (I [] (concept object) (concept object) True)
>                      , Tm (Mp1 ("\\''.addslashes("++id++").'\\'") (concept object))
>                      ]
>                  )
>     )

>  do_del_quer context a str
>           = [ "  DB_doquer('DELETE FROM "++(sqlConcept context (concept a))
>               , "    WHERE "++(sqlExprTrg (ctx a))++" IN ('."++str++".')"
>               ] ++ concat (
>                  [ andNEXISTquer context (ctx a) m
>                  | m@(Mph _ _ _ _ _ _) <- morsWithCpt context (concept a)
>                  ]
>                  ) ++
>               [ "  ');"]
>  termAtts o = [a|a<-attributes o, (Tm (Mph _ _ _ _ _ _))<-[ctx a]] -- Dit betekent: de expressie ctx a bevat precies ��n morfisme.
>  selectExprForAttr context a parent id
>    = selectExprWithF context (ctx a) (concept parent) id
>  selectExprWithF context e cpt id
>    = selectExpr context 25 (sqlExprSrc e) (sqlExprTrg e)
>                  (F [Tm (Mp1 ("\\''.addslashes("++id++").'\\'") cpt), e])

The function "showClasses" generates the class definitions for PHP-classes.
These classes define the PHP-objects, which are used as intermediate objects in the user interface.
A PHP-object stores information from the CSL as long as the user interacts with it.

>  showClasses context nm o
>   = [ "class "++concat [n++"_"|n<-nm] ++(name o) ++" {"] ++
>     (map ((++) "  ") (
>      ["var $id;"]
>      ++ ["var $"++(name a)++";"| a <- attributes o]++
>      ["function "++concat [n++"_"|n<-nm]++(name o)++"($id=null"
>                                 ++  (concat [", $"++(name a)++"=array()" | a<-attributes o])
>                                 ++"){"
>      ,"    $this->id=$id;"]
>      ++ ["    $this->"++(name a)++"=$"++(name a)++";"| a <- attributes o] ++
>      ["}"]
>      ++ (concat
>         [ ["function add_"++(name a)++"("++concat [n++"_"|n<-nm++[name o]]++(name a)++" $"++(name a)++"){"
>           ,"  return $this->"++(name a)++"[]=$"++(name a)++";"
>           ,"}"
>           ,"function read_"++(name a)++"($id){"
>           ,"  $obj = new "++concat [n++"_"|n<-nm++[name o]]++(name a)++"($id" ++ (concat [", array()" | as<-attributes a]) ++ ");"
>           ] ++ concat [ [ "  $ctx = DB_doquer('"++ (selectExprForAttr context as a "$id") ++"');"
>                         , "  foreach($ctx as $i=>$v){"
>                         , "    $obj->read_"++name as++"($v['" ++ sqlExprTrg (ctx as) ++ "']);"
>                         , "  }"
>                         ]
>                       | as <-attributes a
>                       ] ++
>           ["  $this->add_"++(name a)++"($obj);"
>           ,"  return $obj;"
>           ,"}"
>           ,"function getEach_"++(name a)++"(){"
>           ,"  // currently, this returns all concepts.. why not let it return only the valid ones?"
>           ,"  $v = DB_doquer('"++(selectExpr context
>                                          30
>                                          (sqlAttConcept context (concept a))
>                                          (sqlAttConcept context (concept a))
>                                          (Tm (I [] (concept a) (concept a) True))
>                                      )++"');"
>           ,"  $res = array();"
>           ,"  foreach($v as $i=>$j){"
>           ,"    $res[]=$j['"++addslashes (sqlAttConcept context (concept a))++"'];"
>           ,"  }"
>           ,"  return $res;"
>           ,"}"
>           ]
>         | a <- attributes o
>         ]
>         )++
>      ["function addGen($type,$value){"
>      ]++ [ "  if($type=='"++(name a)++"') return $this->add_"++(name a)++"($value);"
>          | a <- attributes o
>          ] ++
>      ["  else return false;"|length (attributes o) > 0] ++
>      ["}"
>      ,"function readGen($type,$value){"
>      ]++ [ "  if($type=='"++(name a)++"') return $this->read_"++(name a)++"($value);"
>          | a <- attributes o
>          ] ++
>      ["  else return false;"|length (attributes o) > 0] ++
>      ["}"
>      ]
>      )) ++
>     [ "}"
>     ] ++ (concat [ showClasses context (nm++[name o]) a |a <- attributes o ] )


>  getObject context o | null (attributes o) = 
>   [ "new object(\""++(name o)++"\", array()"++mystr (objectOfConcept context (concept o))++")"
>   ]
>  getObject context o =
>   [ "new object(\""++(name o)++"\", array"
>   ]
>   ++ (concat(mapHeadTail  (mapHeadTail ((++) "   ( ")
>                                        ((++) "     "))
>                           (mapHeadTail ((++) "   , ")
>                                        ((++) "     "))
>                           [ concat
>                              [["new oRef( new oMulti( " ++ phpString (Inj `elem` m) ++ ","
>                                                         ++ phpString (Uni `elem` m) ++ ","
>                                                         ++ phpString (Sur `elem` m) ++ ","
>                                                         ++ phpString (Tot `elem` m) ++ " ) // derived from "++(showADL (ctx a))
>                              ], (mapHeadTail ((++) "  , ") ((++) "   ") (getObject context a))
>                               , ["  ) "]]
>                           | a <- attributes o, m <- [multiplicities (ctx a)]
>                           ]
>      )       )++["   )"++mystr (objectOfConcept context (concept o))++")"]

>  mapTail f (a:as) = a:(map f as)
>  mapHead f (a:as) = (f a):as
>  addFstLst f1 f2 (a:as) = (f1++a):(addLst f2 as)
>  addLst f (a:[]) = [a++f]
>  addLst f (a:as) = a: addLst f as
>  mapHeadTail f1 f2 (a:as) = (f1 a):(map f2 as)
>  mystr Nothing  = ""
>  mystr (Just o) = ", \""++(name o)++".php\""
>  phpString b = if b then "true" else "false"

Wat doet addLst?

  addLst [8] [[5], [6], [7]]
=
  [5]: addLst [8] [[6], [7]]
=
  [5]: [6]: addLst [8] [[7]]
=
  [5]: [6]: [[7]++[8]]
=
  [[5], [6], [7,8]]

Hypothese addLst ls lss = init lss++[last lss++ls]

