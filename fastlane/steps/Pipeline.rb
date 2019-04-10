#################################
### smf_generate_jenkinsfile ###
#################################

TEMPLATE_JENKINSFILE_APP_FILENAME = "App_Jenkinsfile.template"
TEMPLATE_JENKINSFILE_POD_FILENAME = "Pod_Jenkinsfile.template"
TEMPLATE_GEMFILE_APP_FILENAME = "App_Gemfile.template"
TEMPLATE_GEMFILE_POD_FILENAME = "Pod_Gemfile.template"
JENKINSFILE_FILENAME = "Jenkinsfile"
GEMFILE_FILENAME = "Gemfile"
BUILD_VARIANTS_PATTERN = "__BUILD_VARIANTS__"
POD_EXAMPLE_VARIANTS_PATTERN = "__EXAMPLE_VARIANTS__"
POD_DEFAULT_VARIANTS = ["unit_tests", "patch", "minor", "major", "current", "breaking", "internal"]

desc "Checks if the repository is a Pod"
def is_pod
	framework_variant = @smf_fastlane_config[:build_variants][:framework]

	# First we just check if there's a framework variant and if it's valid.
	if framework_variant != nil 
		if framework_variant[:podspec_path] != nil && framework_variant[:pods_specs_repo] != nil 
			return true
		else
			UI.user_error!("Found framework variant without podspec_path or pods_specs_repo. Please check your Config.json")
		end
	end

	# We also check if there's a variant that contains a podspec_path and pods_specs_repo (in case it is not named framework).
	@smf_fastlane_config[:build_variants].each do |variant_key, variant_value|
		if variant_value[:podspec_path] != nil && variant_value[:pods_specs_repo] != nil
			UI.important("Found POD variant not named 'framework'. Please check your Config.json")
			return true
		end
	end

	return false
end

desc "Generates a Jenkinsfile based on the fastlane commons template and options from Config.json"
desc "Alsp generates the Gemfile"
private_lane :smf_generate_setup_files do |options|
	is_pod_repo = is_pod

	template_filename = is_pod_repo ? TEMPLATE_JENKINSFILE_POD_FILENAME : TEMPLATE_JENKINSFILE_APP_FILENAME
	jenkinsFileData = File.read("#{@fastlane_commons_dir_path}/pipeline/#{template_filename}")

	build_variants_from_config = []

	# If we're building a Pod, exclude the framework variant from the variants list
	if is_pod_repo
		UI.message("Updating POD Jenkinsfile...")
		# We will exclude the "framework" variant from the list of variants, it should not be available as a triger.
		build_variants_from_config = @smf_fastlane_config[:build_variants].select { |variant_key, variant_value|
			variant_value[:podspec_path] == nil && variant_value[:pods_specs_repo] == nil
		}.keys

		jenkinsFileData = jenkinsFileData.gsub("#{POD_EXAMPLE_VARIANTS_PATTERN}", JSON.dump(build_variants_from_config))

		# Add the default variants on top of the one discoveres in Config.json
		build_variants_from_config.push(*POD_DEFAULT_VARIANTS)
	else
		UI.message("Updating APP Jenkinsfile...")
		build_variants_from_config = @smf_fastlane_config[:build_variants].keys
  end

	gemfile_template_filename = is_pod_repo ? TEMPLATE_GEMFILE_POD_FILENAME : TEMPLATE_GEMFILE_APP_FILENAME
  gemfileData = File.read("#{@fastlane_commons_dir_path}/pipeline/#{gemfile_template_filename }")
	File.write("#{smf_workspace_dir}/fastlane/#{GEMFILE_FILENAME}", gemfileData)

	jenkinsFileData = jenkinsFileData.gsub("#{BUILD_VARIANTS_PATTERN}", JSON.dump(build_variants_from_config))
	File.write("#{smf_workspace_dir}/#{JENKINSFILE_FILENAME}", jenkinsFileData)
end

###############################
### smf_update_jenkins_file ###
###############################

desc "Generates a Jenkinsfile and commits it if there are changes"
private_lane :smf_update_jenkins_file do |options|
	smf_generate_setup_files

	jenkinsfile_changed = false
  gemfile_changed = false

	Dir.chdir(smf_workspace_dir) do
		jenkinsfile_changed = `git status --porcelain`.include? "#{JENKINSFILE_FILENAME}"
		gemfile_changed = `git status --porcelain`.include? "#{GEMFILE_FILENAME}"
	end

	UI.message("Checking for Jenkinsfile changes...")

	# If something changed in config
	if jenkinsfile_changed or gemfile_changed
		UI.message("Jenkinsfile changed since last build, will synchronize and commit the changes...")

		git_add(path: "./#{JENKINSFILE_FILENAME}")
		git_add(path: "./fastlane/#{GEMFILE_FILENAME}")
		git_add(path: "./fastlane/#{GEMFILE_FILENAME}.lock")
		git_commit(path: ".", message: "Updated Generated SetupFiles")

		push_to_git_remote(
		remote: "origin",
			remote_branch: ENV["CHANGE_BRANCH"],
			force: false
		)

		UI.user_error!("Generated Files changed since last build, build will be restarted. This is not a failure.")
	else
		UI.success("Jenkinsfile is up to date. Nothing to do.")
	end
end