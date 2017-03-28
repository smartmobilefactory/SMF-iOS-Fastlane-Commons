
  desc "Create and push the metaJSON files."
  private_lane :generate_meta_json do |options|

    buildVariant = options[:buildVariant]
    branch = options[:branch]

    if buildVariant == "Alpha"
      desc "Create the meta JSON files"
      sh "cd .. && Submodules/SMF-iOS-CommonProjectSetupFiles/MetaJSON/update-and-push-meta-jsons.sh \"#{branch}\" || true"
    end

  end
