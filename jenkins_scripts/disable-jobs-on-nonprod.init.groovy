import jenkins.model.Jenkins
import java.util.logging.LogManager

/* Jenkins home directory */ 
def jenkinsHome = Jenkins.instance.getRootDir().absolutePath
def logger = LogManager.getLogManager().getLogger("")

if (System.getenv('jenkins-domain-url') == 'https://jenkins.somedomain.com') {
  logger.info("Domain url is nonprod, so disabling all multibranch jobs.")

  logger.info("Preventing new buiilds.")
  Jenkins.instance.doQuietDown()
  logger.info("Cancelling queued builds.")
  Jenkins.instance.queue.clear()
  logger.info("Disabling all multibranch pipelines.")
  Jenkins.instance.getAllItems(
    org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject.class
  ).each {
    i -> i.setDisabled(true)
    i.save()
    logger.info("Successfully disabled job: " + i)
  }
  // Jenkins.instance.doCancelQuietDown()
} else {
  logger.info("Domain url is not nonprod, so leaving jobs enabled.")
}