<?php
error_reporting(E_ALL ^ E_DEPRECATED);
ini_set("display_errors", 1);

require __DIR__ . '/../Generics.php';
require_once __DIR__ . '/DatabaseUtils.php';
require_once __DIR__ . '/InstallMysqlProcedures.php';
require_once __DIR__ . '/../pluginsettings.php'; // configuration for ExecEngine and plugins
require_once __DIR__ . '/loadplugins.php';

initSession();

// This module handles four requests: 
//
//     Database.php?resetSession
//     Database.php?getTimestamp
//     Database.php?testRule=..
//     Database.php?commands=..

if (!isset($execEngineSays)) // set in 'pluginsettings.php'
  $execEngineSays = true; // When 'true' the ExecEngine provides high level logging
if (!isset($execEngineWhispers)) // set in 'pluginsettings.php'
  $execEngineWhispers = false; // When 'true', the ExecEngine provides details when logging.

$selectedRoleNr = isset($_REQUEST['role']) ? $_REQUEST['role'] : -1; // role=-1 (or not specified) means no role is selected

if (isset($_REQUEST['resetSession'])) {
  resetSession();
} else if (isset($_REQUEST['getTimestamp'])) {
  timestampHtml();
} else if (isset($_REQUEST['testRule'])) {
  testRule($_REQUEST['testRule']);
} else if (isset($_REQUEST['getPopulationADL']) ) {
  showPopulationADL();
} else if (isset($_REQUEST['ip']) ) {
  echo $_SERVER['SERVER_ADDR'];
} else if (isset($_REQUEST['commands'])) {
  echo '<div id="UpdateResults">';
  
  if ($_REQUEST['interface']) {
    $interface = urldecode($_REQUEST['interface']);
  } else {
    error("Parameter 'interface' not present in POST request");
  }
  
  dbStartTransaction();
  
  processCommands(); // update database according to edit commands
    
  $conjunctViolationCache = array (); // array of arrays of violations, indexed by conjunct id, for caching conjuncts evaluated during rule checking/reporting
  // Haskell(ish) type: $conjunctViolationCache :: [ (ConjuncId, [(Src, Tgt)]) ]
  
  echo '<div id="InvariantRuleResults">';
  $invariantRulesHold = checkInvariants($interface, $conjunctViolationCache);
  echo '</div>';
  
  // updateSignals is separate from checkInvariants, because we might not want to update signals when invariants fail
  // (in which case, updateSignals would be called after 'if ($invariantRulesHold)' below)
  updateSignals($interface, $conjunctViolationCache);
  echo '<div id="ProcessRuleResults">';
  reportSignals($selectedRoleNr, $conjunctViolationCache);
  echo '</div>';

  if ($invariantRulesHold) {
    setTimeStamp();
    dbCommitTransaction();
  } else {
    dbRollbackTransaction();
  }
  echo '</div>';
}

function processCommands()
{ $commandsJson = $_POST['commands']; 
  if (isset($commandsJson))
    processCommandsJson($commandsJson);
}

function processCommandsJson($commandsJson)
{ $commandArray = json_decode($commandsJson);
    foreach ($commandArray as $command) processCommand($command);
}

