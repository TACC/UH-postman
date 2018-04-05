# Getting Started

### Check List of prequisitites to run Newman tests

 1. our **testuser** must be defined in our tenant (testuser)
 2. our tenant_id must be defined in APIM.
 3. our tenant record must be in the core database tenants table
 4. changes must be made in the following files to match our environment
    * tenants/config/newman_data.json
    * tenants/data/systems/storage.json
    * tenants/data/systems/compute.json
    * tenants/environments/dev.sandbox.postman_environment
 5. our external test system that acts as storage and compute host must
    have the public key installed in authorized keys file of user designated
    for host access.


See the CIC-AgavePostmanintegrationTestSuite pdf file for more details on the Newman tests.
jenkins job run:

cd tenants; 
./newman-v2.sh -v $service --add-host dev.tenants.develop.agaveapi.co:129.114.97.227  dev.develop
