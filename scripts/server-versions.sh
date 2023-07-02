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

# Releases
serverDownloadUrls['1.16.1']='https://launcher.mojang.com/v1/objects/a412fd69db1f81db3f511c1463fd304675244077/server.jar'
serverDownloadUrls['1.16.2']='https://launcher.mojang.com/v1/objects/c5f6fb23c3876461d46ec380421e42b289789530/server.jar'
serverDownloadUrls['1.16.3']='https://launcher.mojang.com/v1/objects/f02f4473dbf152c23d7d484952121db0b36698cb/server.jar'
serverDownloadUrls['1.16.4']='https://launcher.mojang.com/v1/objects/35139deedbd5182953cf1caa23835da59ca3d7cd/server.jar'
serverDownloadUrls['1.16.5']='https://launcher.mojang.com/v1/objects/1b557e7b033b583cd9f66746b7a9ab1ec1673ced/server.jar'
serverDownloadUrls['1.17.1']='https://launcher.mojang.com/v1/objects/a16d67e5807f57fc4e550299cf20226194497dc2/server.jar'
serverDownloadUrls['1.19.4']='https://piston-data.mojang.com/v1/objects/8f3112a1049751cc472ec13e397eade5336ca7ae/server.jar'
serverDownloadUrls['1.20.0']='https://piston-data.mojang.com/v1/objects/15c777e2cfe0556eef19aab534b186c0c6f277e1/server.jar'

# Latest versions
latestSnapshot='23w18a'
latestRelease='1.20.0'

# Latest download URLs
latestSnapshotDownloadUrl="${serverDownloadUrls[${latestSnapshot}]}"
latestReleaseDownloadUrl="${serverDownloadUrls[${latestRelease}]}"