function processCommand($command) {
  if (!isset($command->dbCmd))
    error("Malformed command, missing 'dbCmd'");
  switch ($command->dbCmd) {
    case 'addToConcept':
      if (array_key_exists('atom', $command) && array_key_exists('concept', $command))
        editAddToConcept($command->atom, $command->concept);
      else
        error("Command $command->dbCmd is missing parameters");
      break;
    case 'update':
      if (array_key_exists('relation', $command) && array_key_exists('isFlipped', $command) &&
          array_key_exists('parentAtom', $command) && array_key_exists('parentConcept', $command) &&
          array_key_exists('childAtom', $command) && array_key_exists('childConcept', $command) &&
          array_key_exists('parentOrChild', $command) && array_key_exists('originalAtom', $command))
        editUpdate($command->relation, $command->isFlipped, $command->parentAtom, $command->parentConcept,
                   $command->childAtom, $command->childConcept, $command->parentOrChild, $command->originalAtom);
      else
        error("Command $command->dbCmd is missing parameters");
      break;
    case 'delete':
      if (array_key_exists('relation', $command) && array_key_exists('isFlipped', $command) &&
          array_key_exists('parentAtom', $command) && array_key_exists('childAtom', $command))
        editDelete($command->relation, $command->isFlipped, $command->parentAtom, $command->childAtom);
      else
        error("Command $command->dbCmd is missing parameters");
      break;
    default :
      error("Unknown command '$command->dbCmd'");
  }
}

function editAddToConcept($atom, $concept) {
  emitLog("editAddToConcept($atom, $concept)");
  addAtomToConcept($atom, $concept, true);
}

// NOTE: if $originalAtom == '', editUpdate means insert
function editUpdate($rel, $isFlipped, $parentAtom, $parentConcept, $childAtom, $childConcept, $parentOrChild, $originalAtom) {
  global $allRelations;
  global $tableColumnInfo;
  
  emitLog("editUpdate($rel, " . ($isFlipped ? 'true' : 'false') . ", $parentAtom, $childAtom, $parentOrChild, $originalAtom)");
  /* There seems to be a bug in 'editUpdate', nl. when a $relation occurs multiple times as KEY in the relationTableInfo (which we have seen happening when you overload an (Ampersand) relation (name). The following code may be used to find the right entry in the relationTableInfo, but that is not used by 'editUpdate'.
  // check if $relation appears in $allRelations
  if (array_key_exists($relation, $allRelations))
  { foreach($allRelations as $key => $arr)
     if($key == $relation)
     { if($arr['srcConcept'] == $srcConcept && $arr['tgtConcept'] == $tgtConcept)
        { $table = $arr['table'];
        $srcCol = $arr['srcCol'];
           $tgtCol = $arr['tgtCol'];
           echo "<br>[FOUND: table=$table, srcCol=$srcCol, tgtCol=$tgtCol]";
       }
     }
  } else
  { echo "ERROR: Relation $relation does not exist (in table info)";
  }
*/
  $table = $allRelations[$rel]['table'];
  $srcCol = $allRelations[$rel]['srcCol'];
  $tgtCol = $allRelations[$rel]['tgtCol'];
  $parentCol = $isFlipped ? $tgtCol : $srcCol;
  $childCol = $isFlipped ? $srcCol : $tgtCol;
  
  $stableConcept = $parentOrChild == 'parent' ? $childConcept : $parentConcept;
  $modifiedConcept = $parentOrChild == 'parent' ? $parentConcept : $childConcept;
  $modifiedCol = $parentOrChild == 'parent' ? $parentCol : $childCol;
  $modifiedAtom = $parentOrChild == 'parent' ? $parentAtom : $childAtom;
  $stableCol = $parentOrChild == 'parent' ? $childCol : $parentCol;
  $stableAtom = $parentOrChild == 'parent' ? $childAtom : $parentAtom;
  
  $tableEsc = escapeSQL($table);
  $modifiedColEsc = escapeSQL($modifiedCol);
  $stableColEsc = escapeSQL($stableCol);
  $modifiedAtomEsc = escapeSQL($modifiedAtom);
  $stableAtomEsc = escapeSQL($stableAtom);
  $originalAtomEsc = escapeSQL($originalAtom);
  
  // ensure that the $modifiedAtom is in the concept tables for $modifiedConcept
  addAtomToConcept($modifiedAtom, $modifiedConcept, true);
  // TODO: errors here are not reported correctly
  
  // only if the stable column is unique, we do an update
  // TODO: maybe we can do updates also in non-unique columns
//  emitLog('table ' . $table . ' col ' . $stableCol . ' ' . $tableColumnInfo[$table][$stableCol]['unique']);
  if ($tableColumnInfo[$table][$stableCol]['unique']) { // note: this uniqueness is not set as an SQL table attribute
    $query = "UPDATE `$tableEsc` SET `$modifiedColEsc`='$modifiedAtomEsc' WHERE `$stableColEsc`='$stableAtomEsc'";
    emitLog($query);
    queryDb($query);
  } elseif ($tableColumnInfo[$table][$modifiedCol]['unique']) { // todo: is this ok? no, we'd also have to delete stableAtom originalAtom and check if modified atom even exists, otherwise we need an insert, not an update.
    $query = "UPDATE `$tableEsc` SET `$stableColEsc`='$stableAtomEsc' WHERE `$modifiedColEsc`='$modifiedAtomEsc'";
    emitLog($query);
    queryDb($query);
  } else {
    if ($originalAtom != '') { // delete only if there was an $originalAtom 
      $query = "DELETE FROM `$tableEsc` WHERE `$stableColEsc`='$stableAtomEsc' AND `$modifiedColEsc`='$originalAtomEsc';";
      emitLog($query);
      queryDb($query);
    }
    
    //$stableSuperColsEsc   = array_map(escapeSQL, getSuperColumns($table, $stableConcept  ));
    //$modifiedSuperColsEsc = array_map(escapeSQL, getSuperColumns($table, $modifiedConcept));
    //emitLog('$stableSuperColsEsc: '.var_export($stableSuperColsEsc, true));
    //emitLog('$modifiedSuperColsEsc: '.var_export($modifiedSuperColsEsc, true));
    
    $query = "INSERT INTO `$tableEsc` (`$stableColEsc`, `$modifiedColEsc`) VALUES ('$stableAtomEsc', '$modifiedAtomEsc')";
    emitLog($query);
    queryDb($query);
  }
}

