#################################
### smf_generate_jenkins_file ###
#################################

desc "Generates a jenkins file based on the fastlane commons template and options from Config.json"
private_lane :smf_generate_jenkins_file do |options|
	jenkinsFileData = File.read("#{@fastlane_commons_dir_path}/pipeline/App_Jenkinsfile")
 	build_variants = ["Alpha", "Beta", "Live"]

 	build_variants_from_config = @smf_fastlane_config[:build_variants].keys
 	
 	build_config_variants = []
 	build_variants_from_config.each do |variant|
 		build_config_variants.push(variant)
 	end

 	if build_config_variants.length > 0
 		build_variants = build_config_variants
 	end

 	jenkinsFileData = jenkinsFileData.gsub("__BUILD_VARIANTS__", JSON.dump(build_variants))
	File.write("#{smf_workspace_dir}/Jenkinsfile", jenkinsFileData)
end

###############################
### smf_update_jenkins_file ###
###############################

desc "Generates a Jenkins file and commits it if there are changes"
private_lane :smf_update_jenkins_file do |options|
	smf_generate_jenkins_file

	something_to_commit = false

	Dir.chdir(smf_workspace_dir) do
    	something_to_commit = !`git status --porcelain`.include? 'Jenkinsfile'
  	end

  	UI.message("Checking for Jenkins file changes...")

  	# If something changed in config
  	if something_to_commit
  		UI.message("Jenkins file changed since last build, will synchronize and commit the changes...")

  		branch = git_branch
    	sh("git", "fetch")
    	sh("git", "checkout", branch)
    	sh("git", "pull")
    	git_add(path: '.')
    	git_commit(path: '.', message: "Updated Jenkins file")

    	# push_to_git_remote(
     #  		remote: 'origin',
     #  		remote_branch: ENV["CHANGE_BRANCH"],
     #  		force: false
    	# )

  		UI.user_error!("Build will be restarted. This is not a failure.")
  	else
  		UI.message("Jenkins file is up to date...")
  	end
end