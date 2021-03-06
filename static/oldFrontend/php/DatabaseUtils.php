<?php
require __DIR__ . '/../dbSettings.php';
// We need the __DIR__ because all require statements are relative to the path of the browser-requested php file.
// Otherwise, when DatabaseUtils is included by Interface.php, we would need 'dbSettings.php', but when included
// by php/Database.php, we would need '../dbSettings.php'.

global $DB_host;
global $DB_user;
global $DB_pass;
global $dbName;

$DB_link = mysqli_connect($DB_host, $DB_user, $DB_pass, $dbName);

// Check connection
if (mysqli_connect_errno()) {
  die( "Failed to connect to MySQL.\n" 
     . "<br/><br/><span style=\"color: red\"><b>Error while connecting to MySQL:</b></span> " 
     . mysqli_connect_error() 
     . "<br/>The database may not have been initialized yet. (<a href=\"Installer.php\">Initialize database</a>)<br/>"
     );
}
// Set sql_mode to ANSI
DB_doquer("SET SESSION sql_mode = 'ANSI'");

// let PHP also report undefined variable references
function terminate_missing_variables($errno, $errstr, $errfile, $errline) {
  if (($errno == E_NOTICE) and (strstr($errstr, "Undefined variable")))
    echo ("$errstr in $errfile line $errline");
  
  return false; // Let the PHP error handler handle all the rest
}
set_error_handler("terminate_missing_variables");

// Sessions

define("EXPIRATION_TIME", 60 * 60); // expiration time in seconds

function initSession() {
  // when using $_SESSION, we get a nonsense warning if not declared global, however here
  // we only do isset, so no need for global
  global $allConcepts;
  
  session_start(); // Start a new, or resume the existing, PHP session
  
  // only execute session code when concept SESSION is used by adl script
  if (isset($allConcepts['SESSION'])) { 
    // TODO: until error handling is improved, this hack tries a dummy query and returns silently if it fails.
    // This way, errors during initSession do not prevent the reset-database link from being visible.
    DB_doquerErr("SELECT * FROM `__SessionTimeout__` WHERE false", $error);
    if ($error)
      return;
      
      // Remove expired Ampersand-sessions from __SessionTimeout__ and all concept tables and relations where it appears.
    $expirationLimit = time() - EXPIRATION_TIME;
    $expiredSessions = firstCol(DB_doquer("SELECT SESSION FROM `__SessionTimeout__` WHERE lastAccess < $expirationLimit;"));
    foreach ($expiredSessions as $expiredSessionAtom)
      deleteSession($expiredSessionAtom);
          
    // Create a new session if sessionAtom in php _SESSION is not set (browser started a new session)
    // or sessionAtom is not in SESSIONS (previous session expired)
    if (!isset($_SESSION['sessionAtom']) || !isAtomInConcept($_SESSION['sessionAtom'], 'SESSION')) {
      $sessionAtom = mkUniqueAtomByTime('SESSION');
      $_SESSION['sessionAtom'] = $sessionAtom;
      addAtomToConcept($sessionAtom, 'SESSION', false);
    } else {
      $sessionAtom = $_SESSION['sessionAtom'];
    }
    // echo "sessionAtom = [$sessionAtom]<br>";
    
    $timeInSeconds = time();
    DB_doquer( "INSERT INTO `__SessionTimeout__` (`SESSION`,`lastAccess`) VALUES ('$_SESSION[sessionAtom]','$timeInSeconds')" 
             . "ON DUPLICATE KEY UPDATE `lastAccess` = '$timeInSeconds'");
    // echo "SessionAtom is $sessionAtom access is $timeInSeconds";
  }
}

function resetSession() {
  global $allConcepts;
  
  if ($allConcepts['SESSION']) { // only execute session code when concept SESSION is used by adl script
    deleteSession($_SESSION['sessionAtom']);
  }
}

function deleteSession($sessionAtom) { // echo "deleting $sessionAtom<br/>";
  DB_doquer("DELETE FROM `__SessionTimeout__` WHERE SESSION = '$sessionAtom';");
  deleteAtom($sessionAtom, 'SESSION');
}

// Queries
function DB_doquer($quer) {
  $result = DB_doquerErr($quer, $error);
  
  if ($error)
    die("<div class=InternalError>$error</div>");
  return $result;
}