function getSuperColumns($table, $concept) {
  global $tableColumnInfo;
  
  // won't work. there is not enough info in generics.php to determine the appropriate super columns
  // (if the concept of a column is a superconcept of $concept, it may also be in one of the relation target fields instead of the kernel,
  // in which case we should not touch it)
  emitLog('Get super columns in table ' . $table . ' for concept ' . $concept);
  $tableInfo = $tableColumnInfo[$table];
  foreach ($tableInfo as $column => $fieldInfo) {
    emitLog('column: ' . $column . ' ');
  }
  
  return array ();
}

function editDelete($rel, $isFlipped, $parentAtom, $childAtom) {
  global $allRelations;
  global $tableColumnInfo;
  
  emitLog("editDelete($rel, " . ($isFlipped ? 'true' : 'false') . ", $parentAtom, $childAtom)");
  $srcAtom = $isFlipped ? $childAtom : $parentAtom;
  $tgtAtom = $isFlipped ? $parentAtom : $childAtom;
  
  $table = $allRelations[$rel]['table'];
  $srcCol = $allRelations[$rel]['srcCol'];
  $tgtCol = $allRelations[$rel]['tgtCol'];
  
  $tableEsc = escapeSQL($table);
  $srcAtomEsc = escapeSQL($srcAtom);
  $tgtAtomEsc = escapeSQL($tgtAtom);
  $srcColEsc = escapeSQL($srcCol);
  $tgtColEsc = escapeSQL($tgtCol);
  
  if ($tableColumnInfo[$table][$tgtCol]['null']) // note: this uniqueness is not set as an SQL table attribute
    $query = "UPDATE `$tableEsc` SET `$tgtColEsc`=NULL WHERE `$srcColEsc`='$srcAtomEsc' AND `$tgtColEsc`='$tgtAtomEsc';";
  else
    $query = "DELETE FROM `$tableEsc` WHERE `$srcColEsc`='$srcAtomEsc' AND `$tgtColEsc`='$tgtAtomEsc';";
  
  emitLog($query);
  queryDb($query);
}

