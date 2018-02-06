############################
###### General config ######
############################

ENV['BUILD_VARIANT'] == nil ? build_variant = "" : build_variant = ENV['BUILD_VARIANT']
ENV['BUILD_TYPE'] == nil ? build_type = "targets" : build_type = ENV['BUILD_TYPE']
message( "Running danger for build variant **\"" + build_variant + "\"** with build type **\"" + build_type + "\"**")

if File.file?('fastlane/BuildVariants.json')
  config = JSON.parse(File.read('fastlane/BuildVariants.json'))
  project_config = config["project"]
  danger_config = config["danger_config"]
  target_config = config["targets"][build_variant]
  config_parsed = true
else
  warn "No BuildVariants.json found in ./fastlane"
end

if danger_config == nil
  warn "BuildVariants.json did not include danger_config, using defaults."
  danger_config["git.lines_of_code"] = 100
  danger_config["github.pr_body.length"] = 10
  danger_config["github.branch_for_base"] = "develop"
  danger_config["github.pr_title.include"] = "[WIP]"
  config["danger_config"][build_type][build_variant]["notify_if_coverage_is_less_than"] = 30
  config["danger_config"][build_type][build_variant]["notify_if_modified_file_is_less_than"] = 50
end

#####################
###### General ######
#####################

if config_parsed == true
  if git.lines_of_code > danger_config["git.lines_of_code"]
    warn("Big PR")
  end

  if github.pr_body.length < danger_config["github.pr_body.length"]
    warn "Please provide a summary in the Pull Request description"
  end

  if github.branch_for_base != danger_config["github.branch_for_base"]
    warn("Please target PRs to `develop` branch")
  end

  if github.pr_title.include? danger_config["github.pr_title.include"]
    warn("PR is classed as Work in Progress") 
  end
else
  warn("Slather not run: BuildVariants.json wasn't parsed")
end

###################
###### Xcode ######
###################

if danger_config["xcode_summary.report"]
  xcode_summary.report 'build/reports/errors.json'
else
  message( "Skipping Xcode summary report for: " + build_variant + ". Not enabled in BuildVariants.json.")
end

#######################
###### Swiftlint ######
#######################

if danger_config["swiftlint"]
  if File.file?('Pods/SwiftLint/swiftlint')
    swiftlint.binary_path = 'Pods/SwiftLint/swiftlint'
  end

  swiftlint.lint_files
else
  message( "Skipping SwiftLint for: " + build_variant + ". Not enabled in BuildVariants.json.")
end

#####################
###### Slather ######
#####################

if config_parsed == true
  if config[build_type][build_variant]["perform_unit_tests"]
    slather.configure(project_config["project_name"] + ".xcodeproj", target_config["scheme"], options: {
      workspace: project_config["project_name"] + ".xcworkspace"
    })

    slather.notify_if_coverage_is_less_than(minimum_coverage: danger_config[build_type][build_variant]["notify_if_coverage_is_less_than"])
    slather.notify_if_modified_file_is_less_than(minimum_coverage: danger_config[build_type][build_variant]["notify_if_modified_file_is_less_than"])
    slather.show_coverage
  else
    message( "Skipping slather (code coverage) for: " + build_variant + ". Not enabled in BuildVariants.json.")
  end
else
  warn("Slather not run: BuildVariants.json wasn't parsed")
end
