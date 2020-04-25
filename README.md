# Deployment scripts

`deploy.sh` is the master script that helps with

* Collected release notes for the base node, Android and iOs apps
* Updates repo tags
* Builds installer bundles
* Tags repo with latest release numbers
* Pushes binaries to respective places

For every release, prepare a `versiondata-x.y.z.env` file that holds some release metadata. See the sample `versiondata.env` file for the list of varibale that should be updated.

###  Subscripts

* libwallet_hashes.sh - hashes and bundles the libwallet FFI binaries
* deploy_android.sh - builds the Android app and pushes it to the Play store