// new function
function runAllProcedures() {
  $query = "CALL AllProcedures";
  emitLog($query);
  queryDb($query);
}




//// TODO: rule-checking code should move to a different module (e.g. Eval.php) but is kept here for now to allow easy access
//         to the history while fixing the exec engine functionality.



// TODO: add ExecEngine support
function checkInvariants($interface, &$conjunctViolationCache) {
  global $allInterfaceObjects;
  global $allRoles;
  global $allRules;
  global $allConjuncts;

  $invConjunctIds = $allInterfaceObjects[$interface]['invConjunctIds'];
  //emitLog("Checking invariant rules for interface ".$interface);
  //emitLog("Corresponding conjuncts: ".print_r($conjunctIds, true));

  $violationsPerRule = computeAllViolationsPerRule($invConjunctIds, $conjunctViolationCache);
  
  // Report violations for each rule
  foreach ($violationsPerRule as $ruleName => $violations) {
    $rule = $allRules[$ruleName];
    emitAmpersandLog( brokenRuleMessage($rule) );
    foreach ( violationMessages($roleNr, $rule, $violations) as $msg )
      emitAmpersandLog( $msg );
  }

  return count($violationsPerRule) == 0;
}

function computeAllViolationsPerRule($invConjunctIds, &$conjunctViolationCache) {
  global $allConjuncts;

  $violationsPerRule = array (); // will contain all violations, indexed by rule name
  foreach ($invConjunctIds as $conjunctId) {
    // evaluate each conjunct that and store violations in $violationsPerRule

    $conjunct = $allConjuncts[$conjunctId];
    $ruleNames = $conjunct['invariantRuleNames'];
    $ruleNamesStr = "invariants: [".join(",", $ruleNames)."]";
    
    $violationsSQL = $conjunct['violationsSQL'];
    $error = '';
    emitLog("SQL eval conjunct $conjunctId (for $ruleNamesStr)");
    $conjunctViolations = DB_doquerErr($violationsSQL, $error); // execute violationsSQL to check for violations
    if ($error)
      error("While evaluating conjunct $conjunctId ($ruleNamesStr):\n" . $error);
    $conjunctViolationCache[$conjunctId] = $conjunctViolations;
    // cache violations so we don't need to re-evaluate on updating signal tables
    // NOTE: since we loop over the conjuncts rather than the invariants, there is no need to
    //       use the cache within the invariant checking (no evaluated conjuncts will be encountered)
    
    if (count($conjunctViolations) == 0) {
      emitLog("Conjunct $conjunctId ($ruleNamesStr) holds"); // log successful conjunct validation
    } else {
      emitLog("Conjunct $conjunctId ($ruleNamesStr) is broken");
    
      // store this conjunct's violations for its originating rules in $violationsPerRule
      foreach($ruleNames as $ruleName) { 
        $rule = $allRules[$ruleName];    
        if (!$violationsPerRule[ $ruleName ])
          $violationsPerRule[ $ruleName ] = array ();
    
        $violationsPerRule[$ruleName] = array_merge( $violationsPerRule[ $ruleName ], $conjunctViolations);
      }
    }
  }
  
  return $violationsPerRule;
}

