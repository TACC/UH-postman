#!/bin/bash

set -o errexit #abort if any command fails
me=$(basename "$0")

help_message="\
Usage: $me [<options>] TENANT_ID
Runs Agave Platform integration tests against the Admin APIs and publishes a
report summary to Slack. Options exist for running tests against a single
service, and enabling status results posted to the agave-slackops Slack channel.

Options:

  -s, --service            The name of an Agave Admin API service to run the tests on.
                           If specified, only the tests against this service will be run.
      --notify-slack       If present, the results summary will be written to slack.
      --add-host           Any additional hosts to add into the docker containers.
      --dry-run            Run the filters and set the environment, but skip actual test run
  -h, --help               Show this help information.
  -v, --verbose            Increase script verbosity.
  -d, --debug              Enable debug logging on the HTTP requests.
  "

function err() {
    echo "$@" >&2 ;

    cleanup_temp_files

    exit 1;
}

function cleanup_temp_files() {
  (( $verbose )) && echo "Removing temp filtered files"
  rm -rf tmp
}

function parse_args() {

  extra_hosts=()

  # Parse arg flags
  # If something is exposed as an environment variable, set/overwrite it
  # here. Otherwise, set/overwrite the internal variable instead.
  while : ; do
    if [[ $1 = "-h" || $1 = "--help" ]]; then
      echo "$help_message"
      return 0
    elif [[ $1 = "-v" || $1 = "--verbose" ]]; then
      verbose=1
      shift
    elif [[ $1 = "-d" || $1 = "--debug" ]]; then
      debug=1
      shift
    elif [[ ( $1 = "-s" || $1 = "--service" ) && -n $2 ]]; then
      admin_service=$2
      shift 2
    elif [[ $1 = "--notify-slack"  ]]; then
      notify_slack=1
      shift
    elif [[ $1 = "--dry-run"  ]]; then
      dry_run=1
      shift
    elif [[ $1 = "--add-host" ]] && [[ -n "$2" ]]; then
      extra_hosts+=( "$1 $2" )
      shift 2
    else
      break
    fi
  done

  # Set internal option vars from the environment and arg flags. All internal
  # vars should be declared here, with sane defaults if applicable.


  if [[ -z "$1" ]]; then
    echo "No tenant provided." >&2
    echo "$help_message"
    return 1
  else
    TENANT="${1}"
  fi

}



