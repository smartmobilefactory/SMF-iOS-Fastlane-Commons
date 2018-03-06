def smf_is_jenkins_environment
  return ENV["JENKINS_URL"]
end