// TODO: add ExecEngine support
function updateSignals($interface, $conjunctViolationCache) {
  // $conjunctViolationCache contains violations for already evaluated conjuncts (during invariant checking)
  // if updateSignals is only called on succesful invariant checking, the cached conjuncts will always have 0 violations.
  // Since any SQL evaluation is kept at the MySQL server by INSERTing it immediately, the cache is not modified here
  // and $conjunctViolationCache is not a reference parameter.
  
  global $signalTableName;
  global $allInterfaceObjects;
  global $allRules;
  global $allConjuncts;

  $sigConjunctIds = $allInterfaceObjects[$interface]['sigConjunctIds'];
  //emitLog("Checking signals for interface '$interface'");
  //emitLog("Conjuncts: [".join(',',$sigConjunctIds)."]");
  
  // Remove all signal conjunct violations for this interface from the signal table
  queryDb("DELETE FROM `$signalTableName` ".mkWhereDisjunction($sigConjunctIds));

  $signalTableRows = array ();
  foreach ($sigConjunctIds as $conjunctId) {
    $conjunct = $allConjuncts[$conjunctId];
    $ruleNames = $conjunct['signalRuleNames'];
    
    //emitLog('Checking conjunct: ' . $conjunctId . ', signal table: ' . $signalTableName);
    //emitLog("Coming from (signals: [".join(",", $ruleNames)."])");

    $evaluatedConjunct = $conjunctViolationCache[$conjunctId];
    if (isset($evaluatedConjunct)) { // the conjunct has already been evaluated
      emitLog("update: Cached SQL eval conjunct: $conjunctId");

      $conjunctViolationRows = array_map(function($violation) use ($conjunctId){
        return array('conjId' => $conjunctId, 'src' => escapeSQL($violation['src']), 'tgt' => escapeSQL($violation['tgt']));
      }, $evaluatedConjunct);
      $signalTableRows = array_merge($signalTableRows, $conjunctViolationRows);
      //emitLog('Rows: '.print_r($conjunctViolationRows, true));

    } else {
      // Compute and insert the new violations.
      $violationsSQL = $conjunct['violationsSQL'];        
      emitLog("SQL local eval signal conjunct $conjunctId");
      $query = "INSERT INTO `$signalTableName`"
             . " SELECT '$conjunctId' AS conjId, violations.src, violations.tgt"
             . " FROM ($violationsSQL) AS violations";
      //emitLog($query);
      queryDb($query);
    }    
  }
  
  if (count($signalTableRows) > 0 ) { // only insert when violations>0 (sql doesn't handle empty lists elegantly)
    $valueTuples =array_map(function($row) {
      return "('".$row['conjId']."','".$row['src']."','".$row['tgt']."')";
    }, $signalTableRows);
    $query = "INSERT INTO `$signalTableName` (conjId,src,tgt) VALUES ". implode(',', $valueTuples);
    emitLog($query);
    queryDb($query);
  }
}

