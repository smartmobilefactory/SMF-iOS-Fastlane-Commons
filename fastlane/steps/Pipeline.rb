#################################
### smf_generate_jenkins_file ###
#################################

desc "Generates a jenkins file based on the fastlane commons template and options from Config.json"
private_lane :smf_generate_jenkins_file do |options|
	UI.important("Reading template")
	UI.important("Workspace #{smf_workspace_dir}")

	jenkinsFileData = File.read("#{@fastlane_commons_dir_path}/pipeline/App_Jenkinsfile")
 	build_variants = ["Alpha", "Beta", "Live"]
 	
 	UI.important("Default variants #{build_variants}")

 	build_variants_from_config = @smf_fastlane_config[:build_variants].keys

	UI.important("Config variants #{build_variants_from_config}")
 	
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