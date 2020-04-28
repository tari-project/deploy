#!/bin/bash
version=${1}
DATE=`date +%Y-%m-%d`
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
hashfile=${TARI_WEBSITE_REPO}/_binaries/libwallet-hashes-${version}.txt
echo "# Mobile libraries for Tari libwallet version ${version}. ${DATE}" > ${hashfile}
jnipath=${ANDROID_WALLET_REPO}/jniLibs
cd ${jnipath}
sha256sum wallet.h >> "${hashfile}"
for i in ${arch_arr[@]}; do
  # Tarball the required libraries
  filename=libwallet-${i}-${version}.tar.gz
  tar -czf "${TARI_WEBSITE_REPO}/_binaries/${filename}" -C "${jnipath}" wallet.h $i >/dev/null 2>&1
  sha256sum $i/* >> ${hashfile}
done

# iOS library
iospath=${IOS_WALLET_REPO}/MobileWallet/TariLib/
filename=libwallet-ios-${version}.tar.gz
tar -czf "${TARI_WEBSITE_REPO}/_binaries/${filename}" -C "${iospath}" wallet.h libtari_wallet_ffi.a >/dev/null 2>&1
cd $iospath
sha256sum libtari_wallet_ffi.a >> ${hashfile}
