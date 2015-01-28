module VirusScanService
  class KasperskyRunner
    ScanLogPathNotSet = Class.new(StandardError)
    ScanLogParseError = Class.new(StandardError)

    include BuildHttp

    attr_reader :url, :result
    attr_accessor :scan_log_path, :scan_folder

    def initialize(url)
      @url = url
      @scan_folder = Pathname.new('/tmp')
    end

    def call
      pull_file
      begin
        scan_file
        set_result
      ensure
        remove_file
      end
      nil
    end

    def scan_file_path
      scan_folder.join(filename)
    end

    private

    def remove_file
      # kaspersky is automatically removing suspicious file,
      # this will ensure that all files are erased after check
      FileUtils.rm_r(scan_folder.join(filename)) if File.exist?(scan_folder.join(filename))
    end

    def set_result
      result = File.read(scan_log_path || raise(ScanLogPathNotSet))
      result.scan(/Total detected:\s*(\d+)/) do |threat_count, *other|
        if threat_count == ''
          raise ScanLogParseError
        elsif threat_count == '0'
          @result = 'Clean'
        else
          @result = 'VirusInfected'
        end
      end

      raise ScanLogParseError if @result.nil?
    end

    def scan_file
      system("avp.com SCAN #{scan_file_path} /i4 /fa /RA:#{scan_log_path}")
    end

    def pull_file
      http = build_http

      request = Net::HTTP::Get.new(uri.to_s)
      response = http.request(request)
      open(scan_file_path, 'wb') do |file|
        file.write(response.body)
        file.close
      end
    end

    def uri
      @uri ||= URI.parse(url)
    end

    def filename
      File.basename(uri.path)
    end
  end
end
