# !/bin/bash

###AJ: Create a tmp dir if not present in pwd. Create a Log info file in ./tmp with name Mylog(Timestamp when the program ran).log

if [[ ! -d "tmp" ]]; then 
	mkdir ./tmp
fi
touch ./tmp/Mylog.$(date +%Y.%m.%d-%H:%M:%S).log
exec > >(tee -i ./tmp/Mylog.$(date +%Y.%m.%d-%H:%M:%S).log)
exec 2>&1

###AJ: Abort if any command fails 
set -o errexit 

clear 
me=$(basename "$0")

help_message="\
Version 1.1
Usage:

Runs Agave Platform smoke tests for Systems, Files, Jobs, Apps, Metadata and Notifications against the science APIs and publishes report to local directory. 

Before running make sure to populate the config file with appropriate values.

Options to run the SmoketestsUH.sh script:

  -s, --service		The name of an Agave Science API service to run the tests on. If specified, only the tests against this service will be run.                           
  -h, --help		Show this help information.
  -env				Environment name (dev)

To run the program in debug mode run command: bash -x smoketests_dev.sh -s [<service_name>]	

Examples:

1.  To run smoke tests for all services in dev env:
./SmoketestsUH.sh -s all -env dev

2. To run smoke tests for all services in staging env:
./SmoketestsUH.sh -s all -env staging

3. To run the smoke tests for specific service in dev/staging
./SmoketestsUH.sh -s <service_name> -env <env_name>
  "

###AJ: Setting Environment variables
VERSION='v2'
SYSTEMS_SERVICE='systems/'
SYSTEM='system/'
FILES_SERVICE='files/v2'
APPS_SERVICE='apps/'
NOTIFICATIONS_SERVICE='notifications/'
JOBS_SERVICE='jobs/'
METADATA_SERVICE='meta/'
STATUS_EXPECTED=success
STATUS_NOT_EXPECTED=error
LISTINGS=/listings/
MEDIA=/media
DATA='/data/'


###AJ: Function to remove temp files. Call to this function is commented for now.
function cleanup_temp_files() {
  (( $verbose )) && echo "Removing temp filtered files"
  rm -rf tmp
}

###AJ: Assertion to check status of response from the GET request
function assert_status( ) {
	STATUS=`echo $RESULT | jq -r '.status'` 
	if [ "$STATUS"  = "$STATUS_EXPECTED" ] &&  [ "$STATUS"  != "$STATUS_NOT_EXPECTED" ]
	then
		echo "Output PASS"
		num_of_tests_pass=$((num_of_tests_pass+1))
	else
		echo "Output FAIL"
		ERROR=`echo $RESULT | jq -r '.message'`
		echo "Test failed due to:" $ERROR
		num_of_tests_fail=$((num_of_tests_fail+1))
	fi;	
	
}

function assert_version ( ) {
REVISION=`echo $RESULT | jq -r '.version'` 
	if [ "$REVISION"  = "$VERSION_EXPECTED" ]
	then
		echo "Output PASS"
		num_of_tests_pass=$((num_of_tests_pass+1))
	else
		echo "Output FAIL"
		num_of_tests_fail=$((num_of_tests_fail+1))
	fi;	
	}
	
###AJ: Function to load configurations per environment
function load_config ( ) {
	#echo $env_name
	CONFIG=`cat ./config_devstg.json`
	if [[ ("$env_name" = "dev") ]]
	 then
		#echo "Inside dev"
		BASE_URL=`echo $CONFIG | jq -r '.dev.BASE_URL'`
		ACCESS_TOKEN=`echo $CONFIG | jq -r '.dev.token'`
		STORAGE_SYSTEM=`echo $CONFIG | jq -r '.dev.storage_id'`
		EXEC_SYSTEM=`echo $CONFIG | jq -r '.dev.exec_id'`
		UUID=`echo $CONFIG | jq -r '.dev.testmetadata_uuid'`
		SCHEMA_ID=`echo $CONFIG | jq -r '.dev.schema_id'`
		VERSION_EXPECTED=`echo $CONFIG | jq -r '.dev.version'`
	elif [[ ("$env_name" = "staging") ]]
	 then
		#echo "Inside staging"
		BASE_URL=`echo $CONFIG | jq -r '.staging.BASE_URL'`
		ACCESS_TOKEN=`echo $CONFIG | jq -r '.staging.token'`
		STORAGE_SYSTEM=`echo $CONFIG | jq -r '.staging.storage_id'`
		EXEC_SYSTEM=`echo $CONFIG | jq -r '.staging.exec_id'`
		UUID=`echo $CONFIG | jq -r '.staging.testmetadata_uuid'`
		SCHEMA_ID=`echo $CONFIG | jq -r '.staging.schema_id'`
		VERSION_EXPECTED=`echo $CONFIG | jq -r '.staging.version'`
	else
		break
	fi
}



