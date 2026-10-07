#!/bin/bash
R=/vol4/@appshare/octop-native/qa5-acl
rm -rf "$R"; mkdir -p "$R"
printf 'x\n' > "$R/plain-new-file"
( umask 077; printf 'x\n' > "$R/secret-umask077" )
( umask 022; printf 'x\n' > "$R/normal-umask022" )
chmod 600 "$R/plain-new-file"
ls -l "$R"
echo "--- getfacl ---"
for f in "$R"/plain-new-file "$R"/secret-umask077 "$R"/normal-umask022; do echo "== $f"; getfacl -p "$f" 2>&1 | grep -v '^#'; done
echo "--- 尝试用同组/其他身份读？(无法模拟他人，只能看 ACL) ---"
rm -rf "$R"
