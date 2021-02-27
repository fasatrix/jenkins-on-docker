FROM adoptopenjdk/openjdk11:jdk-11.0.10_9-alpine AS jenkins

RUN apk add --no-cache \
  bash \
  coreutils \
  curl \
  git \
  git-lfs \
  openssh-client \
  tini \
  ttf-dejavu \
  tzdata \
  unzip

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home
ARG REF=/usr/share/jenkins/ref

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}
ENV REF $REF

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown ${uid}:${gid} $JENKINS_HOME \
  && addgroup -g ${gid} ${group} \
  && adduser -h "$JENKINS_HOME" -u ${uid} -G ${group} -s /bin/bash -D ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# $REF (defaults to `/usr/share/jenkins/ref/`) contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p ${REF}/init.groovy.d

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.235.4}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=e5688a8f07cc3d79ba3afa3cab367d083dd90daab77cebd461ba8e83a1e3c177

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" "$REF"

ARG PLUGIN_CLI_URL=https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.2.0/jenkins-plugin-manager-2.2.0.jar
RUN curl -fsSL ${PLUGIN_CLI_URL} -o /usr/lib/jenkins-plugin-manager.jar

# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER ${user}

COPY jenkins_scripts/jenkins-support.sh /usr/local/bin/jenkins-support
COPY jenkins_scripts/jenkins.sh /usr/local/bin/jenkins.sh
COPY jenkins_scripts/tini-shim.sh /bin/tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]
COPY jenkins_scripts/jenkins-plugin-cli.sh /bin/jenkins-plugin-cli

USER root
RUN chmod +x /usr/local/bin/jenkins-support /usr/local/bin/jenkins.sh /bin/tini /bin/jenkins-plugin-cli
USER jenkins

FROM alpine:latest AS newrelic
RUN apk add --no-cache curl unzip
RUN curl https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic-java.zip -o /tmp/newrelic-java.zip
RUN unzip /tmp/newrelic-java.zip -d /tmp

FROM jenkins AS plugins
#
USER jenkins
#
## skip the jenkins wizard setup
ENV JAVA_OPTS "-Djava.awt.headless=true \
-Djenkins.install.runSetupWizard=false \
-server \
-XX:+AlwaysPreTouch \
-XX:MaxRAMPercentage=80 \
-Dhudson.model.DirectoryBrowserSupport.CSP \
-Dorg.apache.commons.jelly.tags.fmt.timeZone=Pacific/Auckland \
-Dhudson.slaves.NodeProvisioner.initialDelay=0 \
-Dhudson.slaves.NodeProvisioner.MARGIN=50 \
-Dhudson.slaves.NodeProvisioner.MARGIN0=0.85 \
-Djenkins.model.Jenkins.logStartupPerformance=true \
-javaagent:/opt/newrelic.jar"

# initialise Jenkins using the configuration-as-code plugin
COPY --chown=jenkins:jenkins plugins.txt "$JENKINS_HOME"/ref/
RUN /bin/jenkins-plugin-cli --verbose --latest false -f "$JENKINS_HOME"/ref/plugins.txt

FROM plugins

COPY --from=newrelic /tmp/newrelic/newrelic.jar /opt/newrelic.jar

COPY --chown=jenkins:jenkins casc_config/config.yml casc_config/ec2-agent-config.yml $JENKINS_HOME/casc_configs/
# Do not add ec2 slave config for local testing
# COPY casc_config/config.yml $JENKINS_HOME/casc_configs/
# Use anonymous config only for testing purposes
# COPY casc_config/anonymous_config.yml $JENKINS_HOME/casc_configs/
COPY --chown=jenkins:jenkins casc_config/azure_config.yml $JENKINS_HOME/casc_configs/
# Add configuration for job seeding
COPY --chown=jenkins:jenkins casc_config/jobs/* $JENKINS_HOME/casc_configs/
# Add configuration for views
COPY --chown=jenkins:jenkins casc_config/views/* $JENKINS_HOME/casc_configs/

RUN mkdir $JENKINS_HOME/init.groovy.d
COPY --chown=jenkins:jenkins jenkins_scripts/disable-jobs-on-nonprod.init.groovy $JENKINS_HOME/init.groovy.d
ENV CASC_JENKINS_CONFIG $JENKINS_HOME/casc_configs
VOLUME $JENKINS_HOME