###AJ: Function containing smoke tests for all services
function smoke_tests() {

	###AJ: total_core_tests, total_core_pass, total_core_fail are cumulative statistics for all services
	total_core_test=$((total_core_test+num_of_tests))
	total_core_pass=$((total_core_pass+num_of_tests_pass))
	total_core_fail=$((total_core_fail+num_of_tests_fail))     

	###AJ: num_of_tests, num_of_tests_pass, num_of_tests_fail are tests per service
	num_of_tests=0
	num_of_tests_pass=0
	num_of_tests_fail=0

	###AJ: Run smoke tests per command line arguement given in -s or --service
	while :
	do
		flag_tests_fail=false
		case $core_service in
		###AJ: Smoke tests for systems service
		systems)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Begin running smoke tests for Systems service: "
			echo " "
			echo "Test: Check if system service is available"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$SYSTEMS_SERVICE$VERSION 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			#assert_version $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "Test: Check if storage systems available to the user"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$SYSTEMS_SERVICE$VERSION?type=STORAGE 2>/dev/null`
			num_of_tests=$((num_of_tests+1))			
			assert_status $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if execution systems available to the user"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$SYSTEMS_SERVICE$VERSION?type=EXECUTION 2>/dev/null`
			num_of_tests=$((num_of_tests+1))			
			assert_status $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if systems service points to correct version"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$SYSTEMS_SERVICE$VERSION 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "************* Summary of Systems Tests ****************"
			echo " "
			echo "Total system tests ran:" $num_of_tests
			echo "Total system tests pass:" $num_of_tests_pass
			echo "Total system tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Systems Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		
		###AJ: Smoke tests for files service
	        files)
			echo " "
			echo "*********************************************** "
			echo "Begin running smoke tests for Files service"
			echo " "
			echo "Test: Check if files listing is available"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$FILES_SERVICE$LISTINGS 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if files listing is available for particular storage system id"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$FILES_SERVICE$LISTINGS$SYSTEM$STORAGE_SYSTEM 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if files listing is available for particular execution system id"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$FILES_SERVICE$LISTINGS$SYSTEM$EXEC_SYSTEM 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if File service points to correct verison"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$FILES_SERVICE$LISTINGS 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " " 
			echo "************* Summary of Files Tests ****************"
			echo " "
			echo "Total Files tests ran:" $num_of_tests
			echo "Total Files tests pass:" $num_of_tests_pass
			echo "Total Files tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Files Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		###AJ: Smoke tests for apps service
		apps)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Running smoke tests for Apps service"
			echo " "
			echo "Checking apps service....."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$APPS_SERVICE$VERSION 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if apps service points to correct version"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$APPS_SERVICE$VERSION 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "************* Summary of Apps Tests ****************"
			echo " "
			echo "Total Apps tests ran:" $num_of_tests
			echo "Total Apps tests pass:" $num_of_tests_pass
			echo "Total Apps tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Apps Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		###AJ: Smoke tests for notifications service
		notifications)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Running smoke tests for Notifications service"
			echo " "
			echo "Checking notifications service....."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$NOTIFICATIONS_SERVICE$VERSION 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if notification service points to correct version"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$APPS_SERVICE$VERSION 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "************* Summary of Notifications Tests ****************"
			echo " "
			echo "Total Notifications tests ran:" $num_of_tests
			echo "Total Notifications tests pass:" $num_of_tests_pass
			echo "Total Notifications tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Notifications Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		###AJ: Smoke tests for jobs service
		jobs)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Running smoke tests for Jobs service"
			echo " "
			echo "Checking jobs service....."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$JOBS_SERVICE$VERSION 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Test: Check if jobs service points to correct version"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$APPS_SERVICE$VERSION 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "************* Summary of Jobs Tests ****************"
			echo " "
			echo "Total Jobs  tests ran:" $num_of_tests
			echo "Total Jobs  tests pass:" $num_of_tests_pass
			echo "TotalJobs tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Jobs  Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		###AJ: Smoke tests for metadata service
		metadata)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Running smoke tests for Metadata service"
			echo " "
			echo "Checking metadata service....."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$METADATA_SERVICE$VERSION$DATA 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "			
			echo "Create metadata1: testmetadata1 with value as json"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" -X POST -H 'Content-type:application/json' --data-binary '{"name": "testmetadata1", "value": {"title": "Example Metadata", "properties": {"species": "arabidopsis", "description": "A model organism..."}},"schemaId": null, "associationIds":[] }' $BASE_URL$METADATA_SERVICE$VERSION$DATA 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			#UUID=`echo $RESULT | jq -r '.result.uuid'`
			#echo $UUID
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Create metadata2: testmetadata2 with value as string"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" -X POST -H 'Content-type:application/json' --data-binary '{"name": "testmetadata2", "value": "example","schemaId": null, "associationIds":[] }' $BASE_URL$METADATA_SERVICE$VERSION$DATA 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Creating metadat3 using association id of testmetadata1...."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" -X POST -H 'Content-type:application/json' --data-binary '{"name": "testmetadata3", "value": "example","schemaId": null, "associationIds":["3163371713340510696-242ac115-0001-012"] }' $BASE_URL$METADATA_SERVICE$VERSION$DATA 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Metadata Searching by name...."
			RESULT=`curl -G -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$METADATA_SERVICE$VERSION$DATA --data-urlencode '{"name":"testmetadata1"}' 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo " "
			echo "Listing metadata permissions for testuser...."
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$METADATA_SERVICE$VERSION$DATA$UUID/pems/testuser 2>/dev/null`
			num_of_tests=$((num_of_tests+1))
			assert_status  $RESULT, $num_of_tests_pass, $num_of_tests_fail
			echo "  " 
			echo "Test: Check if metadata service points to correct version"
			RESULT=`curl -k -H "Authorization:Bearer $ACCESS_TOKEN" $BASE_URL$METADATA_SERVICE$VERSION/data 2>/dev/null`
                        num_of_tests=$((num_of_tests+1))
			assert_version  $RESULT, $num_of_tests_pass, $num_of_tests_fail, $VERSION_EXPECTED
			echo " "
			echo "************* Summary of Metadata Tests ****************"
			echo " "
			echo "Total Metadata  tests ran:" $num_of_tests
			echo "Total Metadata  tests pass:" $num_of_tests_pass
			echo "Total Metadata tests fail:" $num_of_tests_fail
			echo " "
			echo "************* End of Metadata Tests ****************"
			echo " "
			if [[ "$num_of_tests_fail" -gt "0" ]];then
				flag_tests_fail=true
				#echo "Inside flag" $flag_tests_fail
			fi
			break
			;;
		###AJ: If user inputs invalid service name
		*)
			echo "  " 
			echo "*********************************************** "
			echo " "
			echo "Please enter a valid service name: systems, files, apps, notifications, metadata, jobs, all"
			break
			;;
		esac
	done
		
}	
###AJ: Parse comand line arguements. $1 -h: HELP  -s, --service : SYSTEMS, FILES, JOBS, APPS, METADATA, NOTIFICATIONS, ALL (To run smoke tests for all services) , -env $2 dev, staging
function parse_args() {

	###AJ: List Services contains names of all services, for which smoke tests will be run when user selects -s all or --service all	
	Services=("systems"  "files"  "apps"  "jobs" "notifications" "metadata")
	
	while : ; do
		if [[ $1 = "-h" || $1 = "--help" ]]; then
   			echo "$help_message"
     	 		break
  		 elif [[ ( $1 = "-s" || $1 = "--service" ) && ($3="-env") && -n $4 ]]; then
     			echo "***** Begin Smoke Tests for Agave API Platform v0.6*****"
			echo " " 
			echo "***** QA Contact: ajamthe@tacc.utexas.edu *****"
			core_service_temp=$2
			env_name_temp=$4
			###AJ: Convert env names to lower case
			env_name=`echo $env_name_temp | tr '[A-Z]' '[a-z]'` 

			load_config $env_name, $BASE_URL, $ACCESS_TOKEN, $STORAGE_SYSTEM, $EXEC_SYSTEM,$UUID,$SCHEMA_ID,$VERSION_EXPECTED
			
			###AJ: Convert service names to lower case, so they match with case ids in switch case
			core_service=`echo $core_service_temp | tr '[A-Z]' '[a-z]'` 

			###AJ: Create storage system
			#create_storage_system

			###AJ: Run smoke tests for service given in command line arguement. User can specify 'all' if tests should run for all services

			### Run smoke tests for particular service
			if [ $core_service != "all" ]; then
	               		 smoke_tests $core_service, $num_of_tests_pass, $num_of_tests_fail, $num_of_tests
				

			###AJ: Run Smokes for all services
			elif [ $core_service = 'all' ]; then
				###AJ: Place holders for cumulative run statistics
				total_core_test=0
				total_core_pass=0
				total_core_fail=0

			###AJ: For all services in the Services list run the smoke tests and calculate the run statistics
				for i in "${Services[@]}"
				do	
					core_service=$i
					smoke_tests $core_service, $total_core_test, $total_core_pass, $total_core_fail, $flag_tests_fail

			    done

			###AJ: Update the run statsistics to get data from last dervice run
				total_core_test=$((total_core_test+num_of_tests))
				total_core_pass=$((total_core_pass+num_of_tests_pass))
				total_core_fail=$((total_core_fail+num_of_tests_fail))  

				echo "***************** Cumulative summary ***********************"
				echo " "
				echo "Total Tests passed: " $total_core_pass"/"$total_core_test
				echo " "
				echo "Total Tests fail: " $total_core_fail"/"$total_core_test
				echo " "
				echo " ****************** End of Cumulative summary **************" 
			#	break
			fi
		 break

   		 else
     			 break
  		  fi
 	done

  
###AJ: If the user does not provide any command line arg, display help message
  if [[ -z "$1" ]]; then
    echo "Please enter valid command line agruments"
    echo "$help_message"
    return 1
  fi
  ###AJ: Call the cleanup function to disable storage
#  clean_up
}

###AJ: Main function
main() {

	parse_args "$@"
	###AJ: Call to Clean up function has been commented for now
   	#cleanup_temp_files
}


main  "$@" 