function DB_doquerErr($quer, &$error) {
  global $_SESSION; // when using $_SESSION, we get a nonsense warning if not declared global
  global $DB_link;
  global $DB_errs;
  
  // Replace the special atom value _SESSION by the current sessionAtom
  // NOTE: we only replace if the query contains _SESSION, otherwise the initialization DB_doquerErr calls will yield warnings.
  $quer = strpos($quer, '_SESSION') !== FALSE ? str_replace("_SESSION", $_SESSION['sessionAtom'], $quer) : $quer;

  $result = mysqli_query($DB_link, $quer);
  if (!$result) {
    $error = 'Error ' . ($ernr = mysqli_errno($DB_link)) . ' in query "' . $quer . '": ' . mysqli_error($DB_link);
    return false;
  }
  if ($result === true)
    return true; // success.. but no contents..
  $rows = Array ();
  while ($row = mysqli_fetch_array($result)) {
    $rows[] = $row;
    unset($row);
  }
  return $rows;
}

function getSpecializations($concept) {
  global $allSpecializations;
  
  return isset($allSpecializations[$concept]) ? $allSpecializations[$concept] : array ();
}

function getView($concept) {
  global $allViews;
  
  foreach ($allViews as $view)
    if ($concept == $view['concept'] || in_array($concept, getSpecializations($view['concept'])))
      return $view;
  
  return null;
}

function showViewAtom($atom, $concept) {
  $viewDef = getView($concept);
  
  if (!$viewDef || $atom == '') {
    return $atom;
  } else {
    $viewStrs = array ();
    foreach ($viewDef['segments'] as $viewSegment)
      if ($viewSegment['segmentType'] == 'Text')
        $viewStrs[] = htmlSpecialChars($viewSegment['Text']);
      elseif ($viewSegment['segmentType'] == 'Html')
        $viewStrs[] = $viewSegment['Html'];
      else {
        if ($viewSegment['expSQL'] == "")
          ExecEngineSHOUTS("showViewAtom($atom, $concept)");
        $r = getCoDomainAtoms($atom, $viewSegment['expSQL']);
        $txt = count($r) ? $r[0] : "<View relation not total>";
        $viewStrs[] = htmlSpecialChars($txt);
        // this can happen in a create-new interface when the view fields have not yet been
        // filled out, while the atom is shown (but hidden by css) at the top.
      }
    return implode($viewStrs);
  }
}

function showPair($srcAtom, $srcConcept, $srcNrOfIfcs, $tgtAtom, $tgtConcept, $tgtNrOfIfcs, $pairView) {
  $srcHasInterfaces = $srcNrOfIfcs == 0 ? '' : ' hasInterface=' . ($srcNrOfIfcs == 1 ? 'single' : 'multiple');
  $tgtHasInterfaces = $tgtNrOfIfcs == 0 ? '' : ' hasInterface=' . ($tgtNrOfIfcs == 1 ? 'single' : 'multiple');
  
  if (count($pairView) == 0) {
    $source = showViewAtom($srcAtom, $srcConcept);
    $target = showViewAtom($tgtAtom, $tgtConcept);
    
    // if source and target are the same atom and we have a view for it, don't show a tuple
    if ($srcAtom == $tgtAtom && $srcConcept == $tgtConcept && getView($srcConcept))
      return "<span class=\"Pair\">" 
           .   "<span class=\"PairAtom\" atom=\"$srcAtom\" concept=\"$srcConcept\"$srcHasInterfaces>$source</span>"
           . "</span>";
    else
      return "<span class=\"Pair\">(" 
           .   "<span class=\"PairAtom\" atom=\"$srcAtom\" concept=\"$srcConcept\"$srcHasInterfaces>'$source'</span>"
           .   ", <span class=\"PairAtom\" atom=\"$tgtAtom\" concept=\"$tgtConcept\"$tgtHasInterfaces>'$target'</span>"
           . ")</span>";
  } else {
    $pairStrs = array (
        "<span class=\"Pair\">" );
    foreach ($pairView as $segment)
      if ($segment['segmentType'] == 'Text')
        $pairStrs[] = $segment['Text'];
      else {
        $atom = $segment['srcOrTgt'] == 'Src' ? $srcAtom : $tgtAtom;
        $concept = $segment['srcOrTgt'] == 'Src' ? $srcConcept : $tgtConcept;
        $hasInterfaces = $segment['srcOrTgt'] == 'Src' ? $srcHasInterfaces : $tgtHasInterfaces;
        if ($segment['expSQL'] == "")
          ExecEngineSHOUTS("showPair($srcAtom, $srcConcept, $srcNrOfIfcs, $tgtAtom, $tgtConcept, $tgtNrOfIfcs, $pairView)");
        $r = getCoDomainAtoms($atom, $segment['expSQL']);
        
        // we label all expressionsegments as violation source or target based on the source of their expression
        $pairStrs[] = "<span class=\"PairAtom\" atom=\"$atom\" concept=\"$concept\"$hasInterfaces>";
        $pairStrs[] = showViewAtom($r[0], $segment['expTgt']) . "</span>";
      }
    $pairStrs[] = "</span>";
    return implode($pairStrs);
  }
}

