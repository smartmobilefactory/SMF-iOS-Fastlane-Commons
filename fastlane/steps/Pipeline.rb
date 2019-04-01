#################################
### smf_generate_jenkins_file ###
#################################

desc "Generates a jenkins file based on the fastlane commons template and options from Config.json"
private_lane :smf_generate_jenkins_file do |options|
	jenkinsFileData = File.read("#{@fastlane_commons_dir_path}/pipeline/App_Jenkinsfile")
 	build_variants = ["Alpha", "Beta", "Live"]
 	
 	build_variants_config = @smf_fastlane_config[:build_variants]
 	
 	build_config_variants = []
 	smf_build_variants_array.each do |variant|
 		build_config_variants.push(variant)
 	end

 	if build_config_variants.length > 0
 		build_variants = build_config_variants
 	end

 	jenkinsFileData = jenkinsFileData.gsub("__BUILD_VARIANTS__", JSON.dump(build_variants))
	File.write("#{smf_workspace_dir}/Jenkinsfile", jenkinsFileData)
end