FROM debian:latest
USER root

ENV MINECRAFT_VERSION=1.16.5
ENV SERVER_DOWNLOAD_URL=https://launcher.mojang.com/v1/objects/1b557e7b033b583cd9f66746b7a9ab1ec1673ced/server.jar

# Minecraft directories
ENV minecraftServerDir=/opt/Minecraft_Servers
ENV worldsDir=$minecraftServerDir/worlds
ENV worldDir=$worldsDir/world
ENV serverConfigFile=$worldDir/server-version.sh
ENV serverJarsDir=$minecraftServerDir/server_jars
ENV modsDir=$minecraftServerDir/mods
ENV scriptsDir=$minecraftServerDir/scripts
ENV backupsDir=$minecraftServerDir/backups
ENV logDir=$minecraftServerDir/log

# Upgrade and install packages
RUN apt-get -y update \
    && apt-get -y upgrade \
    && apt -y install curl software-properties-common default-jdk screen \
    && mkdir -p $scriptsDir

# Stage the entrypoint and management scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/* $scriptsDir/

# Configure the server
RUN useradd -d '/home/minecraft' -s '/bin/bash' -c 'Minecraft User' minecraft \
    && mkhomedir_helper minecraft \
    && useradd -d '/home/mcbackup' -s '/bin/bash' -c 'Minecraft Backup User' mcbackup \
    && mkhomedir_helper mcbackup \
    && mkdir -p $minecraftServerDir \
    && mkdir -p $worldsDir \
    && mkdir -p $worldDir \
    && mkdir -p $serverJarsDir/$MINECRAFT_VERSION \
    && mkdir -p $modsDir \
    && mkdir -p $backupsDir \
    && mkdir -p $logDir \
    && chmod 750 $scriptsDir/*.sh \
    && curl -o $serverJarsDir/$MINECRAFT_VERSION/server.jar $SERVER_DOWNLOAD_URL \
    && sed -i "s|REPLACE_WORLDS_DIR|$worldsDir|g" /usr/local/bin/entrypoint.sh \
    && sed -i "s|REPLACE_SCRIPTS_DIR|$scriptsDir|g" /usr/local/bin/entrypoint.sh \
    && sed -i "s|REPLACE_VERSION|$MINECRAFT_VERSION|g" /usr/local/bin/entrypoint.sh \
    && chown minecraft:minecraft /usr/local/bin/entrypoint.sh \
    && chmod 700 /usr/local/bin/entrypoint.sh \
    && echo 'MINECRAFT_WORLD=world' > $minecraftServerDir/config.sh \
    && chown -R minecraft:minecraft $minecraftServerDir

# Set minecraft as the user to run the server
USER minecraft

WORKDIR $minecraftServerDir/
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/start-server.sh"]

# Build
# docker build -t minecraft:1.16.5 .

# Run and mount a world directory
# docker run -it --detach -v ~/Downloads/world:/opt/Minecraft_Servers/worlds/world -p 25565:25565 --name world1 minecraft:1.16.5

