# app/uploaders/model_uploader.rb
class ModelUploader < CarrierWave::Uploader::Base
  storage :file

  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  def extension_allowlist
    %w(h5)  # Adjust this depending on your model file type
  end
end
