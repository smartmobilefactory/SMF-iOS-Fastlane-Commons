####################################################
### smf_install_pods_if_project_contains_podfile ###
####################################################

desc "Runs pod install if the project contains a Podfile"
private_lane :smf_install_pods_if_project_contains_podfile do |options|

  if File.exist?("#{smf_workspace_dir}/Podfile")
    sh "pod install"
  else
    UI.message("Didn't install Pods as the project doesn't contain a Podfile")
  end

end