function execPair($srcAtom, $srcConcept, $tgtAtom, $tgtConcept, $pairView) {
  $pairStrs = array ();
  foreach ($pairView as $segment) {
    if ($segment['segmentType'] == 'Text') {
      $pairStrs[] = $segment['Text'];
    } else {
      $atom = $segment['srcOrTgt'] == 'Src' ? $srcAtom : $tgtAtom;
      $concept = $segment['srcOrTgt'] == 'Src' ? $srcConcept : $tgtConcept;
      if ($segment['expSQL'] == "")
        ExecEngineSHOUTS("execPair($srcAtom, $srcConcept, $tgtAtom, $tgtConcept, $pairView)");
      $r = getCoDomainAtoms($atom, $segment['expSQL']); // SRC of TGT kunnen door een expressie gevolgd worden
      $pairStrs[] = $r[0]; // Even er van uit gaan dat we maar 1 atoom kunnen behandelen...
    }
  }
  return implode($pairStrs);
}

// return an atom "Concept_<n>" that is not in $existingAtoms (make sure that $existingAtoms covers all concept tables)
function mkUniqueAtom($existingAtoms, $concept) {
  $generatedAtomNrs = array ();
  foreach (array_unique($existingAtoms) as $atom) {
    preg_match('/\A' . $concept . '\_(?P<number>[123456789]\d*)\z/', $atom, $matches);
    // don't match nrs with leading 0's since we don't generate those
    $generatedAtomNrs[] = $matches['number'];
  }
  
  $generatedAtomNrs = array_filter($generatedAtomNrs); // filter out all the non-numbers (which are null)
  sort($generatedAtomNrs);
  foreach ($generatedAtomNrs as $i => &$nr) {
    if ($nr != $i + 1) // as soon as $generatedAtomNrs[i] != i+1, we arrived at a gap in the sorted number sequence and we can use i+1
      return $concept . '_' . ($i + 1);
  }
  return $concept . '_' . (count($generatedAtomNrs) + 1);
}

function mkUniqueAtomByTime($concept) {
  $time = explode(' ', microTime()); // yields [seconds,microseconds] both in seconds, e.g. ["1322761879", "0.85629400"]
  return $concept . '_' . $time[1] . "_" . substr($time[0], 2, 6); // we drop the leading "0." and trailing "00" from the microseconds
}

function addAtomToConcept($newAtom, $concept, $shouldLog = false) { // Insert 'newAtom' only if it does not yet exist...
  global $allConcepts;
  
  if ($shouldLog)
    emitLog("adding to concept tables: $newAtom : $concept (" . count($allConcepts[$concept]['conceptTables']) . " columns)");
  foreach ($allConcepts[$concept]['conceptTables'] as $conceptTableCol) {
    // $allConcepts[$concept]['conceptTables'] is an array of tables with arrays of columns maintaining $concept.
    // (we have an array rather than a single column because of generalizations)
    $conceptTable = $conceptTableCol['table'];
    $conceptCols = $conceptTableCol['cols']; // We insert the new atom in each of them.

    $conceptTableEsc = escapeSQL($conceptTable);
    $newAtomEsc = escapeSQL($newAtom);
    
    // invariant: all concept tables (which are columns) are maintained properly, so we can query an arbitrary one for checking the existence of a concept
    $firstConceptColEsc = escapeSQL($conceptCols[0]);
    
    $existingAtoms = firstCol(DB_doquer("SELECT `$firstConceptColEsc` FROM `$conceptTableEsc`")); // no need to filter duplicates and NULLs

    if (!in_array($newAtom, $existingAtoms)) {
      $allConceptColsEsc = '`' . implode('`, `', $conceptCols) . '`';
      $newAtomsEsc = array_fill(0, count($conceptCols), $newAtomEsc);
      $allValuesEsc = "'" . implode("', '", $newAtomsEsc) . "'";
      
      $query = "INSERT INTO `$conceptTableEsc` ($allConceptColsEsc) VALUES ($allValuesEsc)";
      if ($shouldLog)
        emitLog($query);
      DB_doquer($query);
    }
  }
}

