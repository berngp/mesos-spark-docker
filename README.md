# Running Your Spark Job Executors In Docker Containers

  The following tutorial showcases a _Dockerized_ _Apache Spark_ application running in a _Mesos_ cluster.
In the example the _Spark Driver_, as well as the _Spark Executors_, will be running in a _Docker Image_ based on Ubuntu with the
additions of the [SciPy][SCIPY] Python packages. If you are already familiar with the reasons of using Docker
as well as Apache Mesos feel free to skip the next section and jump right into the tutorial, if not, please carry on.

## Rational

  Today is pretty common to find Engineers and Data Scientist that need to run _Big Data workloads_ inside a
shared infrastructure. In addition the infrastructure could potentially be used not only for such workloads but
to server other important services required for business operations. All these amalgamates to a none trivial infrastructure
and provisioning conundrum.

  A very common way to solve such problem is to virtualize the infrastructure and statically partition it such that each group
has its own resources to deploy and run their applications. Hopefully the maintainers of such infrastructure and services have a _DevOps_ mentality and
have automated, and continuously work on automating, the configuration and software provisioning tasks on such infrastructure.
The problem is, as [Benhamin Hindman][MESOS_WHY] backed by [studies][MESOS_WP] done at the University of California at Berkeley
points out, static partitioning can be highly inefficient on the utilization of such infrastructure. This has prompted the development
of _Resource Schedulers_ that abstracts CPU, memory, storage, and other compute resources away from machines, either physical or virtual,
to enable the execution of applications across the infrastructure to achieve a higher utilization factor, among other things.

  The concept of sharing infrastructure resources is not new for applications that entail the analysis of large datasets, in most cases through
algorithms that favor parallelization of workloads. Today the most common frameworks to develop such applications are _Hadoop Map Reduce_ and
_Apache Spark_. In the case of _Apache Spark_ it can be deployed in clusters managed by _Resource Schedulers_ such as Hadoop YARN or Apache Mesos.
Now, since different applications are running inside a shared infrastructure its common to find applications that have different sets of requirements
across the packages and versions they depend on to function. As an operation engineer, or infrastructure manager, you could force your users to a predefine set of
software libraries, along with their versions, that the infrastructure supports. Hopefully if you follow that path you also establish a procedure to
upgrade such software libraries and add new ones. This tends to require an investment in time and might be frustrating to Engineers and Data Scientist that
are constantly installing new packages and libraries to facilitate their work. When you decide to upgrade you might as well have to refactor some applications
that might have been running for a long time but have hard dependencies on previous versions of the packages that are part of the upgraded. All in all, its not simple.

  Linux Containers, and specially Docker, offer an abstraction such that software can be packaged into light weight images that can be executed as containers. The containers are executed with some level of isolation, such isolation is mainly provided by _cgroups_. Each image can define the type of operating system that it requires along with the software packages. This provides a
fantastic mechanism to pass the burden of maintaining the software packages and libraries out of infrastructure management and operations to the owners of the applications.
With this the infrastructure and operation teams can run multiple, isolated, applications that can potentially have conflicting software libraries within the same infrastructure. _Apache Spark_ can leverage this as long as its deployed with an _Apache Mesos_ cluster that supports Docker.

In the next sections we will review how we can run Apache Spark Applications within Docker containers.

## Tutorial

  For this tutorial we will use a CentOS 7.2 minimal image running on [VirtualBox][VBOX]. We will
not include as part of this tutorial the instructions on obtaining such CentOS Image and making
it available in _VirtualBox_ nor configuring its network interfaces.

  In addition to the above we will be using a single node to keep this exercise as simple as possible.
We can later explore deploying a similar setup in a set of nodes in the cloud but for the sake of simplicity and time
our single node will be running the following services:

* A Mesos Master
* A Mesos Slave
* A Zookeeper Instance
* A Docker Daemon

### Step 1: The Mesos Cluster

To install _Apache Mesos_ in your cluster I suggest you follow the [Mesosphere getting started guidelines][MESOSPHERE_GS].
Since we are using CentOS 7.2 we first installed the _Mesosphere YUM Repository_ as follows:

    # Add the repository
    sudo rpm -Uvh http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-1.noarch.rpm

We then install _Apache Mesos_ and the _Apache Zookeeper_ packages.

    sudo yum -y install mesos mesosphere-zookeeper

