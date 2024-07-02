#!/bin/bash

# Minecraft server download URLs and versions
declare -A serverDownloadUrls

# Snapshots
serverDownloadUrls['20w16a']='https://launcher.mojang.com/v1/objects/754bbd654d8e6bd90cd7a1464a9e68a0624505dd/server.jar'
serverDownloadUrls['20w17a']='https://launcher.mojang.com/v1/objects/0b7e36b084577fb26148c6341d590ac14606db21/server.jar'
serverDownloadUrls['20w19a']='https://launcher.mojang.com/v1/objects/fbb3ad3e7b25e78723434434077995855141ff07/server.jar'
serverDownloadUrls['20w20b']='https://launcher.mojang.com/v1/objects/0393774fb1f9db8288a56dbbcf45022b71f7939f/server.jar'
serverDownloadUrls['20w21a']='https://launcher.mojang.com/v1/objects/03b8fa357937d0bdb6650ec8cc74506ec2fd91a7/server.jar'
serverDownloadUrls['20w22a']='https://launcher.mojang.com/v1/objects/c4a62eb36917aaa06dc8e20a2a35264d5fda123b/server.jar'
serverDownloadUrls['1.16-pre2']='https://launcher.mojang.com/v1/objects/8daeb71269eb164097d7d7ab1fa93fc93ab125c3/server.jar'
serverDownloadUrls['1.16-pre5']='https://launcher.mojang.com/v1/objects/56081523bca4f7074f111d1e8a9fd0a86d072a2b/server.jar'
serverDownloadUrls['1.16-pre8']='https://launcher.mojang.com/v1/objects/d6a747371b200216653be9b4140cd2862eddbb0e/server.jar'
serverDownloadUrls['1.16-rc1']='https://launcher.mojang.com/v1/objects/7213e5ba8fe8d352141cf3dde907c26c43480092/server.jar'
serverDownloadUrls['20w48a']='https://launcher.mojang.com/v1/objects/d1551eed659a023a0a73137282397a78b0dda261/server.jar'
serverDownloadUrls['20w51a']='https://launcher.mojang.com/v1/objects/fc87ef4c3cf1c815809249cc00ccade233b22cf5/server.jar'
serverDownloadUrls['21w44a']='https://launcher.mojang.com/v1/objects/ae583fd57a8c07f2d6fbadce1ce1e1379bf4b32d/server.jar'
serverDownloadUrls['23w07a']='https://piston-data.mojang.com/v1/objects/b919e6e1683a4b6f37f2717c7841e88e306bdc94/server.jar'
serverDownloadUrls['23w16a']='https://piston-data.mojang.com/v1/objects/4a8487f877eb4f3506978fb85faf41a08b570398/server.jar'
serverDownloadUrls['23w18a']='https://piston-data.mojang.com/v1/objects/240177c763b6009ea81aaf0ef14a73822320856d/server.jar'
serverDownloadUrls['23w31a']='https://piston-data.mojang.com/v1/objects/11ef2ae139b0badda80a1ea07c2dd0cf9034a32f/server.jar'
serverDownloadUrls['23w33a']='https://piston-data.mojang.com/v1/objects/0254dde460b23861840cff6e80fc7fdbbccad88e/server.jar'
serverDownloadUrls['23w51b']='https://piston-data.mojang.com/v1/objects/d443ec98f3f3ee2dc92e0788d6d83d74844feb4f/server.jar'
serverDownloadUrls['24w21a']='https://piston-data.mojang.com/v1/objects/743d74805b64f83052fe449993f42182f76b129e/server.jar'