// Remove all occurrences of $atom in the database (all concept tables and all relations)
// In tables where the atom may not be null, the entire row is removed.
// TODO: If all relation fields in a wide table are null, the entire row could be deleted, but this doesn't
// happen now. As a result, relation queries may return some nulls, but these are filtered out anyway.
function deleteAtom($atom, $concept) {
  global $tableColumnInfo;
  
  foreach ($tableColumnInfo as $table => $tableInfo)
    foreach ($tableInfo as $column => $fieldInfo) {
      // TODO: could be optimized by doing one query per table. But deleting per column yields the same result.
      // (unlike adding)
      if ($fieldInfo['concept'] == $concept) {
        $tableEsc = escapeSQL($table);
        $columnEsc = escapeSQL($column);
        $atomEsc = escapeSQL($atom);
        
        if ($fieldInfo['null']) // if the field can be null, we set all occurrences to null
          $query = "UPDATE `$tableEsc` SET `$columnEsc`=NULL WHERE `$columnEsc`='$atomEsc';";
        else // otherwise, we remove the entire row for each occurrence
          $query = "DELETE FROM `$tableEsc` WHERE `$columnEsc` = '$atomEsc';";
          // echo $query;
        DB_doquer($query);
      }
    }
}

// Currently not used. Javascript creates a unique name and index.php adds to to the concept in a temporary transaction.
function createNewAtom($concept) {
  $newAtom = mkUniqueAtomByTime($concept);
  
  addAtomToConcept($newAtom, $concept, false);
  return $newAtom;
}

/* invariant: all concept tables (which are columns) are maintained properly, so we can query an arbitrary one to obtain the list of atoms */
function getAllConceptAtoms($concept) {
  global $allConcepts;
  
  $conceptTable = $allConcepts[$concept]['conceptTables'][0]['table']; // $allConcepts[$concept]['conceptTables'] is an array of tables with arrays of columns maintaining $concept
  $conceptCol = $allConcepts[$concept]['conceptTables'][0]['cols'][0]; // for lookup, we just take the first table and its first column
  $conceptTableEsc = escapeSQL($conceptTable);
  $conceptColEsc = escapeSQL($conceptCol);
  
  // need to do array_unique and array_filter, since concept table may contain duplicates and NULLs
  // TODO: more elegant to filter dups and nulls in SQL: ("SELECT DISTINCT `$conceptColEsc` FROM `$conceptTableEsc`  WHERE `$conceptColEsc` IS NOT NULL")
  return array_unique(array_filter(firstCol(DB_doquer("SELECT `$conceptColEsc` FROM `$conceptTableEsc`")),'notNull'));  
} 

function notNull($atom) { // need a type-based comparison, otherwise 0 is also null
  return $atom !== null;
}

function isAtomInConcept($atom, $concept) {
  return in_array($atom, getAllConceptAtoms($concept));
}

function getRelationContents($relationInfo) {
  global $allRelations;
  $table  = $relationInfo['table'];
  $srcCol = $relationInfo['srcCol'];
  $tgtCol = $relationInfo['tgtCol'];
  
  $tableEsc = escapeSQL($table);
  $srcColEsc = escapeSQL($srcCol);
  $tgtColEsc = escapeSQL($tgtCol);

  $query = "SELECT `$srcColEsc` as `src`, `$tgtColEsc` as `tgt` FROM `$tableEsc` WHERE `$srcColEsc` IS NOT NULL  AND  `$tgtColEsc` IS NOT NULL";
  $pairs = queryDb($query);
  return $pairs;
}


function isInterfaceForRole($interface, $roleNr) {
  return $roleNr == -1 || count($interface['interfaceRoles']) == 0 || in_array(getRoleName($roleNr), $interface['interfaceRoles']);
  // an interface is visible if: no role is selected; the interface does not specify roles; or the interface roles contain $role
}

function getTopLevelInterfacesForConcept($concept, $roleNr) {
  global $allInterfaceObjects;
  $interfacesForConcept = array ();
  foreach ($allInterfaceObjects as $interface) {
    if (  ($interface['srcConcept'] == $concept || in_array($concept, getSpecializations($interface['srcConcept']))) 
       && isInterfaceForRole($interface, $roleNr) )
      $interfacesForConcept[] = $interface;
  }
  return $interfacesForConcept;
}

function getNrOfInterfaces($concept, $roleNr) {
  return count(getTopLevelInterfacesForConcept($concept, $roleNr));
}


// Misc utils

function getRoleName($roleNr) {
  global $allRoles;
  
  return $roleNr == -1 ? 'Algemeen' : $allRoles[$roleNr]['name'];
}

function firstRow($rows) {
  return $rows[0];
}

function firstCol($rows) {
  foreach ($rows as $i => &$v)
    $v = $v[0];
  return $rows;
}

