  

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