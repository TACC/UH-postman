#!/usr/bin/env php
<?php

// This is the array of tests that perform file uploads that need to ensure
// the file name is properly injected.
$replacements = array(
  'apps setup::Stage wc App' => 'data/wc',
  'apps setup::Stage wc App Wrapper' => 'data/wrapper.sh',
  'apps::Register New Multipart Upload Application' => 'tmp/data/apps/app.json',

  'jobs setup::Stage wrapper.sh for Jobs Tests' => 'data/wrapper.sh',
  'jobs setup::Stage wrapper-short.sh for Jobs Tests' => 'data/wrapper-short.sh',
  'jobs setup::Stage wc for Jobs Tests' => 'data/wc',
  'jobs:Submit a New Multipart Upload Short Job Request' => 'tmp/data/jobs/job.json',

  // 'notifications::Create a Multipart Upload Notification' => 'tmp/data/notifications/notification.json',

  'monitors::Register Multipart Upload Test Compute System' => 'tmp/data/systems/compute.json',
  'monitors::Add New Multipart Upload Monitor' => 'tmp/data/monitors/monitor.json',

  'meta::Add New Multipart Upload Metadata' => 'tmp/data/metadata/meta.json',
  'meta::Add New Multipart Upload Metadata Schema' => 'tmp/data/metadata/schema.json',

  'systems::Create a Storage System Multipart Form Upload Test' => 'tmp/data/systems/storage.json',
  
  'uuids setup::Stage File' => 'data/wrapper.sh',

  // 'foo::bar' => 'foo.sh',
);

/**
 * Command line parser for the script
 */
class CLI_Parser {

  private $args;

  private $options;

  function __construct() {
    $this->parseOpts();
    $this->parseArgs();
  }

  /**
   * Parses options passed to the script. Options are everything before "--"
   * @return array options passed to the script
   */
  private function parseOpts() {
    $defaults = array() + array(
      'default-filename' => 'compress.data',
      'data-directory' => '',
      'output' => ''
    );

    $shortopts  = "";
    $shortopts .= "v";    // Flag: verbose mode
    $shortopts .= "d";    // Flag: debug mode

     $longopts  = array(
        "default-file::", // Optional: default upload filename to inject if the test is not defined
        "data-directory::", // Optional: the parent directory of all the replacement files
        "output::",       // Optional: output file to write the filtered json collection document
    );

    $this->options = getopt($shortopts, $longopts) + $defaults;

    // var_dump( $options );
  }

  /**
   * Parses arguments passed to the script. Arguments are everything after "--".
   * The lone argument should be the postman collection file.
   * @return array arguments passed to the script
   */
  private function parseArgs() {
    global $argv;

    $args = array_search('--', $argv);
    $this->args = array_splice($argv, $args ? ++$args : (count($argv) - count($this->options)));

    // var_dump( $args );
  }

  public function getArgs() {
    return $this->args;
  }

  public function getOptions() {
    return $this->options;
  }
}


// define('VERBOSE', $options['verbose'] || $options['v']);
// define('DEBUG', $options['debug'] || $options['d']);
// define('POSTMAN_COLLECTION_FILE', 'Agave-Prod-Staging.json.postman_collection');
//
// define('DEFAULT_UPLOAD_FILENAME', 'compress.data');

class PostmanCollectionParser {

  private $postmanCollection = '';
  private $debug = false;
  private $verbose = false;
  private $defaultUploadFilename = 'compress.data';
  private $defaultUploadDirectory = '';
  private $outputFile = '';

  private $totalUpdates = 0;

  function __construct() {
    $this->parseCommandLine();
  }

  /**
   * Parses command line into options and args for use when
   * parsing the postman file.
   * @return void
   */
  private function parseCommandLine() {
    $parser = new CLI_Parser();

    $this->initPostmanCollection($parser);

    $this->initOptions($parser);
  }

  /**
   * Parses command line into arguments to obtain the
   * path to the postman collection on the local system.
   * @return void
   */
  private function initPostmanCollection($parser) {

    $args = $parser->getArgs();

    if (empty($args)) {
      $this->error("No Postman collection provided. Please specify a file "
            ."containing your Postman collection by appending "
            ."\"-- <path to file>\" to this command.");
    }
    else if (!file_exists($args[0])) {
      $this->error("{$args[0]}: No such file or directory");
    }
    else {
      $this->postmanCollection = $args[0];
    }
  }

  /**
   * Parses command line options for use when parsing the postman file.
   * @return void
   */
  private function initOptions($parser) {
    $options = $parser->getOptions();

    $this->debug = isset($options['d']);
    $this->verbose = isset($options['v']);
    $this->defaultUploadFilename = $options['default-file'];
    $this->defaultUploadDirectory = $this->addTrailingSlash($options['data-directory']);
    $this->output = $options['output'];
  }

