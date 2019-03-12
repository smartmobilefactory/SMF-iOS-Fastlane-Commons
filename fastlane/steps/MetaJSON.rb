# Constants

SLATHER_COVERAGE_REPORT_JSON_NAME = "report.json"
SMF_COVERAGE_REPORT_JSON_NAME = "test_coverage.json"
SLATHER_HTML_OUTPUT_DIR_NAME = "slather_coverage_report"

##############################
### smf_generate_meta_json ###
##############################

# options: build_variants_contains_whitelist (String) [optional]

desc "Create the metaJSON files - applys only for Alpha builds."
private_lane :smf_generate_meta_json do |options|

  # Parameter
  build_variants_contains_whitelist = options[:build_variants_contains_whitelist]

  if (build_variants_contains_whitelist.nil?) || (build_variants_contains_whitelist.any? { |whitelist_item| @smf_build_variant.include?(whitelist_item) })
    desc "Create the meta JSON files"

    metajson = "#{@fastlane_commons_dir_path}/tools/MetaJSON-Wrapper.app/Contents/Frameworks/metajson"
    workspace_dir = smf_workspace_dir
    branch = @smf_git_branch

    # Create and commit the MetaJSON files
    sh "cd .. && #{metajson} analyse --d \"#{workspace_dir}\" --p \"#{@smf_fastlane_config[:project][:project_name]}\" --branch #{branch} --output \"#{workspace_dir}/.MetaJSON\" --automatically --verbose 2>/dev/null || true"
  end
end

############################
### smf_commit_meta_json ###
############################

desc "Commit the metaJSON files - applys only for Alpha builds."
private_lane :smf_commit_meta_json do |options|

  # Variables
  workspace = smf_workspace_dir

  # Copy additional meta files to MetaJSON directory
  sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then cp -R #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/. #{workspace}/.MetaJSON/; fi"

  # Delete the temporary MetaJSON folder
  sh "if [ -d #{workspace}/#{$METAJSON_TEMP_FOLDERNAME} ]; then rm -rf #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}; fi"

  # Remove Pods.json and Cloc.json if they are present
  sh "if [ -f #{workspace}/.MetaJSON/Pods.json ]; then rm #{workspace}/.MetaJSON/Pods.json; fi"
  sh "if [ -f #{workspace}/.MetaJSON/Cloc.json ]; then rm #{workspace}/.MetaJSON/Cloc.json; fi"

  # Reset git, add MetaJSON directory and commit. A failing commit is not seen as error as this is fine if there are no changed files
  sh "cd \"#{workspace}\"; git reset && git add \".MetaJSON\" && (git commit -m \"Update MetaJSONs\" || true)"

end

##############
### Helper ###
##############

