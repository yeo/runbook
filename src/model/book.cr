class Book
  def self.find_all(dir)
    Dir[dir].map do |f|
      {name: f, title: f.split("/").last.split(".").first.gsub("-", " ")}
    end
  end
end
