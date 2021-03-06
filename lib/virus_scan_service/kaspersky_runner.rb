require_relative 'kaspersky_runner/linux_executor'
require_relative 'kaspersky_runner/windows_executor'
require 'fileutils'

module VirusScanService
  class KasperskyRunner
    ScanLogPathNotSet = Class.new(StandardError)
    ScanLogParseError = Class.new(StandardError)
    AntivirusExecNotSet = Class.new(StandardError)
    RequestNotSuccessful = Class.new(StandardError)

    include BuildHttp

    attr_reader   :url, :result
    attr_writer   :scan_folder, :archive_folder
    attr_accessor :scan_log_path, :timestamp_builder, :antivirus_exec

    def initialize(url)
      @url = url
      @timestamp_builder = ->{ Time.now.to_i.to_s }
    end

    def call
      begin
        pull_file
        begin
          empty_scan_log
          scan_file
          set_result
        ensure
          remove_file
          archive_scan_log if File.size?(scan_log_path) # Exists & non-empty
        end
      rescue URI::InvalidURIError, RequestNotSuccessful
        set_result_download_error
      end
      return nil
    end

    def scan_file_path
      scan_folder.join(filename)
    end

    def scan_folder
      @scan_folder ||= Pathname
        .new('/tmp')
        .join('scans')
        .tap do |path|
          ::FileUtils.mkdir_p(path)
        end
    end

    def archive_folder
      @archive_folder ||= Pathname
        .new('/tmp')
        .join('scans')
        .tap do |path|
          ::FileUtils.mkdir_p(path)
        end
    end

    private
    def archive_scan_log
      archive_name = "#{File.basename(scan_log_path.to_s, '.*')}_#{timestamp_builder.call}.log"
      ::FileUtils.mv(scan_log_path, archive_folder.join(archive_name))
    end

    def remove_file
      begin
        FileUtils.rm_r(scan_folder.join(filename))
      rescue => e
        # kaspersky is automatically removing suspicious files
        # this is rescue ensures that after kasperky removes that file
        # script wont blow up
        #
        # For whatever reason under Windows using
        #
        #   if File.exist?(scan_folder.join(filename))
        #
        # won't help to determine if file was removed by kaspersky
        #
        # That's why this captures if exception matches Permission deny @ unlink_internal
        raise e unless e.to_s.match('unlink_internal')
      end
    end

    def empty_scan_log
      File.open(scan_log_path, 'w') {}
    end

    def set_result
      result = File.read(scan_log_path || raise(ScanLogPathNotSet))
      result.scan(/(?:Total detected|Threats found):\s*(\d+)/) do |threat_count, *other|
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

    def set_result_download_error
      @result = 'FileDownloadError'
    end

    def scan_file
      (antivirus_exec || raise(AntivirusExecNotSet))
        .scan(scan_file_path, scan_log_path)
    end

    def pull_file
      http = build_http

      request = Net::HTTP::Get.new(uri.to_s)
      response = http.request(request)

      raise(RequestNotSuccessful) unless response.class == Net::HTTPOK

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