def smf_run_linter

  # Variables
  workspace = smf_workspace_dir

  begin

    source_path = "#{workspace}/build/reports/swiftlint.json"
    target_path = "#{$METAJSON_TEMP_FOLDERNAME}/swiftlint.json"

    # Run SwiftLint and save the output as JSON
    swiftlint_path = Dir["#{workspace}/**/SwiftLint/portable_swiftlint/swiftlint"].first
    if ( ! File.exists?(swiftlint_path))
      swiftlint_path = "#{workspace}/Pods/SwiftLint/swiftlint"
    end

    UI.message("Running: #{swiftlint_path} lint --reporter json > \"#{source_path}\"")
    system "cd #{workspace}; #{swiftlint_path} lint --reporter json > \"#{source_path}\""

    # Removes the workspace part
    workspace_regexp = (workspace + '/').gsub(/\//, '\\\\\\\\\/')
    system "sed -i -e 's/#{workspace_regexp}//g' #{source_path}"

    # Turns \/ int /
    a = '\\\\\/'
    b = '\/'
    # Convert the abosulte path to a path wich is relative to the project root folder
    system "sed -i -e 's/#{a}/#{b}/g' #{source_path}"

    # Sort the report to avoid a changed file altough the warnings are the same
    swiftlint_report_file = File.read("#{source_path}")
    swiftlint_report_array ||= JSON.parse(swiftlint_report_file)
    swiftlint_report_array = swiftlint_report_array.sort_by { |entry| [entry['file'], entry['line'], entry['character'], entry['reason']] }
    File.open("#{workspace}/#{target_path}","w") do |f|
      f.write(JSON.pretty_generate(swiftlint_report_array))
    end

  rescue => e
    UI.error("Failed to run SwiftLint. But the build job will continue. SwiftLint Path: #{swiftlint_path}\nException #{e}")

    smf_send_chat_message(
        title: "Failed to run Swiftlint for #{smf_default_notification_release_title} 😢",
        type: "error",
        slack_channel: ci_ios_error_log
      )
  end
end

def smf_run_slather

  # Variables
  workspace = smf_workspace_dir
  scheme = @smf_fastlane_config[:build_variants][@smf_build_variant_sym][:scheme]
  project_name = @smf_fastlane_config[:project][:project_name]

  # Create the Slather report as html
  system "cd " + workspace + "; slather coverage -v --html --scheme " + scheme + " --workspace " + project_name + ".xcworkspace " + project_name + ".xcodeproj"

  # Create the Slather report as json
  system "cd " + workspace + "; slather coverage -v --json --scheme " + scheme + " --workspace " + project_name + ".xcworkspace " + project_name + ".xcodeproj"

  # Analyse the Slather json report and store the result in out format
  if File.file?(workspace + "/#{SLATHER_COVERAGE_REPORT_JSON_NAME}")
    smf_create_json_slather_summary(workspace + "/#{SLATHER_COVERAGE_REPORT_JSON_NAME}")
  end

  # Copy the output into the temporary MetaJSON folder so that the files can be used once the MetaJSON creation is complete
  slather_json_report_path = "#{workspace}/build/reports/#{SMF_COVERAGE_REPORT_JSON_NAME}"
  sh "if [ -f \"#{slather_json_report_path}\" ]; then cp \"#{slather_json_report_path}\" #{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/#{SMF_COVERAGE_REPORT_JSON_NAME}; fi"
  slather_html_report_output_root_path = "#{workspace}"
  slather_html_report_output_dir_name = "html"
  slather_html_report_output_path = "#{slather_html_report_output_root_path}/#{slather_html_report_output_dir_name}"
  slather_html_report_path = "#{workspace}/#{$METAJSON_TEMP_FOLDERNAME}/#{SLATHER_HTML_OUTPUT_DIR_NAME}"


  # Compress the Slather HTML folder and delete it afterwards
  sh "if [ -d \"#{slather_html_report_output_path}\" ]; then cd \"#{slather_html_report_output_root_path}\"; zip -rj \"#{slather_html_report_output_dir_name}.zip\" #{slather_html_report_output_dir_name}/*; fi"
  sh "if [ -f \"#{slather_html_report_output_path}.zip\" ]; then cp \"#{slather_html_report_output_path}.zip\" \"#{slather_html_report_path}.zip\"; fi"
end

def smf_create_json_slather_summary(report_file)
  if File.file?(report_file)
    files = JSON.parse(File.read(report_file))

    workspace = smf_workspace_dir

    summary = { }
    summary["files"] = [ ]

    total_covered_loc = 0
    total_relevant_loc = 0
    filenum = 0

    for file in files
        filenum += 1

        covered_loc = 0
        relevant_loc = 0

        for line in file["coverage"]
          if line.to_i > 0
            covered_loc += 1
            relevant_loc += 1
          elsif !line.nil? && line.to_i == 0
            relevant_loc += 1
          end
        end

        percent = (covered_loc.to_f / relevant_loc.to_f) * 100

        entity = { }
        entity["file"] = file["file"]
        entity["coverage"] = percent
        summary["files"] << entity

        total_covered_loc += covered_loc
        total_relevant_loc += relevant_loc
    end

    percent = (total_covered_loc.to_f / total_relevant_loc.to_f) * 100

    summary["total_coverage"] = percent

    File.open(workspace + "/build/reports/#{SMF_COVERAGE_REPORT_JSON_NAME}", "w") do |f|
      f.write(summary.to_json)
    end
  else
    puts "Warning: could not find Slather JSON report with filename \"#{report_file}\""
  end
end
