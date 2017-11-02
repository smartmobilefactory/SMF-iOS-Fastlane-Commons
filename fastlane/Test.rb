  

  build_variants_config_stored = nil

  private_lane :print_do do |options|
    UI.message("config: #{config}")
  end

  private_lane :work do |options|
    UI.message("Commons: Everthing is fine".green)
  end

  private_lane :crash do |options|
    raise "Commons: Something went wrong".red
  end

  after_all do |lane|
    UI.message("Commons - after_all: lane: #{lane}")
  end

  error do |lane, exception|
    UI.message("Commons - Error: lane: #{lane}, exception: #{exception}")
  end

  def config
    if build_variants_config_stored.nil?
      build_variants_config_stored = build_variants_config
    end

    return build_variants_config_stored
  end