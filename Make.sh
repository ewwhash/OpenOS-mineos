#!/bin/sh
rm -rf ./OpenOS/
rm -rf ./OpenComputers/
rm -rf ./Rootfs.pkg
git clone --depth=1 https://github.com/MightyPirates/OpenComputers.git
echo "Patching..."
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/bin/dmesg.lua ./Patches/dmesg.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/etc/motd ./Patches/motd.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/etc/profile.lua ./Patches/profile.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/lib/core/boot.lua ./Patches/boot.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/lib/core/cursor.lua ./Patches/cursor.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/usr/misc/greetings.txt ./Patches/greetings.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/lib/vt100.lua ./Patches/vt100.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/lib/shell.lua ./Patches/shell.patch
patch ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos/lib/process.lua ./Patches/process.patch
cp -r ./OpenComputers/src/main/resources/assets/opencomputers/loot/openos ./rootfs/
rm -rf ./OpenComputers/
python ./Compress.py
rm -rf ./rootfs/
