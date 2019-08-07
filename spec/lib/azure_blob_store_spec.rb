require 'rails_helper'
require './plugins/discourse-azure-blob-storage/lib/azure_blob_store'

describe FileStore::AzureStore do

  let(:store) { FileStore::AzureStore.new }
  let(:upload) { Fabricate(:upload) }
  let(:uploaded_file) { file_from_fixtures("logo.png") }
  let(:optimized_image) { Fabricate(:optimized_image) }
  let(:optimized_image_file) { file_from_fixtures("logo.png") }
  let(:azure_account) { "azure-blob-account-name" }
  let(:blob_container) { "azure-blob-container-name" }
  let(:blob_service) { Azure::Storage::Blob::BlobService }

  before(:each) do
    SiteSetting.azure_blob_storage_account_name = "azure-blob-account-name"
    SiteSetting.azure_blob_storage_access_key = SecureRandom.base64
    SiteSetting.azure_blob_storage_container_name = "azure-blob-container-name"
    SiteSetting.azure_blob_storage_enabled = true
  end

  context 'uploading to azure blob' do
    let(:upload) do
      Fabricate(:upload, sha1: Digest::SHA1.hexdigest('secreet image string'))
    end

    describe "#store_upload" do
      it "returns an absolute schemaless url" do
        store.expects(:get_depth_for).with(upload.id).returns(0)
        stub_request(:put, "https://#{azure_account}.blob.core.windows.net/#{blob_container}/original/1X/#{upload.sha1}.png")
        expect(store.store_upload(uploaded_file, upload)).to eq(
          "//azure-blob-account-name.blob.core.windows.net/azure-blob-container-name/original/1X/#{upload.sha1}.png"
        )
      end
    end

    describe "#store_optimized_image" do
      it "returns an absolute schemaless url" do
        store.expects(:get_depth_for).with(optimized_image.upload.id).returns(0)
        path = "optimized/1X/#{optimized_image.upload.sha1}_#{OptimizedImage::VERSION}_100x200.png"
        stub_request(:put, "https://#{azure_account}.blob.core.windows.net/#{blob_container}/#{path}")
        expect(store.store_optimized_image(optimized_image_file, optimized_image)).to eq(
          "//azure-blob-account-name.blob.core.windows.net/azure-blob-container-name/#{path}"
        )
      end

      it "recreates optimized image for new version" do
        version = 1
        path = "optimized/1X/#{upload.sha1}_#{version}_20x20.png"
        schemeless_url = "//#{azure_account}.blob.core.windows.net/#{blob_container}/#{path}"
        optimized = Fabricate(:optimized_image,
          upload: upload,
          version: nil,
          url: schemeless_url,
          width: 20,
          height: 20
        )
        old_url = "https:#{schemeless_url}"
        new_url = old_url.sub("#{version}_20x20", "#{OptimizedImage::VERSION}_20x20")

        stub_request(:put, old_url.sub("/optimized/", "/tombstone/optimized/"))
        stub_request(:delete, old_url)
        stub_request(:put, new_url)

        new_optimized = upload.get_optimized_image(20, 20, allow_animation: SiteSetting.allow_animated_avatars)
        expect("https:#{new_optimized.url}").to eq(new_url)
      end
    end
  end

  context 'removal from azure' do
    let(:upload) do
      Fabricate(:upload, sha1: Digest::SHA1.hexdigest('secreet image string'))
    end

    describe "#remove_upload" do
      it "removes the file from azure storage with the right paths" do
        store.expects(:get_depth_for).with(upload.id).returns(0)
        store.expects(:has_been_uploaded?).returns(true)
        blob_service.any_instance.expects(:copy_blob)
        blob_service.any_instance.expects(:delete_blob)
        store.remove_upload(upload)
      end
    end

    describe "#remove_optimized_image" do
      let(:optimized_image) do
        Fabricate(:optimized_image,
          url: "//azure-blob-account-name.blob.core.windows.net/optimized/1X/#{upload.sha1}_1_100x200.png",
          upload: upload
        )
      end

      it "removes the file from Azure storage with the right paths" do
        store.expects(:get_depth_for).with(optimized_image.upload.id).returns(0)
        store.expects(:has_been_uploaded?).returns(true)
        blob_service.any_instance.expects(:copy_blob)
        blob_service.any_instance.expects(:delete_blob)
        store.remove_optimized_image(optimized_image)
      end

    end
  end

  describe ".has_been_uploaded?" do

    it "identifies Azure blob uploads" do
      expect(store.has_been_uploaded?("//azure-blob-account-name.blob.core.windows.net/azure-blob-container-name/1337.png")).to eq(true)
    end

    it "does not match other urls" do
      expect(store.has_been_uploaded?("//azure-blob-account.blob.core.windows.net/1337.png")).to eq(false)
    end

  end

  describe ".absolute_base_url" do
    it "returns a lowercase schemaless absolute url" do
      expect(store.absolute_base_url).to eq("//azure-blob-account-name.blob.core.windows.net")
    end
  end

  it "is external" do
    expect(store.external?).to eq(true)
    expect(store.internal?).to eq(false)
  end

  describe ".purge_tombstone" do
    it "updates tombstone lifecycle" do
      blob_service.any_instance.expects(:list_blobs).returns([])
      store.purge_tombstone(1.day)
    end
  end

  describe ".path_for" do
    def assert_path(path, expected)
      upload = Upload.new(url: path)

      path = store.path_for(upload)
      expected = FileStore::LocalStore.new.path_for(upload) if expected

      expect(path).to eq(expected)
    end

    it "correctly falls back to local" do
      assert_path("/hello", "/hello")
      assert_path("//hello", nil)
      assert_path("http://hello", nil)
      assert_path("https://hello", nil)
    end
  end

  describe ".url_for" do
    def assert_url(url, expected)
      upload = Upload.new(url: url)

      url = store.url_for(upload)
      expected = FileStore::LocalStore.new.url_for(upload) if expected

      expect(url).to eq(expected)
    end

    it "returns url from upload" do
      test = "//example.com/path/file.ext"
      upload = Upload.new(url: test)
      url = store.url_for(upload)
      expect(url).to eq(test)
    end 
    it "adds rscd param to url" do
      test = "//example.com/path/file.ext"
      upload = Upload.new(url: test)
      url = store.url_for(upload, force_download: true)
      expect(url).to eq(test + '?rscd=file;%20attachment')
    end 
  end
end