# Releases
serverDownloadUrls['1.12.2']='https://launcher.mojang.com/mc/game/1.12.2/server/886945bfb2b978778c3a0288fd7fab09d315b25f/server.jar'
serverDownloadUrls['1.16.1']='https://launcher.mojang.com/v1/objects/a412fd69db1f81db3f511c1463fd304675244077/server.jar'
serverDownloadUrls['1.16.2']='https://launcher.mojang.com/v1/objects/c5f6fb23c3876461d46ec380421e42b289789530/server.jar'
serverDownloadUrls['1.16.3']='https://launcher.mojang.com/v1/objects/f02f4473dbf152c23d7d484952121db0b36698cb/server.jar'
serverDownloadUrls['1.16.4']='https://launcher.mojang.com/v1/objects/35139deedbd5182953cf1caa23835da59ca3d7cd/server.jar'
serverDownloadUrls['1.16.5']='https://launcher.mojang.com/v1/objects/1b557e7b033b583cd9f66746b7a9ab1ec1673ced/server.jar'
serverDownloadUrls['1.17.1']='https://launcher.mojang.com/v1/objects/a16d67e5807f57fc4e550299cf20226194497dc2/server.jar'
serverDownloadUrls['1.19.2']='https://piston-data.mojang.com/v1/objects/f69c284232d7c7580bd89a5a4931c3581eae1378/server.jar'
serverDownloadUrls['1.19.4']='https://piston-data.mojang.com/v1/objects/8f3112a1049751cc472ec13e397eade5336ca7ae/server.jar'
serverDownloadUrls['1.20.0']='https://piston-data.mojang.com/v1/objects/15c777e2cfe0556eef19aab534b186c0c6f277e1/server.jar'
serverDownloadUrls['1.20.1']='https://piston-data.mojang.com/v1/objects/84194a2f286ef7c14ed7ce0090dba59902951553/server.jar'
serverDownloadUrls['1.20.2']='https://piston-data.mojang.com/v1/objects/5b868151bd02b41319f54c8d4061b8cae84e665c/server.jar'
serverDownloadUrls['1.20.3']='https://piston-data.mojang.com/v1/objects/4fb536bfd4a83d61cdbaf684b8d311e66e7d4c49/server.jar'
serverDownloadUrls['1.20.4']='https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar'
serverDownloadUrls['1.21.0']='https://piston-data.mojang.com/v1/objects/450698d1863ab5180c25d7c804ef0fe6369dd1ba/server.jar'

# Fabric Versions
# curl -OJ https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.14.22/0.11.2/server/jar
serverDownloadUrls['1.19.2-0.15.3-fabric']='https://meta.fabricmc.net/v2/versions/loader/1.19.2/0.15.3/1.0.0/server/jar'
serverDownloadUrls['1.19.2-0.14.22-fabric']='https://meta.fabricmc.net/v2/versions/loader/1.19.2/0.14.22/1.0.0/server/jar'
serverDownloadUrls['1.20.1-fabric']='https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.14.22/0.11.2/server/jar'
serverDownloadUrls['1.20.2-fabric']='https://meta.fabricmc.net/v2/versions/loader/1.20.2/0.14.22/0.11.2/server/jar'

# Forge Versions
serverDownloadUrls['forge-1.12.2-14.23.5.2860']='https://maven.minecraftforge.net/net/minecraftforge/forge/1.12.2-14.23.5.2860/forge-1.12.2-14.23.5.2860-installer.jar'
serverDownloadUrls['forge-1.16.5-36.2.27']='https://maven.minecraftforge.net/net/minecraftforge/forge/1.16.5-36.2.27/forge-1.16.5-36.2.27-installer.jar'
serverDownloadUrls['forge-1.16.5-36.2.34']='https://maven.minecraftforge.net/net/minecraftforge/forge/1.16.5-36.2.34/forge-1.16.5-36.2.34-installer.jar'

# Latest versions
latestSnapshot='24w21a'
latestRelease='1.21.0'

# Latest download URLs
latestSnapshotDownloadUrl="${serverDownloadUrls[${latestSnapshot}]}"
latestReleaseDownloadUrl="${serverDownloadUrls[${latestRelease}]}"