function targetCol($rows) {
  foreach ($rows as $i => &$v)
    $v = $v['tgt'];
  return $rows;
}

function getCoDomainAtoms($atom, $selectRel) {
  // ExecEngineWhispers(">> getCoDomainAtoms($atom, $selectRel)");
  return targetCol(DB_doquer(selectCoDomain($atom, $selectRel)));
}

function selectCoDomain($atom, $selectRel) {
  return 'SELECT DISTINCT `tgt` FROM (' . $selectRel . ') AS results WHERE src=\'' . escapeSQL($atom) . '\'';
}


// Timestamps

// return the most recent modification time for the database (only Ampersand edit operations are recorded)
function getTimestamp(&$error) {
  $timestampRow = DB_doquerErr("SELECT MAX(`Seconds`) FROM `__History__`", $error);
  
  if ($error)
    return '0';
  else
    return $timestampRow[0][0];
}

// set modification timestamp to the current time
function setTimestamp() {
  $time = explode(' ', microTime()); // yields [seconds,microseconds] both in seconds, e.g. ["1322761879", "0.85629400"]
  $microseconds = substr($time[0], 2,6); // we drop the leading "0." and trailing "00"  from the microseconds
  $seconds =$time[1].$microseconds;  
  date_default_timezone_set('Europe/Amsterdam');
  $date = date("j-M-Y, H:i:s.").$microseconds; 
  DB_doquer("INSERT INTO `__History__` (`Seconds`,`Date`) VALUES ('$seconds','$date')");
  // TODO: add error checking
}


// Dump population to ADL

function getPopulationADL() {
  global $dbName;
  global $contextName;
  global $versionInfo;
  global $allConcepts;
  global $allRelations;

  date_default_timezone_set('Europe/Amsterdam');
  $date = date("j-M-Y at H:i:s");
  $adl  = "CONTEXT {$contextName}_PopulationDump IN ENGLISH\n"
        . "-- Population dump for database '$dbName' (context: '$contextName') on $date\n"
        . "-- Generated by $versionInfo.\n\n";
  foreach (array_keys($allConcepts) as $concept) {
    if ($concept != "ONE") {       
      $conceptEsc = escapeAndQuote($concept);
      $adl .= "POPULATION $conceptEsc CONTAINS ".showAtomListADL(getAllConceptAtoms($concept))."\n";
    }
  }
  foreach ($allRelations as $relationInfo) {
    $srcEsc = escapeAndQuote($relationInfo[srcConcept]);
    $tgtEsc = escapeAndQuote($relationInfo[tgtConcept]);
    $adl .= "$relationInfo[name] :: $srcEsc * $tgtEsc = "
          . showPairListADL(getRelationContents($relationInfo))."\n";
  }
  $adl .= "ENDCONTEXT";
  echo $adl;
}

// ADL generation utils

function showPairListADL($pairs) {
  return '['. implode(';', array_map('showPairADL', $pairs)) .']';
}

function showPairADL($pair) {
  return '('.escapeAndQuote($pair['src']).','.escapeAndQuote($pair['tgt']).')';
}

function showAtomListADL($atoms) {
  return '['. implode(',', array_map('escapeAndQuote', $atoms)) .']';
} 

function escapeAndQuote($str) {
  return '"'.addslashes($str).'"';
}

// Html generation utils

function printBinaryTable($table) {
  echo '<table border=solid>';
  foreach ($table as $row)
    echo '<tr><td>' . $row['src'] . '&nbsp;</td><td>' . $row['tgt'] . '&nbsp;</td></tr>';
  echo '</table>';
}

function echoLn($str) {
  echo $str . '<br/>';
}

function emit(&$lines, $line) {
  $lines .= $line . "\n";
}

// for use in specifiying values for attributes to html elements (eg. <div attr=VALUE>)
// " -> &quot,
function showHtmlAttrStr($str) {
  return '"' . escapeHtmlAttrStr($str) . '"';
}

function showHtmlAttrBool($b) {
  return $b ? '"true"' : '"false"';
}

function escapeHtmlAttrStr($str) {
  return str_replace(array ('"'), array ('&quot;'), $str); // we do escapeSQL and replace \" by &quot; and \' by '
}

function showJsStr($str) {
  return "'" . escapeJsStr($str) . "'";
}

function escapeJsStr($str) {
  return escapeSQL($str);
}

// This is needed for non-javascript urls, where javascript would call encodeURIComponent
// We only handle the &, the browser takes care of the rest.
function escapeURI($str) {
  return str_replace(array ('&'), array ('%26'), $str); // replace & by %26
}

function escapeSQL($str) {
  return addslashes($str);
}
?>