Once the packages are installed we need to configure Zookeeper as well as the Mesos Master and Slave.

#### Zookeeper

For Zookeeper we need to create a Zookeeper Node Identity, we do this my setting the numerical identifying inside
the `/var/lib/zookeeper/myid` file.

    echo "1" > /var/lib/zookeeper/myid

Since by default Zookeeper binds to all interfaces and exposes its services through port `2181` we do not need to
change the `/etc/zookeeper/conf/zoo.cfg` file. Please refer to the [Mesosphere getting started guidelines][MESOSPHERE_GS]
if you have a Zookeeper ensemble, more than one node running Zookeeper. After that we can start the Zookeeper Service.

    sudo service zookeeper restart

#### Mesos Master and Slave

Before we start to describe the Mesos configuration we most note that the location of the Mesos configuration files that
we are going to mention bellow is specific to Mesosphere's Mesos package. If you don't have a strong reason to build
your own Mesos packages I suggest you use the ones that Mesosphere kindly provides. Lets continue.

We need to tell the Mesos Master and Slave the connection string the they can use to reach Zookeeper, including their namespace.
By default Zookeeper will bind to all interfaces, you might want to change this behaviour.
In our case we will make sure that the IP address that we want to use to connect to Zookeeper can be resolved within the
containers. The nodes public interface IP `192.168.99.100`, to do this we do the following:

    echo "zk://192.168.99.100:2181/mesos" > /etc/mesos/zk


Now since in our setup we have several network interfaces associated with the node that will be running the Mesos Master we will
pick an interface that will be reachable within the Docker containers that will eventually be running the Spark Driver and Spark Executors.
Knowing that the IP address that we want to bind to is `192.168.99.100` we do the following:

    echo "192.168.99.100" > /etc/mesos-master/ip

We do a similar thing for the Mesos Slave, again, please consider that in our example the Mesos Slave is running in the same node as the
Mesos Master and we are going to bind it to the same network interface.

    echo "192.168.99.100" > /etc/mesos-slave/ip
    echo "192.168.99.100" > /etc/mesos-slave/hostname

The `ip` defines the IP address that the Mesos Slave is going to bind to and `hostname` defines the _hostname_ that the slave will use to report
its availability and therefore is the value that the _Mesos Frameworks_, in our case _Apache Spark_, will use to connect to it.

Lets start the services

    systemctl start mesos-master
    systemctl start mesos-slave

By default the Mesos Master will bind to port `5050` and the Mesos Slave to port `5051`. Lets confirm, assuming you have installed the `net-utils` package.

    netstat -pleno | grep -E "5050|5051"
    tcp        0      0 192.168.99.100:5050     0.0.0.0:*               LISTEN      0          127336     22205/mesos-master   off (0.00/0/0)
    tcp        0      0 192.168.99.100:5051     0.0.0.0:*               LISTEN      0          127453     22242/mesos-slave    off (0.00/0/0)

Lets run a test.

    MASTER=$(mesos-resolve `cat /etc/mesos/zk`) \
    LIBPROCESS_IP=192.168.99.100 \
    mesos-execute --master=$MASTER \
                  --name="cluster-test" \
                  --command="echo 'Hello World' &&  sleep 5 && echo 'Good Bye'"


### Step 2: Installing Docker

We followed the Docker documentation on [installing Docker in CentOS][DOCKER_COS]. I suggest you
do the same. In a nutshell we executed the following.

    sudo yum update
    sudo tee /etc/yum.repos.d/docker.repo <<-'EOF'
    [dockerrepo]
    name=Docker Repository
    baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
    enabled=1
    gpgcheck=1
    gpgkey=https://yum.dockerproject.org/gpg
    EOF
    sudo yum install docker-engine
    sudo service docker start

If the above succeeded you should be able to do a `docker ps` as well as a `docker search ipython/scipystack` successfully.

### Step 3: Creating a Spark Image

Lets create the Dockerfile that will be used by the Spark Driver and Spark Executor. For our example we will consider
that the Docker Image should provide the SciPy Stack along with additional Python libraries.
So, in a nutshell, the Docker Image most have the following features:

1. The version of libmesos should be compatible with the version of the Mesos Master and Slave.  e.g. `/usr/lib/libmesos-0.26.0.so`
1. Should have a valid JDK.
1. Should have the SciPy Stack as well as Python packages that we want.
1. Have a version of Spark, we will choose 1.6.0


