require 'spec_helper'
require 'fileutils'

RSpec.describe VirusScanService::KasperskyRunner do
  let(:runner) {
    described_class
      .new('http://thisis.test/download/file.png')
      .tap do |runner|
        runner.timestamp_builder = ->{ '012345678' }
        runner.scan_log_path = 'spec/tmp/kaspersky_test.log'
        runner.scan_folder = Pathname
          .new('spec')
          .join('tmp')
          .join('scans')
          .tap do |path| FileUtils.mkdir_p(path) end
        runner.archive_folder = Pathname
          .new('spec')
          .join('tmp')
          .join('scans_archive')
          .tap do |path| FileUtils.mkdir_p(path) end
      end
  }

  let(:scan_log) {
    spec_root
      .join('fixtures')
      .join('virus_result_clean.log')
  }

  describe "#call" do
    before do
      stub_request(:get, "http://thisis.test/download/file.png")
        .with(:headers => {
          'Accept'=>'*/*',
          'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'User-Agent'=>'Ruby'
        })
        .to_return(:status => 200, :body => "This-is-a-file-content", :headers => {})

      expect(runner).to receive(:ensure_no_scan_log_exist).and_call_original

      allow(runner)
        .to receive(:system)
        .with("avp.com SCAN spec/tmp/scans/file.png /i4 /fa /RA:spec/tmp/kaspersky_test.log") {
          FileUtils.cp(scan_log, 'spec/tmp/kaspersky_test.log')
          nil
        }
    end

    after do
      if File.exist?("spec/tmp/scans_archive/kaspersky_test_012345678.log")
        FileUtils.rm "spec/tmp/scans_archive/kaspersky_test_012345678.log"
      end
    end

    let(:call) { runner.call }

    context '' do
      before { allow(runner).to receive(:remove_file) } # skip file remove

      it 'downloads the file from net' do
        call
        expect(File.read(runner.scan_file_path))
          .to eq "This-is-a-file-content"
      end
    end

    it 'should remove scanned file' do
      call
      expect(File.exist?(runner.scan_file_path)).to be false
    end

    it 'should archive scan log' do
      call
      expect(File.exist?('spec/tmp/kaspersky_test.log')).to be false
      expect(File.exist?("spec/tmp/scans_archive/kaspersky_test_012345678.log")).to be true
    end

    context 'when no threats detected' do
      before { call }
      it 'sets the result' do
        expect(runner.result).to eq 'Clean'
      end
    end

    context 'when virus detected' do
      before { call }
      let(:scan_log) {
        spec_root
          .join('fixtures')
          .join('virus_result_threat.log')
      }

      it 'sets the result' do
        expect(runner.result).to eq 'VirusInfected'
      end
    end

    context 'when log has error' do
      let(:scan_log) {
        spec_root
          .join('fixtures')
          .join('virus_result_error.log')
      }

      it 'sets the result' do
        expect { runner.call }
          .to raise_error(VirusScanService::KasperskyRunner::ScanLogParseError)
      end
    end
  end

  describe 'private #ensure_no_scan_log_exist' do
    it 'should existing scan log before scan begin' do
      FileUtils.cp(scan_log, 'spec/tmp/kaspersky_test.log') # pre-existing scan
      runner.send(:ensure_no_scan_log_exist)
      expect(File.exist?('spec/tmp/kaspersky_test.log')).to be false
    end
  end
end
