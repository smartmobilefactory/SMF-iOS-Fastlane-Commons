  

  private_lane :work do |options|
    UI.message("everthing is fine")
  end

  private_lane :crash do |options|
    raise "Something went weong".red
  end

  after_all do |lane|
    UI.message("after_all success lane: #{lane}")
  end

  error do |lane, exception|
    UI.message("error success lane: #{lane}, exception: #{exception}")
  end