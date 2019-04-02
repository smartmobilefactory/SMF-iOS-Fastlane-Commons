#################################
### smf_generate_jenkinsfile ###
#################################

TEMPLATE_APP_FILENAME = "App_Jenkinsfile.template"
TEMPLATE_POD_FILENAME = "Pod_Jenkinsfile.template"
JENKINSFILE_FILENAME = "Jenkinsfile"
BUILD_VARIANTS_PATTERN = "__BUILD_VARIANTS__"
POD_DEFAULT_VARIANTS = ["unit_tests", "patch", "minor", "major", "current", "breaking", "internal"]

def is_pod
	framework_variant = @smf_fastlane_config[:build_variants][:framework]

	# First we just check if there's a framework variant and if it's valid.
	if framework_variant != nil 
		if variant[:podspec_path] != nil && variant[:pods_specs_repo] != nil 
			return true
		else
			UI.user_error!("Found framework variant without podspec_path or pods_specs_repo. Please check your Config.json")
		end
	end

	# We also check if there's a variant that contains a podspec_path and pods_specs_repo (in case it is not named framework).
	is_pod_framework = false
	@smf_fastlane_config[:build_variants].each do |variant_key, variant_value|
		if variant_value[:podspec_path] != nil && variant_value[:pods_specs_repo] != nil
			is_pod_framework = true
			return is_pod_framework
		end
	end

	return is_pod_framework
end

desc "Generates a Jenkinsfile based on the fastlane commons template and options from Config.json"
private_lane :smf_generate_jenkins_file do |options|
	is_pod_repo = is_pod

	template_filename = is_pod_repo ? TEMPLATE_POD_FILENAME : TEMPLATE_APP_FILENAME
	jenkinsFileData = File.read("#{@fastlane_commons_dir_path}/pipeline/#{template_filename}")

	build_variants = []

	# If we're building a Pod, exclude the framework variant from the variants list
	if is_pod_repo
		UI.message("Updating POD Jenkinsfile...")
		build_variants_from_config = @smf_fastlane_config[:build_variants].select { |variant_key, variant_value|
			variant_value[:podspec_path] == nil && variant_value[:pods_specs_repo] == nil
		}.keys
		build_variants_from_config.push(*POD_DEFAULT_VARIANTS)
	else
		UI.message("Updating APP Jenkinsfile...")
		build_variants_from_config = @smf_fastlane_config[:build_variants].keys
	end

	build_variants_from_config.each do |variant|
		build_variants.push(variant)
	end

	UI.message(build_variants)

	jenkinsFileData = jenkinsFileData.gsub("#{BUILD_VARIANTS_PATTERN}", JSON.dump(build_variants))
	File.write("#{smf_workspace_dir}/#{JENKINSFILE_FILENAME}", jenkinsFileData)
end

###############################
### smf_update_jenkins_file ###
###############################

desc "Generates a Jenkinsfile and commits it if there are changes"
private_lane :smf_update_jenkins_file do |options|
	smf_generate_jenkins_file

	something_to_commit = false

	Dir.chdir(smf_workspace_dir) do
		something_to_commit = 'git status --porcelain'.include? "#{JENKINSFILE_FILENAME}"
	end

	UI.message("Checking for Jenkinsfile changes...")

	# If something changed in config
	if something_to_commit
		UI.message("Jenkinsfile changed since last build, will synchronize and commit the changes...")

		branch = git_branch
		sh("git", "fetch")
		sh("git", "checkout", branch)
		sh("git", "pull")
		git_add(path: "./#{JENKINSFILE_FILENAME}")
		git_commit(path: ".", message: "Updated Jenkinsfile")

		# push_to_git_remote(
		# remote: "origin",
		# 	remote_branch: ENV["CHANGE_BRANCH"],
		# 	force: false
		# )

		UI.user_error!("Jenkinsfile changed since last build, build will be restarted. This is not a failure.")
	else
		UI.message("Jenkinsfile is up to date...")
	end
end