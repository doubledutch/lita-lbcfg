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

require 'dd_spacecadet/error'
require 'lita-lbcfg/loader'

module Lita
  module Handlers
    class LBCfgErr < StandardError; end
    class MissingKey < LBCfgErr; end

    class Lbcfg < Handler
      include LitaLBCfg::Loader

      # {
      #   '<region>' => {
      #     '<environment>' => {
      #       '<balancer>' => [
      #         0,
      #         1
      #       ]
      #     }
      #   }
      # }
      config :lb_hash, default: {}
      config :credentials, default: []

      on :loaded, :set_up_spacecadet # from LitaLBCfg::Loader
      on :unhandled_message, :not_found

      # route for getting the status of the load balancer
      route(
        /^lbcfg\sstatus\s(?<region>\w+)\s(?<environment>\w+)\s(?<balancer>\w+)/,
        :status,
        command: true,
        help: {
          'lbcfg status <region> <environment> <balancer>' => 'show the current status of the balancer in the region.environment'
        }
      )

      # route for taking actions on a load balancer
      route(
        /^lbcfg\s(?<action>\w+)\s(?<region>\w+)\s(?<environment>\w+)\s(?<balancer>\w+)\s(?<node>[A-Za-z0-9\-]+)/,
        :lbcfg_router,
        command: true,
        help: {
          'lbcfg enable <region> <environment> <balancer> <node>' => 'enable the backend within the load balancer',
          'lbcfg drain <region> <environment> <balancer> <node>' => 'drain the backend within the load balancer'
        }
      )

      # handler for command_not_found replies
      def not_found(h)
        return unless h[:message].command?

        dest = h[:message].source
        msg = t('not_found', body: h[:message].body)

        robot.send_message(dest, msg)
      end

      # handler function for getting the status of a load balancer
      def status(response)
        region, environment, balancer = split_params(response)

        client = new_client("#{region}-#{environment}")

        # get the IDs from the config and add it to the client
        # respond with an error if we don't recognize the user input

        begin
          balancer_ids(region, environment, balancer).each { |id| client.add_lb(id) }
        rescue MissingKey => e
          return response.reply(e.to_s)
        end

        # get the status of the LBs
        # do it within a begin block so we can catch
        # the exceptions thrown by SpaceCadet
        begin
          # get the details for all LBs we care about
          details = client.status

          # if we don't have any details, bail
          return response.reply(t('status.no_details', region: region, env: environment, balancer: balancer)) if details.empty?

          # otherwise, render the proper output and print it
          response.reply(render_template('status', output: render_status(details)))

        rescue DoubleDutch::SpaceCadet::Error => e # catch all SpaceCadet errors
          title = "An error has occured trying to get the status of #{region}.#{environment}.#{balancer}:"
          reply = render_template('exception', title: title, exception: e.class, message: e.message)
          response.reply(reply)

        rescue StandardError => e # catch all remaining errors
          title = "A generic excpetion has been caught trying to get the status of #{region}.#{environment}.#{balancer}:"
          reply = render_template('exception', title: title, exception: e.class, message: e.message)
          response.reply(reply)
        end
      end

      # router for taking !lbcfg <action> commands and calling appropriate functions
      def lbcfg_router(response)
        # we don't want to allow updating LBs in private
        # so if this is a DM, return a helpful message to tell them "no"
        return response.reply(t('general.private_message')) if is_dm?(response)

        action = response.match_data['action'].downcase

        # if the action is unknown, return an error message
        return response.reply(t('router.invalid_action', action: action)) unless %w(enable drain).include?(action)

        # wrap the call to the appropriation action function in a rescue block
        # both functions would need similar rescue statements, so let's do it here
        begin
          # call lbcfg_<action> on this Class
          # so if action == 'drain' it'll call lbcfg_drain
          response.reply(send("lbcfg_#{action}".to_sym, response))

        rescue DoubleDutch::SpaceCadet::Error => e # catch all SpaceCadet errors
          title = "An error has occured trying to #{action} the requested node:"
          reply = render_template('exception', title: title, exception: e.class, message: e.message)
          response.reply(reply)

        rescue StandardError => e # catch all remaining errors
          title = "A generic excpetion has been caught trying to #{action} the requested node:"
          reply = render_template('exception', title: title, exception: e.class, message: e.message)
          response.reply(reply)
        end
      end

      private

      def new_client(env)
        DoubleDutch::SpaceCadet::LB.new(env)
      end

      def render_status(details)
        out = ''

        # loop over each LB returned and add its formatted status
        # to the end of the `out` string
        details.each do |lb|
          out << "#{lb[:name]} (#{lb[:id]})\n"

          lb[:nodes].each do |node|
            out << "  #{node[:name]}  #{node[:condition]}  #{node[:ip]}  #{node[:id]}\n"
          end

          out << "---\n"
        end

        out
      end

      def lbcfg_drain(response)
        region, environment, balancer, node = split_long_params(response)

        client = new_client("#{region}-#{environment}")

        begin
          balancer_ids(region, environment, balancer).each { |id| client.add_lb(id) }
        rescue MissingKey => e
          return e.to_s
        end

        response.reply(t('drain.starting_update', node: node, region: region, env: environment, balancer: balancer))
        client.update_node(node, :draining)
        t('general.update_done', balancer: balancer)
      end

      def lbcfg_enable(response)
        region, environment, balancer, node = split_long_params(response)

        client = new_client("#{region}-#{environment}")

        begin
          balancer_ids(region, environment, balancer).each { |id| client.add_lb(id) }
        rescue MissingKey => e
          return e.message
        end

        response.reply(t('enable.starting_update', node: node, region: region, env: environment, balancer: balancer))
        client.update_node(node, :enabled)
        t('general.update_done', balancer: balancer)
      end

      # filter function to check if the message looks to be coming via DM
      def is_dm?(response)
        # both the :shell and :console adapters *always* appear to be DMs, so short-circuit those
        return false if [:shell, :console].include?(Lita.config.robot.adapter)

        # return whether it's a PM, or not, according to the adapter
        response.message.source.private_message?
      end

      # take the response Object and parse out the match data
      def split_params(response)
        [
          response.match_data['region'].downcase,
          response.match_data['environment'].downcase,
          response.match_data['balancer'].downcase,
        ]
      end

      # take the response Object and parse out the match data
      # for commands including a node to mutate
      def split_long_params(response)
        split_params(response) << response.match_data['node'].downcase
      end

      # get the load balancer IDs for the cluster we want to operate on
      # this walks the configuration Hash to look for any missing keys
      # we do the walking to provide a helpful error message to the consumer
      def balancer_ids(region, env, balancer)
        h = config.lb_hash

        # if either the <region> or <region>.<environment> key is missing: bail out
        raise MissingKey, t('general.missing_region', region: region) unless h.key?(region)
        raise MissingKey, t('general.missing_env', region: region, env: env) unless h[region].key?(env)

        # if the <region>.<environment>.<balancer> key is missing: bail out
        unless h[region][env].key?(balancer)
          raise MissingKey, t('general.missing_balancer', region: region, env: env, balancer: balancer)
        end

        # if the value for <region>.<environment>.<balancer> is not an Array: bail out
        raise MissingKey, t('general.balancer_not_arr') unless h[region][env][balancer].kind_of?(Array)

        # return the Array of IDs
        h[region][env][balancer]
      end

      Lita.register_handler(self)
    end
  end
end