The Dockerfile bellow will provide the requirements that we mention above. Note that installing Mesos
through the _Mesosphere RPMs_ will install _Open JDK_, in this case `1.7`.

Dockerfile:

    # Version 0.1
    FROM ipython/scipystack
    MAINTAINER Bernardo Gomez Palacio "bernardo.gomezpalacio@gmail.com"
    ENV REFRESHED_AT 2015-03-19

    ENV DEBIAN_FRONTEND noninteractive

    RUN apt-get update
    RUN apt-get dist-upgrade -y

    # Setup
    RUN sudo apt-key adv --keyserver keyserver.ubuntu.com --recv E56151BF
    RUN export OS_DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]') && \
        export OS_CODENAME=$(lsb_release -cs) && \
        echo "deb http://repos.mesosphere.io/${OS_DISTRO} ${OS_CODENAME} main" | \
        tee /etc/apt/sources.list.d/mesosphere.list &&\
        apt-get -y update

    RUN apt-get -y install mesos

    RUN apt-get install -y python libnss3 curl

    RUN curl http://d3kbcqa49mib13.cloudfront.net/spark-1.6.0-bin-hadoop2.6.tgz \
        | tar -xzC /opt && \
        mv /opt/spark* /opt/spark

    RUN apt-get clean

    # Fix pypspark six error.
    RUN pip2 install -U six
    RUN pip2 install msgpack-python
    RUN pip2 install avro

    COPY spark-conf/* /opt/spark/conf/
    COPY scripts /scripts

    ENV SPARK_HOME /opt/spark

    ENTRYPOINT ["/scripts/run.sh"]


Lets explain some very important files that will be available in the Docker Image according to the
Dockerfile mentioned above:

The `spark-conf/spark-env.sh`, as mentioned in the [Spark docs][SPARK_MMASTER], will be used to set the
location of the Mesos `libmesos.so`.


    export MESOS_NATIVE_JAVA_LIBRARY=${MESOS_NATIVE_JAVA_LIBRARY:-/usr/lib/libmesos.so}


The `spark-conf/spark-defaults.conf` is serves as the definition of the default configuration for our
Spark Jobs within the container, the contents are bellow.

    spark.master                      SPARK_MASTER
    spark.mesos.mesosExecutor.cores   MESOS_EXECUTOR_CORE
    spark.mesos.executor.docker.image SPARK_IMAGE
    spark.mesos.executor.home         /opt/spark
    spark.driver.host                 CURRENT_IP
    spark.executor.extraClassPath     /opt/spark/custom/lib/*
    spark.driver.extraClassPath       /opt/spark/custom/lib/*

Note the use of environment variables such as `SPARK_MASTER` and `SPARK_IMAGE` are critical since
this will allow us to customize how the Spark Application interacts with Mesos Docker integration.

We have Docker's entry point script. The script, showcased bellow,
will populate the `spark-defaults.conf` file.


Now lets define the Dockerfile Entrypoint such that it lets us define some basic options that
will get passed to the Spark command, for example `spark-shell`, `spark-submit` or `pyspark`.


    #!/bin/bash

    SPARK_MASTER=${SPARK_MASTER:-local}
    MESOS_EXECUTOR_CORE=${MESOS_EXECUTOR_CORE:-0.1}
    SPARK_IMAGE=${SPARK_IMAGE:-sparkmesos:lastet}
    CURRENT_IP=$(hostname -i)

    sed -i 's;SPARK_MASTER;'$SPARK_MASTER';g' /opt/spark/conf/spark-defaults.conf
    sed -i 's;MESOS_EXECUTOR_CORE;'$MESOS_EXECUTOR_CORE';g' /opt/spark/conf/spark-defaults.conf
    sed -i 's;SPARK_IMAGE;'$SPARK_IMAGE';g' /opt/spark/conf/spark-defaults.conf
    sed -i 's;CURRENT_IP;'$CURRENT_IP';g' /opt/spark/conf/spark-defaults.conf

    if [ $ADDITIONAL_VOLUMES ];
    then
            echo "spark.mesos.executor.docker.volumes: $ADDITIONAL_VOLUMES" >> /opt/spark/conf/spark-defaults.conf
    fi

    exec "$@"



Lets build the image so we can start using it.

    docker build -t sparkmesos . && \
    docker tag -f sparkmesos:latest sparkmesos:latest


### Step 4: Running a Spark Application with Docker.

Now that the image is built we just need to run it. We will call the PySpark application.

    docker run -it --rm \
      -e SPARK_MASTER="mesos://zk://192.168.99.100:2181/mesos" \
      -e SPARK_IMAGE="sparkmesos:latest" \
      -e PYSPARK_DRIVER_PYTHON=ipython2 \
      sparkmesos:latest /opt/spark/bin/pyspark

To make sure that SciPy is working lets write the following to the PySpark shell

    from scipy import special, optimize
    import numpy as np

    f = lambda x: -special.jv(3, x)
    sol = optimize.minimize(f, 1.0)
    x = np.linspace(0, 10, 5000)
    x


Now, depending on the resources available in your cluster you can try to calculate PI

    docker run -it --rm \
      -e SPARK_MASTER="mesos://zk://192.168.99.100:2181/mesos" \
      -e SPARK_IMAGE="sparkmesos:latest" \
      -e PYSPARK_DRIVER_PYTHON=ipython2 \
      sparkmesos:latest /opt/spark/bin/spark-submit --driver-memory 500M \
                                                    --executor-memory 500M \
                                                    /opt/spark/examples/src/main/python/pi.py 1

docker run -it --rm \
      -e SPARK_MASTER="mesos://zk://192.168.99.100:2181/mesos" \
      -e SPARK_IMAGE="sparkmesos:latest" \
      -e PYSPARK_DRIVER_PYTHON=ipython2 \
      sparkmesos:latest /bin/bash 

## Conclusion and further Notes

Although we were able to run a Spark Application within Docker containers in Mesos there is more work to do.
We need to explore containerized Spark Applications that spread across multiple nodes along with providing
a mechanism that enables network port mapping.



## References

1. Apache Mesos. The Apache Software Foundation, 2015. Web. 27 Jan. 2016. <http://mesos.apache.org>.
1. Apache Spark. The Apache Software Foundation, 2015. Web. 27 Jan. 2016. <http://spark.apache.org>.
1. Benjamin Hindman. "Apache Mesos NYC Meetup", August 20, 2013. Web. 27 Jan 2016.  <https://speakerdeck.com/benh/apache-mesos-nyc-meetup>
1. Docker. Docker Inc, 2015. Web. 27 Jan 2016. <https://docs.docker.com/>.
1. Hindman, Konwinski, Zaharia, Ghodsi, D. Joseph, Katz, Shenker, Stoica.
    "Mesos: A Platform for Fine-Grained Resource Sharing in the Data Center"
     Web. 27 Jan 2016. <https://www.cs.berkeley.edu/~alig/papers/mesos.pdf>
1. Mesosphere Inc, 2015. Web. 27 Jan 2016. <https://mesosphere.com/>
1. SciPy.  SciPy developers, 2015. Web. 28 Jan 2016. <http://www.scipy.org/>.
1. Virtual Box, Oracle Inc, 2015. Web 28 Jan 2016. <https://www.virtualbox.org/wiki/Downloads>
1. Wang Qiang, "Docker Spark Mesos". Web 28 Jan 2016. <https://github.com/wangqiang8511/docker-spark-mesos>


[DOCKER_COS]:     https://docs.docker.com/engine/installation/centos/ "Docker CentOS install."
[MESOS_WHY]:      https://speakerdeck.com/benh/apache-mesos-nyc-meetup "Apache Mesos NYC Meetup."
[MESOS_WP]:       https://www.cs.berkeley.edu/~alig/papers/mesos.pdf "Mesos: A Platform for Fine-Grained Resource Sharing in the Data Center."
[SCIPY]:          http://www.scipy.org/ "SciPy: Python based ecosystem for Math, Science, and Engineering."
[SPARK_GUIDE]:    http://spark.apache.org/docs/latest/programming-guide.html "Apache Spark: Programming Guide."
[SPARK_MESOS]:    http://spark.apache.org/docs/latest/running-on-mesos.html "Apache Spark: Running On Mesos."
[SPARK_MMASTER]:  http://spark.apache.org/docs/latest/running-on-mesos.html "Apache Spark: Using a Mesos Master URL"
[VBOX]:           https://www.virtualbox.org/ "VirtualBox"
[MESOSPHERE_GS]:  https://open.mesosphere.com/getting-started/install/ "Mesosphere: Setting up a Mesos and Marathon Cluster"

