
  desc "Build the project based on the build type."
  private_lane :archive_ipa do |options|

    app_identifier = options[:app_identifier]
    scheme = options[:scheme]
    ipa_filename = options[:ipa_filename]
    codesigning_identity = options[:codesigning_identity]

   UI.important("Build a new version")

   unlock_keychain(path: "login.keychain", password: ENV["LOGIN"])

   sigh(
    skip_certificate_verification:true,
    app_identifier: app_identifier
    )

   unlock_keychain(path: "jenkins.keychain", password: ENV["JENKINS"])

   gym(
      clean: true,
      workspace: "#{PROJECT_NAME}.xcworkspace",
      scheme: scheme,
      configuration: 'Release',
      codesigning_identity: codesigning_identity,
      output_directory: "build",
      archive_path:"build/",
      output_name: ipa_filename     
      )
  end
