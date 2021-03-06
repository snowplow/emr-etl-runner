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

# Author::    Alex Dean (mailto:support@snowplowanalytics.com)
# Copyright:: Copyright (c) 2014 Snowplow Analytics Ltd
# License::   Apache License Version 2.0

require 'spec_helper'
require 'time'

describe Snowplow::EmrEtlRunner::Monitoring::Snowplow do

  it "should make a timestamp from the Elasticity API compatible with JSON schema" do
    actual = Snowplow::EmrEtlRunner::Monitoring::Snowplow
      .instance.to_jsonschema_compatible_timestamp(Time.parse('2015-07-29 08:34:40'))
    expect(actual).to eq('2015-07-29T08:34:40Z')
  end

end