function main() {
    local _COLLECTION  _ENVIRONMENT FILTERED_COLLECTION FILTERED_ENVIRONMENT _ITERATION_DATA

    parse_args "$@"

    if [[ ! -d "tmp" ]]; then
      mkdir ./tmp
    fi

    # switch to jwt environment if skipping frontend
    _ENVIRONMENT="environments/$TENANT.postman_environment"
    FILTERED_ENVIRONMENT="tmp/$TENANT.postman_environment"

    # ensure environment file is there
    if [[ ! -e "$_ENVIRONMENT" ]]; then
        err "No environment found for $TENANT. Please provide a valid tenant environment to run the tests against."
    fi

    # ensure collection is present
    _COLLECTION="collections/agave-admin-services.postman_collection.json"
    if [[ ! -e "$_COLLECTION" ]]; then
        err "No collection found to run at $_COLLECTION."
    fi

    FILTERED_COLLECTION="tmp/agave-admin-services.postman_collection.json"

    # ensure newman iteration data is present
    _ITERATION_DATA="config/newman_data.json"
    if [[ ! -e "$_ITERATION_DATA" ]]; then
        err "No iteration data found to run at $_ITERATION_DATA."
    fi

    # copy the environment over for filtering below
    cp -f "${_ENVIRONMENT}" "${FILTERED_ENVIRONMENT}"

    # if a service value is given, update the environment to use that value.
    if [[ -n "$admin_service" ]]; then
        if [[ -n "$(grep "${admin_service}::Start" $_COLLECTION)" ]]; then
            first_test="${admin_service}::Start"
        elif [[ -n "$(grep "${admin_service} setup::" $_COLLECTION)" ]]; then
            first_test=$(grep "${admin_service} setup::" $_COLLECTION | head -n 1 | sed 's/.*"name": //g' | sed 's/,//g' | sed 's/"//g' )
        elif [[ -n "$(grep "${admin_service}::" $_COLLECTION)" ]]; then
            first_test=$(grep "${admin_service}::" $_COLLECTION | head -n 1 | sed 's/.*"name": //g' | sed 's/,//g' | sed 's/"//g' )
        fi

        if [[ -z "$first_test" ]]; then
            err "No postman tests found for service $admin_service"
        else
            (( $verbose )) && echo "Restricting tests to the $admin_service API";
            (( $verbose )) && echo "First test will be $first_test";
            # update the environment with the first service test to run
            sed -i.0 's/%%SKIP_TO_TEST%%/'"${first_test}"'/g'  $FILTERED_ENVIRONMENT
            #cat "$_ENVIRONMENT" | jq --arg t "${first_test}" '.values |= map((select(.key == "SKIP_TO_TEST") | .value) |= $t)' > "$FILTERED_ENVIRONMENT"
        fi
    else
        # update the environment with an empty first service test to run
        sed -i.0 's/%%SKIP_TO_TEST%%//' "${FILTERED_ENVIRONMENT}"
        #cat "$_ENVIRONMENT" | jq '.values |= map((select(.key == "SKIP_TO_TEST") | .value) |= "")' > "$FILTERED_ENVIRONMENT"
    fi


    # Update the global timestamp used to generate unique resource IDs in the tests.
    _TS=$(date +%s)
    (( $verbose )) && echo "Setting environment TEST_DATE to $_TS";
    sed -i.0 's/%%TEST_DATE%%/'$_TS'/' "${FILTERED_ENVIRONMENT}"

    resolve_multipart_upload_template_variables $_TS

    ######################################
    #    DO NOT EDIT BELOW THIS LINE     #
    ######################################

    # pull latest images
#    docker pull php:5.6-cli
#    docker pull postman/newman_ubuntu1404:3.2.0

    # make sure all the upload file names are present and have not been
    # filtered out by postman bugs
    # lib/inject_upload_filenames-v2.php \
    #         -d \
    #         -v \
    #         --default-file=compress.data \
    #         --data-directory=/Users/dooley/dockerspace/agave-postman/staging \
    #         --output=$FILTERED_COLLECTION \
    #         -- $COLLECTION

    (( $verbose )) && echo "Filtering postman $_COLLECTION with runtime file paths ...";

    docker run \
            --rm=true \
            -v $(pwd):/software \
            -t \
            -e FILTERED_COLLECTION:$FILTERED_COLLECTION \
            -e COLLECTION:$_COLLECTION \
            -w /software \
            php:5.6-cli \
            /software/lib/inject_upload_filenames-v2.php \
            $( (( $debug )) && echo '-d' ) \
            $( (( $verbose )) && echo '-v' ) \
            --default-file="data/compress.data" \
            --output=$FILTERED_COLLECTION \
            -- $_COLLECTION


    # touch the output files so we don't have to adjust their permissions
    mkdir -p reports
    touch reports/newman-report.json
    touch reports/newman-report.xml
    touch reports/newman-report.html

    # exit here if we're done with the dry run.
    if (( $dry_run )); then
      exit 0
    fi

    # if we're posting to slack, we call the newman-to-slack script
    if (( $notify_slack )); then

        if (( $debug )); then
            (( $verbose )) && echo "Enabling verbose debugging ...";
            export NODE_DEBUG=http,request,net
        fi

        (( $verbose )) && echo "Starting newman-to-slack runner ...";

        lib/newman-to-slack.sh \
                -v -v -v \
                -a "--iteration-data $_ITERATION_DATA --insecure --timeout-request 60000 --disable-unicode --reporters cli,html,json,junit --reporter-json-export reports/newman-report.json --reporter-junit-export reports/newman-report.xml --reporter-html-export reports/newman-report.html" \
                --environment "$FILTERED_ENVIRONMENT" \
                --webhook https://hooks.slack.com/services/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 \
                -c $FILTERED_COLLECTION || true

    # if we are not posting to slack, we run the collection manually in a docker container
    else

        (( $verbose )) && echo "Starting docker newman runner ...";
        docker run \
             --rm=true \
             -l newman -l $TENANT \
             $([[ -n "$extra_hosts" ]] && echo "${extra_hosts}" || echo "") \
             -v ${PWD}:/etc/newman \
             -t \
             -e "NODE_DEBUG=$( (( debug )) && echo "http,request,net" || echo "false" )" \
             postman/newman_ubuntu1404:3.2.0 run \
             --timeout-request 60000 \
             --insecure \
             --no-color \
             --reporters cli,html,json,junit \
             --reporter-json-export reports/newman-report.json \
             --reporter-junit-export reports/newman-report.xml \
             --reporter-html-export reports/newman-report.html \
             --environment "$FILTERED_ENVIRONMENT" \
             --iteration-data $_ITERATION_DATA \
             $FILTERED_COLLECTION || true

    fi

    cleanup_temp_files
}

function resolve_multipart_upload_template_variables () {
  # get the username from the environment file which was filtered
  # prior to this function call
  TENANT_CODE=$(cat "$FILTERED_ENVIRONMENT" | jq -r '.values[] | select(.key == "TENANT_CODE") | .value' )
  TENANT_USERNAME=$(cat "$FILTERED_ENVIRONMENT" | jq -r '.values[] | select(.key == "USERNAME") | .value' )
  TENANT_USER_EMAIL=$(cat "$FILTERED_ENVIRONMENT" | jq -r '.values[] | select(.key == "USER_EMAIL") | .value' )
  TEST_DATE=${_TS}
  for tpl in `find data -name "*.json"`; do
    (( $verbose )) && echo "Processing data template file $tpl"

    tmpdir="tmp/$(dirname $tpl)"
    # make sure temp data directory is there
    if [[ ! -d "$tmpdir" ]]; then
      mkdir -p "$tmpdir"
    fi

    sed -i.0 's/{{USERNAME}}/'${TENANT_USERNAME}'/g' "tmp/$tpl"
    sed -i.0 's/{{USER_EMAIL}}/'${TENANT_USER_EMAIL}'/g' "tmp/$tpl"
    sed -i.0 's/{{TEST_DATE}}/'${_TS}'/g' "tmp/$tpl"
  done
}

main "$@"
