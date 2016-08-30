# Copyright 2016 DoubleDutch, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'dd_spacecadet/config'

module LitaLBCfg
  module Loader
    # helper function to set up SpaceCadet
    # meant to be used with the `on :loaded` event handler
    # to use this, please add `include LitaLBCfg::Loader` to your handler
    def set_up_spacecadet(_)
      creds = _config.credentials

      creds.each do |credentials|
        _register_client(credentials)
      end
    end

    # helper method for reliably pulling the right Lita config key
    def _config
      Lita.config.handlers.lbcfg
    end

    # helper method to register the client based on the credentials
    def _register_client(credentials)
      DoubleDutch::SpaceCadet::Config.register(
        "#{credentials[:region]}-#{credentials[:env]}".downcase,
        credentials[:username].downcase,
        credentials[:key],
        credentials[:region].upcase
      )
    end
  end
end