function reportSignals($roleNr, $conjunctViolationCache = array()) {
  // $conjunctViolationCache contains violations for already evaluated conjuncts (during invariant checking)
  // if reportSignals is only called on succesful invariant checking, the cached conjuncts will always have 0 violations.
  
  global $signalTableName;
  global $allRoles;
  global $allRules;
  $allRoleRules = array ();
  //emitAmpersandLog('$conjunctViolationCache = '.print_r($conjunctViolationCache,true));
  
  // Compute $allRoleRules (the process rules that need to be reported to this role)
  if ($roleNr == -1) { // if no role is selected, evaluate the rules for all roles
    for ($r = 0; $r < count($allRoles); $r++) { 
      if ($allRoles[$r]['name'] != 'DATABASE') { // filter rules for role 'DATABASE', these will be handled by runAllProcedures() 
        $allRoleRules = array_merge((array)$allRoleRules, $allRoles[$r]['ruleNames']); // merge process rules of all roles
      }
    }
    $allRoleRules = array_unique((array)$allRoleRules); // remove duplicate ruleNames
  } else {
    $role = $allRoles[$roleNr];
    $allRoleRules = $role['ruleNames'];
  } 
  //emitAmpersandLog('$allRoleRules: '.print_r($allRoleRules,true));
  
  // Determine which conjunctIds need to be looked up in the SQL signal table
  $lookupConjunctIds = array ();
  foreach ($allRoleRules as $ruleName) {
    //emitAmpersandLog("Rule: $ruleName");
    $rule = $allRules[$ruleName];
    if (!$rule)
      error("Rule \"$ruleName\" does not exist.");
    
    foreach ($rule['conjunctIds'] as $conjunctId) {
      if ($conjunctViolationCache[$conjunctId]) {
        //emitAmpersandLog("report: Cached SQL eval conjunct: $conjunctId");
      } else { // the conjunct is not in the cache, so we look it up in the SQL signal table
        //emitAmpersandLog("report: SQL lookup queued for conjunct $conjunctId (for signal $ruleName)");
        $lookupConjunctIds[] = $conjunctId;
      }
    }
  }
  $lookupConjunctIds = array_unique($lookupConjunctIds); // Remove duplicates
  foreach ($lookupConjunctIds as $conjunctId) {          // Insert empty arrays in cache, in case sql does not return violations for the conjunct
    $conjunctViolationCache[$conjunctId] = array ();
  }
  //emitAmpersandLog('-conjunct id: '.$conjunctId.' table: '.$signalTableName);
  $query = "SELECT conjId, src,tgt FROM `$signalTableName` ".mkWhereDisjunction($lookupConjunctIds);
  //emitAmpersandLog('Conjunct lookup on conjuncts: ['.join(',',$lookupConjunctIds).']');
  //emitAmpersandLog('Query: '.$query);
  $signalTableRows = queryDb($query); // query all non-cached signal conjuncts
  
  foreach ($signalTableRows as $signalTableRow) { // and add them to the cache
    $conjunctViolationCache[$signalTableRow['conjId']][] = array ('src' => $signalTableRow['src'], 'tgt' => $signalTableRow['tgt']);
  }
  
  //emitAmpersandLog('$conjunctViolationCache = '.print_r($conjunctViolationCache,true));

  // Iterate over the process rules again to report violations per rule
  foreach ($allRoleRules as $ruleName) {
    //emitAmpersandLog("Rule: $ruleName");
    $rule = $allRules[$ruleName];
    
    //emitLog('reporting signal: '.$ruleName);
    $ruleViolations = array ();
    
    foreach ($rule['conjunctIds'] as $conjunctId) {
      //emitAmpersandLog("Reporting conjunct $conjunctId");
      $ruleViolations = array_merge($ruleViolations, $conjunctViolationCache[$conjunctId]);
      //emitAmpersandLog("done");
    }
          
    if (count($ruleViolations) > 0) {  
      emitAmpersandLog( brokenRuleMessage($rule) );
      foreach ( violationMessages($roleNr, $rule, $ruleViolations) as $msg )
        emitAmpersandLog( $msg );
    }
  }
}

// returns "WHERE conjId = $conjunctIds[0] OR .. OR conjId = $conjunctIds[n-1]" 
function mkWhereDisjunction($conjunctIds) {
  if (count($conjunctIds) > 0) {
    return 'WHERE '.implode(' OR ', array_map( function($conjunctId) {return "conjId = '$conjunctId'";}, $conjunctIds));
  } else {
    return '';
  }
}

function brokenRuleMessage($rule) {
  // if the rule has an associated message, we show that instead of the name and the meaning
  return $rule['message'] ? $rule['message'] : "Rule '$rule[name]' is broken: $rule[meaning]";
}

function violationMessages($roleNr, $rule, $violations) {
  $srcNrOfIfcs = getNrOfInterfaces($rule['srcConcept'], $roleNr);
  $tgtNrOfIfcs = getNrOfInterfaces($rule['tgtConcept'], $roleNr);
  
  $pairView = $rule['pairView']; // pairView contains an array with the fragments of the violations message (if specified)
  
  $msgs = array ();
  
  $violationsNoDups =  array_map("unserialize", array_unique(array_map("serialize", $violations)));
  // Not the most elegant way to remove duplicates, but then again, this is php.
  
  foreach ($violationsNoDups as $violation) {
    $pair = showPair($violation['src'], $rule['srcConcept'], $srcNrOfIfcs, $violation['tgt'], $rule['tgtConcept'], $tgtNrOfIfcs, $pairView);
    array_push($msgs, '- ' . $pair);
  }
  return $msgs;
}

