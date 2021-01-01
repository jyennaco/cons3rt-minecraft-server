FROM pycons3rt3:v0-ubi
USER root
RUN yum -y update
RUN mkdir -p /root/bin/homer/src
RUN mkdir -p /usr/homer
COPY . /usr/homer
WORKDIR /usr/homer
RUN pip install --no-cache-dir -r ./cfg/requirements.txt
RUN python setup.py install
CMD /bin/bash

# Build
# docker build -t homer:v20.23 .

# Run and mount Homer directories
# docker run --rm -it -v ~/.cons3rt:/root/.cons3rt -v ~/bin:/root/bin -v homer:v20.23

# Run specific homer commands
# docker run --rm -it -v ~/.cons3rt:/root/.cons3rt homer:v20.23 homer version
