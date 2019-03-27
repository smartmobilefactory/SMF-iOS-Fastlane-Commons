####################################################
### smf_install_pods_if_project_contains_podfile ###
####################################################

desc "Runs pod install if the project contains a Podfile"
private_lane :smf_install_pods_if_project_contains_podfile do |options|

  podfile = "#{smf_workspace_dir}/Podfile"

  if File.exist?(podfile)
    cocoapods(
      podfile: podfile,
      use_bundle_exec: false
    )
  else
    UI.message("Didn't install Pods as the project doesn't contain a Podfile")
  end

end

####################
### smf_pod_push ###
####################

desc "Release a new Pod version"
private_lane :smf_pod_push do |options|

  # Variables 
  build_variant_config = @smf_fastlane_config[:build_variants][@smf_build_variant_sym]
  podspec_path = build_variant_config[:podspec_path]
  specs_repo = build_variant_config[:pods_specs_repo]
  workspace_dir = smf_workspace_dir

  sh "which pod"
  sh "pod --version"

  if specs_repo
  	sh "cd #{workspace_dir}; pod repo push #{specs_repo} #{podspec_path} --allow-warnings --skip-import-validation"
  else
  	sh "cd #{workspace_dir}; pod trunk push #{podspec_path}"
  end

end