// Numbering transactions allows optimization of ExecEngine rules, e.g. transitive closure computations.
function dbStartTransaction() {
  emitLog('START TRANSACTION');
  queryDb('START TRANSACTION');
}

function dbCommitTransaction() {
  emitLog('COMMIT');
  queryDb('COMMIT');
}

function dbRollbackTransaction() {
  emitLog('ROLLBACK');
  queryDb('ROLLBACK');
}

function queryDb($querySql) {
  $result = DB_doquerErr($querySql, $error);
  if ($error)
    error($error);
  
  return $result;
}

function ExecEngineWhispers($msg) {
  global $execEngineWhispers; // set in 'pluginsettings.php'
  global $execEngineSays; // set in 'pluginsettings.php'
  if ($execEngineWhispers && $execEngineSays)
    echo "<div class=\"LogItem AmpersandErr\">$msg</div>";
}

function ExecEngineSays($msg) {
  global $execEngineSays; // set in 'pluginsettings.php'
  if ($execEngineSays)
    echo "<div class=\"LogItem AmpersandErr\"><i>$msg</i></div>";
}

function ExecEngineSHOUTS($msg) {
  echo "<div class=\"LogItem AmpersandErr\" style=\"color:red\"><b>$msg</b></div>";
}

function emitAmpersandLog($msg) {
  echo "<div class=\"LogItem AmpersandErr\">$msg</div>\n";
}

function emitLog($msg) {
  echo "<div class=\"LogItem LogMsg\">$msg</div>\n";
}

function error($err) {
  die("<div class=\"LogItem Error\">Error in Database.php: $err</div>");
} // because of this die, the top-level div is not closed, but that's better than continuing in an erroneous situtation
  // the current php session is broken off, which corresponds to a rollback. (doing an explicit roll back here is awkward
  // since it may trigger an error again, causing a loop)
  
function testRule($ruleName) {
  global $isDev;
  global $allRules;
  global $allConjuncts;
  
  if (!$isDev) {
    echo "<span style=\"color: red\">Rule test unavailable: prototype was not generated with <tt>--dev</tt> option.</span>";
    return;
  }
  if (!$allRules[$ruleName]) {
    echo "<span style=\"color: red\">Error: rule \"$ruleName\" does not exist.</span>";
    return;
  }
  
  echo "<a href=\"../Installer.php\" style=\"float:right\">Reset database</a>";
  echo "<h2>Testing rule $ruleName</h2>";
  $rule = $allRules[$ruleName];
  $ruleAdl = escapeHtmlAttrStr($rule['ruleAdl']);
  echo "<b>ADL:</b>&nbsp;<tt style=\"color:blue\">$ruleAdl</tt></br>";
  echo "<b>Conjunct ids:</b> [".join(",", $rule['conjunctIds'])."]";
  echo "<h3>Rule SQL</h3><pre>$rule[contentsSQL]</pre><h4>results:</h4>";


  $rows = queryDb($rule['contentsSQL']);
  printBinaryTable($rows);
    
  foreach ($rule['conjunctIds'] as $conjunctId) {
    $conjunct = $allConjuncts[$conjunctId];
    echo "<h3>Violation SQL conjunct $conjunctId</h3><pre>$conjunct[violationsSQL]</pre><h4>Conjunct violations:</h4>";
    $rows = queryDb($conjunct['violationsSQL']);
    printBinaryTable($rows);
  }
}

function timestampHtml() {
  $timestamp = getTimestamp($error);
  if ($error) // Show error if there is one. If there is a problem, we will be able to trace it in the browser network log.
    echo "SQL error while fetching timestamp:\n".$error."\n";
  echo "<div class=Result timestamp='$timestamp'>$timestamp</div>";
}

function showPopulationADL() {
  echo getPopulationADL();
}
?>
