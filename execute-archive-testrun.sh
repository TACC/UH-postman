#!/usr/bin/env bash

# Usage :
# Script to run the newman tests and archive the results
#
# example:
# execute-archive-testrun.sh dev.tenants.sandbox.agaveapi.co:149.165.157.105  dev.sandbox "-s apps"

datestamp=$(date +%Y.%m.%d-%H:%M:%S)
echo "*************************************************"
echo " start of test run $datestamp"
echo "*************************************************"

host=$1
tenant=$2
service=$3

projectdir=$(pwd)


cd tenants
mkdir "$projectdir/testrun/$tenant.$datestamp"

./newman-v2.sh -v $service --add-host $host  $tenant > "$projectdir/testrun/$tenant.$datestamp/$tenant.result.txt"
mv tmp "$projectdir/testrun/$tenant.$datestamp"/tmp.$tenant
mv reports "$projectdir/testrun/$tenant.$datestamp"/reports.$tenant
cp config/newman_data.json "$projectdir/testrun/$tenant.$datestamp"/


echo "*************************************************"
echo "                  $datestamp   end of test run   "
echo "*************************************************"
