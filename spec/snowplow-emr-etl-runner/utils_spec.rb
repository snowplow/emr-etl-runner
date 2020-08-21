# Copyright (c) 2012-2020 Snowplow Analytics Ltd. All rights reserved.
#
# This program is licensed to you under the Apache License Version 2.0,
# and you may not use this file except in compliance with the Apache License Version 2.0.
# You may obtain a copy of the Apache License Version 2.0 at http://www.apache.org/licenses/LICENSE-2.0.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the Apache License Version 2.0 is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the Apache License Version 2.0 for the specific language governing permissions and limitations there under.

# Author::    Ben Fradet (mailto:support@snowplowanalytics.com)
# Copyright:: Copyright (c) 2012-2020 Snowplow Analytics Ltd
# License::   Apache License Version 2.0

require 'spec_helper'
require 'base64'
require 'json'
require 'contracts'

Utils = Snowplow::EmrEtlRunner::Utils

describe Utils do
  subject { Object.new.extend described_class }

  describe '#build_enrichments_json' do
    it { should respond_to(:build_enrichments_json).with(1).argument }

    it 'should build a json with empty data if given an empty array' do
      expect(Base64.strict_decode64(subject.build_enrichments_json([]))).to eq({
        'schema' => 'iglu:com.snowplowanalytics.snowplow/enrichments/jsonschema/1-0-0',
        'data'   => []
      }.to_json)
    end

    it 'should build the proper json if given another json' do
      expect(Base64.strict_decode64(subject.build_enrichments_json([ '{"a": "1" }' ]))).to eq({
        'schema' => 'iglu:com.snowplowanalytics.snowplow/enrichments/jsonschema/1-0-0',
        'data'   => [ { 'a' => '1' } ]
      }.to_json)
    end
  end

  describe '#get_hosted_assets_bucket' do
    it { should respond_to(:get_hosted_assets_bucket).with(3).argument }

    it 'should give back the standard bucket if in eu-west-1' do
      expect(subject.get_hosted_assets_bucket('bucket', 'bucket', 'eu-west-1')).to eq('bucket/')
    end

    it 'should suffix the standard bucket with the region if not in eu-west-1' do
      expect(subject.get_hosted_assets_bucket('bucket', 'bucket', 'eu-central-1'))
        .to eq('bucket-eu-central-1/')
    end

    it 'should give back the specified bucket if in eu-west-1' do
      expect(subject.get_hosted_assets_bucket('std-bucket', 'bucket', 'eu-west-1')).to eq('bucket/')
    end

    it 'should give back the specified bucket if not in eu-west-1' do
      expect(subject.get_hosted_assets_bucket('std-bucket', 'bucket', 'eu-central-1'))
        .to eq('bucket/')
    end
  end

  describe '#get_cc_version' do
    it { should respond_to(:get_cc_version).with(1).argument }

    it 'should give back 1.5 if the enrich version is <= 1.8.0' do
      expect(subject.get_cc_version("0.6.0")).to eq("1.5")
      expect(subject.get_cc_version("1.8.0")).to eq("1.5")
    end

    it 'should give back 1.10 if the enrich version is > 1.8.0' do
      expect(subject.get_cc_version("1.9.0")).to eq("1.10")
    end

    it 'should fail if the argument is not a version' do
      expect {
        subject.get_cc_version("s")
      }.to raise_error(ArgumentError, 'Malformed version number string s')
    end
  end

  describe '#is_ua_ndjson' do
    it { should respond_to(:is_ua_ndjson).with(1).argument }

    it 'should give back true for an airship fmt' do
      expect(subject.is_ua_ndjson('ndjson/com.urbanairship.connect/blabla')).to be(true)
    end

    it 'should give back false for another fmt' do
      expect(subject.is_ua_ndjson('thrift')).to be(false)
    end
  end

  describe '#is_cloudfront_log' do
    it { should respond_to(:is_cloudfront_log).with(1).argument }

    it 'should give back true for a cloudfront fmt' do
      expect(subject.is_cloudfront_log('cloudfront')).to be(true)
      expect(subject.is_cloudfront_log('tsv/com.amazon.aws.cloudfront/blabla')).to be(true)
    end

    it 'should give back false for another fmt' do
      expect(subject.is_cloudfront_log('ndjson/com.urbanairship.connect/blabla'))
    end
  end

  describe '#get_s3_endpoint' do
    it { should respond_to(:get_s3_endpoint).with(1).argument }

    it 'should prefix the s3 url with the region if its not us-east-1' do
      expect(subject.get_s3_endpoint('eu-west-1')).to eq('s3-eu-west-1.amazonaws.com')
    end

    it 'should give back s3.amazonaws.com if us-east-1' do
      expect(subject.get_s3_endpoint('us-east-1')).to eq('s3.amazonaws.com')
    end
  end

  describe '#get_assets' do
    it { should respond_to(:get_assets).with(5).argument }

    it 'should give back the old enrich artifact if major == 0' do
      expect(subject.get_assets('/', '0.1.0', '1.2.0', '0.1.0', '0.1.0')).to eq({
        :enrich => '/3-enrich/hadoop-etl/snowplow-hadoop-etl-0.1.0.jar',
        :shred => '/3-enrich/scala-hadoop-shred/snowplow-hadoop-shred-1.2.0.jar',
        :loader   => "/4-storage/rdb-loader/snowplow-rdb-loader-0.1.0.jar",
        :elasticsearch => '/4-storage/hadoop-elasticsearch-sink/hadoop-elasticsearch-sink-0.1.0.jar'
      })
    end

    it 'should give back the new enrich artifact if major > 0' do
      expect(subject.get_assets('/', '1.4.0', '1.2.0', '0.1.0', '0.1.0')).to eq({
        :enrich => '/3-enrich/scala-hadoop-enrich/snowplow-hadoop-enrich-1.4.0.jar',
        :shred => '/3-enrich/scala-hadoop-shred/snowplow-hadoop-shred-1.2.0.jar',
        :loader   => "/4-storage/rdb-loader/snowplow-rdb-loader-0.1.0.jar",
        :elasticsearch => '/4-storage/hadoop-elasticsearch-sink/hadoop-elasticsearch-sink-0.1.0.jar'
      })
    end
  end

  describe '#partition_by_run' do
    it { should respond_to(:partition_by_run).with(3).argument }

    it 'should give back the folder with the run id appended if retain' do
      expect(subject.partition_by_run('f', 'id')).to eq('frun=id/')
    end

    it 'should give back nil if not retain' do
      expect(subject.partition_by_run('f', 'id', false)).to be_nil
    end
  end

  describe '#output_codec_from_compression_format' do
    it { should respond_to(:output_codec_from_compression_format).with(1).argument }

    it 'should give back an empty array if the compression format is nil' do
      expect(subject.output_codec_from_compression_format(nil)).to eq([])
    end

    it 'should give back an empty array if the compression format is NONE' do
      expect(subject.output_codec_from_compression_format('NONE')).to eq([])
    end

    it 'should give back gz if the compression format is GZIP or GZ' do
      expect(subject.output_codec_from_compression_format('GZIP')).to eq([ '--outputCodec', 'gz' ])
      expect(subject.output_codec_from_compression_format('GZ')).to eq([ '--outputCodec', 'gz' ])
    end

    it 'should return the proper output codec if the provided one is supported' do
      expect(subject.output_codec_from_compression_format('LZO')).to eq([ '--outputCodec', 'lzo' ])
    end
  end

  describe '#glob_path' do
    it { should respond_to(:glob_path).with(1).argument }

    it 'should add /* if not already present' do
      expect(subject.glob_path('p')).to eq('p/*')
      expect(subject.glob_path('p/')).to eq('p/*')
    end

    it 'should do nothing if the path already ends with /*' do
      expect(subject.glob_path('p/*')).to eq('p/*')
    end
  end

  describe '#parse_duration' do
    it 'should successfully convert weeks, days, hours and minutes into seconds correctly' do
      expect(subject.parse_duration("1w 5d 3h 13m")).to eq(1048380)
    end
  end

  describe '#get_failure_details' do
    let(:jobflow_id) { "JOB ID" }
    let(:cluster_state) { 'TERMINATED' }
    let(:timeline) do
      <<-JSON
        {
          "CreationDateTime": 1436788464.415,
          "EndDateTime": 1436791032.097,
          "ReadyDateTime": 1436788842.195
        }
      JSON
    end
    let(:aws_cluster_status) do
      <<-JSON
        {
          "Cluster": {
            "Applications": [
              {
                "Name": "hadoop",
                "Version": "1.0.3"
              }
            ],
            "AutoTerminate": true,
            "Configurations": [
            ],
            "Ec2InstanceAttributes": {
              "Ec2AvailabilityZone": "us-east-1a",
              "EmrManagedMasterSecurityGroup": "sg-b7de0adf",
              "EmrManagedSlaveSecurityGroup": "sg-89de0ae1"
            },
            "Id": "j-3T0PHNUXCY7SX",
            "MasterPublicDnsName": "ec2-54-81-173-103.compute-1.amazonaws.com",
            "Name": "Elasticity Job Flow",
            "NormalizedInstanceHours": 2,
            "RequestedAmiVersion": "latest",
            "RunningAmiVersion": "2.4.2",
            "Status": {
              "State": "#{cluster_state}",
              "StateChangeReason": {
                "Code": "ALL_STEPS_COMPLETED",
                "Message": "Steps completed"
              },
              "Timeline": #{timeline}
            },
            "Tags": [
              {
                "Key": "key",
                "Value": "value"
              }
            ],
            "TerminationProtected": false,
            "VisibleToAllUsers": false
          }
        }
      JSON
    end

    let (:cluster_status) { Elasticity::ClusterStatus.from_aws_data(JSON.parse(aws_cluster_status)) }

    let(:aws_cluster_steps) do
      <<-JSON
        {
            "Steps": [
                {
                    "ActionOnFailure": "TERMINATE_CLUSTER",
                    "Config": {
                        "Args": [
                            "36",
                            "3",
                            "0"
                        ],
                        "Jar": "s3n://elasticmapreduce/samples/cloudburst/cloudburst.jar",
                        "MainClass" : "MAIN_CLASS",
                        "Properties": {
                            "Key1" : "Value1",
                            "Key2" : "Value2"
                        }
                    },
                    "Id": "s-OYPPAC4XPPUC",
                    "Name": "Elasticity Custom Jar Step",
                    "Status": {
                        "State": "COMPLETED",
                        "StateChangeReason": {
                          "Code": "ALL_STEPS_COMPLETED",
                          "Message": "Steps completed"
                        },
                        "Timeline": #{timeline}
                    }
                }
            ]
        }
      JSON
    end

    let(:cluster_step_statuses) { Elasticity::ClusterStepStatus.from_aws_list_data(JSON.parse(aws_cluster_steps)) }

    let(:expected_output) {
      [
        "EMR jobflow JOB ID failed, check Amazon EMR console and Hadoop logs for details (help: https://github.com/snowplow/snowplow/wiki/Troubleshooting-jobs-on-Elastic-MapReduce). Data files not archived.",
        "JOB ID: TERMINATED [ALL_STEPS_COMPLETED] ~ 00:36:29 #{subject.get_timespan(cluster_status.ready_at, cluster_status.ended_at)}",
        " - 1. Elasticity Custom Jar Step: COMPLETED ~ elapsed time n/a [ - #{cluster_status.ended_at}]"
      ]
        .join("\n")
    }

    it { should respond_to(:get_failure_details).with(3).argument }

    it 'should create a string containing a summary of the failure' do
      expect(subject.get_failure_details(jobflow_id, cluster_status, cluster_step_statuses)).to eq(expected_output)
    end
  end

  describe '#should_copy_shredded_JSONs' do
    targets_dir = File.expand_path(File.dirname(__FILE__)+"/resources/blacklist-tabular").to_s
    v0_15_0 = Gem::Version.new("0.15.0")
    v0_16_0 = Gem::Version.new("0.16.0")
    v0_16_0_rc1 = Gem::Version.new("0.16.0-rc1")

    it 'should return true if shredder version < 0.16.0 and tabularBlacklist is empty' do
      expect(subject.should_copy_shredded_JSONs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/empty')])).to eq(true)
    end

    it 'should return true if shredder version < 0.16.0 and tabularBlacklist is not empty' do
      expect(subject.should_copy_shredded_JSONs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/non-empty')])).to eq(true)
    end

    it 'should return true if shredder version < 0.16.0 and tabularBlacklist is null' do
      expect(subject.should_copy_shredded_JSONs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/null')])).to eq(true)
    end

    it 'should return false if shredder version >= 0.16.0 and tabularBlacklist is empty' do
      expect(subject.should_copy_shredded_JSONs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/empty')])).to eq(false)
    end

    it 'should return true if shredder version >= 0.16.0 and tabularBlacklist is not empty' do
      expect(subject.should_copy_shredded_JSONs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/non-empty')])).to eq(true)
    end

    it 'should return true if shredder version >= 0.16.0 and tabularBlacklist is null' do
      expect(subject.should_copy_shredded_JSONs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/null')])).to eq(true)
    end
  end

  describe '#should_copy_shredded_TSVs' do
    targets_dir = File.expand_path(File.dirname(__FILE__)+"/resources/blacklist-tabular").to_s
    v0_15_0 = Gem::Version.new("0.15.0")
    v0_16_0 = Gem::Version.new("0.16.0")
    v0_16_0_rc1 = Gem::Version.new("0.16.0-rc1")

    it 'should return false if shredder version < 0.16.0 and tabularBlacklist is not an array' do
      expect(subject.should_copy_shredded_TSVs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/not-array')])).to eq(false)
    end

    it 'should return false if shredder version < 0.16.0 and tabularBlacklist is an array' do
      expect(subject.should_copy_shredded_TSVs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/empty')])).to eq(false)
    end

    it 'should return false if shredder version < 0.16.0 and tabularBlacklist is null' do
      expect(subject.should_copy_shredded_TSVs(v0_15_0, v0_16_0_rc1, [readSDJ(targets_dir + '/null')])).to eq(false)
    end

    it 'should return false if shredder version >= 0.16.0 and tabularBlacklist is not an array' do
      expect(subject.should_copy_shredded_TSVs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/not-array')])).to eq(false)
    end

    it 'should return true if shredder version >= 0.16.0 and tabularBlacklist is an array' do
      expect(subject.should_copy_shredded_TSVs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/empty')])).to eq(true)
    end

    it 'should return false if shredder version >= 0.16.0 and tabularBlacklist is null' do
      expect(subject.should_copy_shredded_TSVs(v0_16_0, v0_16_0_rc1, [readSDJ(targets_dir + '/null')])).to eq(false)
    end
  end

  describe '#extract_tabular_blacklist' do
    targets_dir = File.expand_path(File.dirname(__FILE__)+"/resources/blacklist-tabular").to_s

    it 'should return nil if there is no blacklistTabular' do
      targetPath = targets_dir + '/absent'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)])).to eq(nil)
    end

    it 'should return empty array if blacklistTabular is an empty array' do
      targetPath = targets_dir + '/empty'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)])).to eq([])
    end

    it 'should return an array with one element if blacklistTabular contains one element' do
      targetPath = targets_dir + '/non-empty'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)]).length).to eq(1)
    end

    it 'should return nil if blacklistTabular is not an array' do
      targetPath = targets_dir + '/not-array'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)])).to eq(nil)
    end

    it 'should return nil if blacklistTabular is null' do
      targetPath = targets_dir + '/null'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)])).to eq(nil)
    end

    it 'should return nil if resdhift_config version is < 4.0.0' do
      targetPath = targets_dir + '/redshift-config-3'
      expect(subject.extract_tabular_blacklist([readSDJ(targetPath)])).to eq(nil)
    end
  end

  include Contracts
  Contract String => Iglu::SelfDescribingJson
  def readSDJ(path)
    json = JSON.parse(File.read(path), {:symbolize_names => true})
    Iglu::SelfDescribingJson.parse_json(json)
  end
end
