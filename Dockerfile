# Version 0.1
FROM ipython/scipystack

MAINTAINER Bernardo Gomez Palacio "bernardo.gomezpalacio@gmail.com"
ENV REFRESHED_AT 2015-03-19

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get dist-upgrade -y

# RUN echo "deb http://repos.mesosphere.io/ubuntu/ trusty main" > /etc/apt/sources.list.d/mesosphere.list
# RUN apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
# RUN apt-get -y update
# RUN apt-get -y install mesos=0.26.0-0.2.145.ubuntu1404

# Setup
RUN sudo apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
RUN export OS_DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]') && \
    export OS_CODENAME=$(lsb_release -cs) && \
    echo "deb http://repos.mesosphere.io/${OS_DISTRO} ${OS_CODENAME} main" | \
    tee /etc/apt/sources.list.d/mesosphere.list &&\
    apt-get -y update

RUN apt-get -y install mesos

RUN apt-get install -y python libnss3 curl

#RUN add-apt-repository ppa:webupd8team/java -y && \
#    apt-get install oracle-java8-installer && \
#    apt-get install oracle-java8-set-default

# echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee /etc/apt/sources.list.d/webupd8team-java.list
# echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list
# apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886
# apt-get update
# apt-get install oracle-java8-installer

RUN curl http://d3kbcqa49mib13.cloudfront.net/spark-1.6.0-bin-hadoop2.6.tgz \
    | tar -xzC /opt && \
    mv /opt/spark* /opt/spark

RUN apt-get clean

# Fix pypspark six error.
RUN pip2 install -U six
RUN pip2 install boto
RUN pip2 install msgpack-python
RUN pip2 install avro

COPY spark-conf/* /opt/spark/conf/
COPY scripts /scripts

ENV SPARK_HOME /opt/spark

ENTRYPOINT ["/scripts/run.sh"]

