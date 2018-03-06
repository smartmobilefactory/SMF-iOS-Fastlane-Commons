def smf_is_jenkins_environment
  return ENV["JENKINS_URL"]
end

def smf_workspace_dir
  if smf_is_jenkins_environment
    return ENV[$WORKSPACE_ENV_KEY]
  else
    path = "#{Dir.pwd}"
    if path.end_with?("/fastlane")
      path = path.chomp("/fastlane") 
    end
    UI.message("Fastlane doesn't seem to run in a Jenkins environement. The workspace path is \"#{path}\"")
    return path
  end
end
