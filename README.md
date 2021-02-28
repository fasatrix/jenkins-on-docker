# jenkins-on-docker
# Environment: Windows OS with Docker version 20.10.2 (build 2291f61) - switch to LINUX container 
Instructions:
* ```cd c:\```
* ```git clone https://github.com/fasatrix/jenkins-on-docker.git```
* ```cd jenkins-on-docker``` 
* your prompt should be ```c:/jenkins-on-docker```
* ```docker  build --no-cache -t jenkins .```
* be patient until the image has been built (some plugins could take a while to download/install)
* ```docker run -d --name jenkins -v C:/docker-on-jenkins/casc_config/anonymous_config.yml:/var/jenkins_home/casc_configs/azure_config.yml --env-file ./env.list jenkins```
* ```docker logs jenkins```