  /**
   * Parses the postman json document.
   * @return string the parsed json object.
   */
  public function parse() {
    global $replacements;
    // read in the postman collection. This will accept a file or url
    if ($this->verbose) echo "Reading postman collection from: {$this->postmanCollection}\n";
    $json_file = file_get_contents($this->postmanCollection);

    // parse the json response
    $postmanCollection = json_decode($json_file, true);

    // if the collection has bad json, exit with message
    if (empty($postmanCollection)) {
      $this->error("Invalid json found in {$this->postmanCollection}");
    }
    // if the collection is good, parse and output to the appropriate place
    else {
      try {
        // parse collection and get updated array
        $postmanCollection = $this->doParse($postmanCollection);

        // print summary if requested. summary always goes to stdout
        if ($this->verbose) $this->printSummary();

        // if an output location has been specified, write there
        if ($this->output) {
          file_put_contents($this->output, $this->formatResponse($postmanCollection));
        }
        // otherwise write to std out
        else {
          echo $this->formatResponse($postmanCollection);
        }
      }
      // all errors will be written to stderr
      catch (Exception $error) {
          if ($this->verbose) {
            $this->printSummary();
            $this->error($error->getMessage() . ": \n" . implode("\n", array_keys($replacements)));
          }

          $this->formatResponse(null, $error);
      }
    }

  }

  /**
   * Parses the postman collection ensuring all file upload
   * tests have a proper value for the upload file. The global
   * $replacements array contains any custom values needing to
   * be injected in <test_name> => <filename> form.
   * @param  array $json [description]
   * @return [type]       [description]
   */
  private function doParse($postmanCollection) {

    global $replacements;

    $this->totalUpdates = 0;

    // update collection name to clarify that this collection has been changed
    $postmanCollection['info']['name'] .= '-Filtered';

    // for each collection update the file name on POST requests
    foreach ($postmanCollection['item'] as $colIndex => &$subcollection) {
      // and for each subcollection
      foreach ($subcollection['item'] as $testIndex => &$testcase) {
        // if it's a POST request
        if ($testcase['request']['method'] == 'POST') {
          // we only do this for multipart uploads. These requests are identified
          // by the existence of a "formdata" field in the request body.
          if (array_key_exists('formdata', $testcase['request']['body'])) {
            // check for a form parameter with key "fileToUpload". this indicates a file upload
            foreach ($testcase['request']['body']['formdata'] as $paramIndex => &$param) {
              // if we've found the "fileToUpload" parameter definition
              if ($param['key'] == 'fileToUpload') {

                // update our replacement counter for the summary output
                $this->totalUpdates++;

                if ($this->debug) echo "{$this->totalUpdates}. Updating \"{$testcase['name']}\" \n<=====" . json_encode($param, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
                // use the value defined in the replacement array if it exists
                if (array_key_exists($testcase['name'], $replacements)) {
                  $param['src'] = $this->defaultUploadDirectory . $replacements[$testcase['name']];
                  unset($replacements[$testcase['name']]);
                }
                // otherwise, assign the default value
                else {
                  $param['src'] = $this->defaultUploadDirectory . $this->defaultUploadFilename;
                }
                if ($this->debug) echo "\n=====>" .json_encode($param, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES) . "\n\n";
              }
            }
          }
        }
      }
    }

    if (count($replacements) > 0) {
      throw new Exception("Failed to process one or more named tests: \n" . implode("\n", array_keys($replacements)));
    }
    else {
      return $postmanCollection;
    }
  }

  /**
   * Formats the response optionally printing summary information
   * if verbose was true.
   *
   * @param  string $json  the json response. null if there was an error
   * @param  Error $error the error reported during processing
   * @return string the formatted response
   */
  private function printSummary() {
    global $replacements;

    echo "##########################################\n";
    echo "Summary\n";
    echo "##########################################\n";
    echo "Total replacements: {$this->totalUpdates}\n";
    echo "Unmatched replacements: " . count($replacements). "\n";

    foreach (array_keys($replacements) as $testName) {
      echo "\t$testName\n";
    }
    echo "##########################################\n\n";
  }

  private function formatResponse($json='', $error=null) {
    return json_encode($json, JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
  }

  private function error($message) {
    $stderr = fopen('php://stderr', 'w');
    fwrite($stderr, "ERROR: {$message}\n\n");
    exit(1);
  }

  function addTrailingSlash($value) {
  	if (!(empty($value) || $this->endsWith($value, '/'))) {
  		$value .= '/';
  	}
  	return $value;
  }
  private function endsWith($haystack,$needle,$case=true) {
    if($case){return (strcmp(substr($haystack, strlen($haystack) - strlen($needle)),$needle)===0);}
    return (strcasecmp(substr($haystack, strlen($haystack) - strlen($needle)),$needle)===0);
  }
}

$parser = new PostmanCollectionParser();
$parser->parse();
