#!/bin/bash
version=${1}

if [ -z ${version} ]
then
  echo usage: update_libs.sh version
  exit
fi

arches='
arm64-v8a
x86_64
armeabi-v7a
'
arch_arr=($arches)

# Create the hash file
hashfile=${TARI_WEBSITE_REPO}/_binaries/hashes-${version}.txt
echo "# Mobile libraries for Tari libwallet version ${version}. ${date}" > ${hashfile}
pushd . > /dev/null
cd $JNI_PATH
sha256sum wallet.h >> ${hashfile}
popd > /dev/null
for i in ${arch_arr[@]}; do
  # Tarball the required libraries
  filename=${i}-${version}.tar.gz
  tar -czf _binaries/${filename} -C $JNI_PATH wallet.h $i >/dev/null 2>&1
  pushd . > /dev/null
  cd $JNI_PATH
  sha256sum $i/* >> ${hashfile}
  popd > /dev/null
done

# iOS library
filename=libtari_wallet_ffi-ios-${version}.tar.gz
tar -czf _binaries/${filename} -C $IOS_PATH wallet.h libtari_wallet_ffi.a >/dev/null 2>&1
pushd . > /dev/null
cd $IOS_PATH
sha256sum libtari_wallet_ffi.a >> ${hashfile}
popd > /dev/null