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

require 'spec_helper'

def action_to_verb(action)
  case action.downcase
  when 'drain'
    'Draining'
  when 'enable'
    'Enabling'
  else
    '???'
  end
end

def action_to_sym(action)
  case action.downcase
  when 'drain'
    :draining
  when 'enable'
    :enabled
  else
    :UNKNOWN_THINGY
  end
end


describe Lita::Handlers::Lbcfg, lita_handler: true do
  it { is_expected.to route_command('lbcfg status sf test lita').to(:status) }
  it { is_expected.to route_command('lbcfg drain sf test lita us-lita-01').to(:lbcfg_router) }
  it { is_expected.to route_command('lbcfg enable sf test lita us-lita-01').to(:lbcfg_router) }
  it { is_expected.to route_command('lbcfg invalid sf test lita us-lita-01').to(:lbcfg_router) }

  let(:happy_status) do
    [
      {
        name: 'test-lb01',
        id: 42,
        nodes: [
          { name: 'app01', condition: 'ENABLED', ip: '127.0.0.1', id: 142 },
          { name: 'app02', condition: 'ENABLED', ip: '127.0.0.2', id: 184 }
        ]
      },
      {
        name: 'test-lb02',
        id: 84,
        nodes: [
          { name: 'app01', condition: 'ENABLED', ip: '127.0.0.1', id: 242 },
          { name: 'app02', condition: 'ENABLED', ip: '127.0.0.2', id: 284 }
        ]
      }
    ]
  end

  let(:happy_cfg) do
    {
      'sf' => {
        'test' => {
          'lita' => [42, 84]
        }
      }
    }
  end

  let(:sad_region_cfg) do
    {
      'sfx' => {
        'test' => {
          'lita' => [42, 84]
        }
      }
    }
  end

  let(:sad_env_cfg) do
    {
      'sf' => {
        'testx' => {
          'lita' => [42, 84]
        }
      }
    }
  end

  let(:sad_balancer_cfg) do
    {
      'sf' => {
        'test' => {
          'litax' => [42, 84]
        }
      }
    }
  end

  describe '#config' do
    it 'should set the lb_hash key to an empty Hash' do
      expect(Lita.config.handlers.lbcfg.lb_hash).to be_a(Hash)
      expect(Lita.config.handlers.lbcfg.lb_hash).to be_empty
    end

    it 'should set the credentials key to an empty Array' do
      expect(Lita.config.handlers.lbcfg.credentials).to be_an(Array)
      expect(Lita.config.handlers.lbcfg.credentials).to be_empty
    end
  end

  ####
  # Shared Tests
  ####
  shared_examples 'happy path' do |opts|
    let(:action) { opts[:action] }
    let(:verb) { action_to_verb(action) }
    let(:symbol) { action_to_sym(action) }

    before do
      @lb_client = double('DoubleDutch::SpaceCadet::LB', status: happy_status, add_lb: nil, update_node: nil)
      allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:new_client)
        .with('sf-test')
        .and_return(@lb_client)
    end

    after do
      allow_any_instance_of(DoubleDutch::SpaceCadet::LB).to receive(:new_client).and_call_original
    end

    it 'should create a new DoubleDutch::SpaceCadet::LB config and add the IDs to it' do
      expect(@lb_client).to receive(:add_lb).with(42)
      expect(@lb_client).to receive(:add_lb).with(84)
      send_command("lbcfg #{action} sf test lita app01")
    end

    it 'should call the update with the proper values' do
      expect(@lb_client).to receive(:update_node).with('app01', symbol)
      send_command("lbcfg #{action} sf test lita app01")
    end

    it 'should respond with the correct response' do
      send_command("lbcfg #{action} sf test lita app01")
      expect(replies.size).to eql(2)
      expect(replies[0]).to eql("#{verb} app01 within the sf.test.lita balancer...")
      expect(replies[1]).to eql('Finished updating the lita load balancer')
    end
  end

  shared_examples 'unsafe or inconsistent lb' do |opts|
    let(:action) { opts[:action] }
    let(:verb) { action_to_verb(action) }
    let(:symbol) { action_to_sym(action) }

    context 'when the LB is unsafe' do
      before do
        @lb_client = double('DoubleDutch::SpaceCadet::LB', status: happy_status, add_lb: nil, update_node: nil)
        allow(@lb_client).to receive(:update_node).and_raise(DoubleDutch::SpaceCadet::LBUnsafe, 'testBody')
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:new_client)
          .with('sf-test')
          .and_return(@lb_client)
      end

      after do
        allow_any_instance_of(DoubleDutch::SpaceCadet::LB).to receive(:new_client).and_call_original
      end

      it 'should create a new DoubleDutch::SpaceCadet::LB config and add the IDs to it' do
        expect(@lb_client).to receive(:add_lb).with(42)
        expect(@lb_client).to receive(:add_lb).with(84)
        send_command("lbcfg #{action} sf test lita app01")
      end

      it 'should call the update with the proper values' do
        expect(@lb_client).to receive(:update_node).with('app01', symbol)
        send_command("lbcfg #{action} sf test lita app01")
      end

      it 'should respond with the correct response' do
        send_command("lbcfg #{opts[:action]} sf test lita app01")
        expect(replies.size).to eql(2)
        expect(replies[0]).to eql("#{verb} app01 within the sf.test.lita balancer...")
        expect(replies[1]).to eql(
"An error has occured trying to #{action} the requested node:\n" +
'DoubleDutch::SpaceCadet::LBUnsafe: testBody'
        )
      end
    end

    context 'when the LB is inconsistent' do
      before do
        @lb_client = double('DoubleDutch::SpaceCadet::LB', status: happy_status, add_lb: nil, update_node: nil)
        allow(@lb_client).to receive(:update_node).and_raise(DoubleDutch::SpaceCadet::LBInconsistentState, 'testBody')
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:new_client)
          .with('sf-test')
          .and_return(@lb_client)
      end

      after do
        allow_any_instance_of(DoubleDutch::SpaceCadet::LB).to receive(:new_client).and_call_original
      end

      it 'should create a new DoubleDutch::SpaceCadet::LB config and add the IDs to it' do
        expect(@lb_client).to receive(:add_lb).with(42)
        expect(@lb_client).to receive(:add_lb).with(84)
        send_command("lbcfg #{action} sf test lita app01")
      end

      it 'should call the update with the proper values' do
        expect(@lb_client).to receive(:update_node).with('app01', symbol)
        send_command("lbcfg #{action} sf test lita app01")
      end

      it 'should respond with the correct response' do
        send_command("lbcfg #{opts[:action]} sf test lita app01")
        expect(replies.size).to eql(2)
        expect(replies[0]).to eql("#{verb} app01 within the sf.test.lita balancer...")
        expect(replies[1]).to eql(
"An error has occured trying to #{action} the requested node:\n" +
'DoubleDutch::SpaceCadet::LBInconsistentState: testBody'
        )
      end
    end
  end

  shared_examples 'action bad bot config' do |opts|
    context "when the region isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_region_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command("lbcfg #{opts[:action]} sf test lita app01")
        expect(replies.last).to eql("Region 'sf' does not exist in the config")
      end
    end

    context "when the env isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_env_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command("lbcfg #{opts[:action]} sf test lita app01")
        expect(replies.last).to eql("Environment 'test' does not exist in the config for sf")
      end
    end

    context "when the balancer isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_balancer_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command("lbcfg #{opts[:action]} sf test lita app01")
        expect(replies.last).to eql("Balancer 'lita' does not exist in the config for sf.test")
      end
    end
  end

  ####
  # Handlers
  ####

  context 'invalid command' do
    it 'should respond with an error' do
      send_command('unknown bot command')
      expect(replies.last).to eql(
        "The command did not match any known routes, please try again. ('unknown bot command')"
      )
    end
  end

  # action router
  context do
    before(:each) do
      lbcfg = double('Lita::', lb_hash: happy_cfg, credentials: [])
      allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
    end

    describe '.lbcfg_drain' do
      it_behaves_like 'happy path', action: 'drain'
      it_behaves_like 'action bad bot config', action: 'drain'
      it_behaves_like 'unsafe or inconsistent lb', action: 'drain'
    end

    describe '.lbcfg_enable' do
      it_behaves_like 'happy path', action: 'enable'
      it_behaves_like 'action bad bot config', action: 'enable'
      it_behaves_like 'unsafe or inconsistent lb', action: 'enable'
    end

    context 'invalid command' do
      it 'returns an error message' do
        send_command('lbcfg invalid sf test lita app01')
        expect(replies.last).to eql("invalid is not a valid action, please use 'drain' or 'enable'")
      end
    end
  end

  describe '.status' do
    let(:happy_data) do
      [
        {
          name: 'test-lb01',
          id: 42,
          nodes: [
            { name: 'app01', condition: 'ENABLED', ip: '127.0.0.1', id: 142 },
            { name: 'app02', condition: 'DRAINING', ip: '127.0.0.2', id: 184 }
          ]
        },
        {
          name: 'test-lb02',
          id: 84,
          nodes: [
            { name: 'app01', condition: 'ENABLED', ip: '127.0.0.1', id: 242 },
            { name: 'app02', condition: 'DRAINING', ip: '127.0.0.2', id: 284 }
          ]
        },
      ]
    end

    before(:each) do
      lbcfg = double('Lita::', lb_hash: happy_cfg, credentials: [])
      allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
    end

    context 'happy-path' do
      before do
        @lb_client = double('DoubleDutch::SpaceCadet::LB', status: happy_data, add_lb: nil)
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:new_client)
          .with('sf-test')
          .and_return(@lb_client)
      end

      after do
        allow_any_instance_of(DoubleDutch::SpaceCadet::LB).to receive(:new_client).and_call_original
      end

      it 'should create a new DoubleDutch::SpaceCadet::LB config and add the IDs to it' do
        expect(@lb_client).to receive(:add_lb).with(42)
        expect(@lb_client).to receive(:add_lb).with(84)
        send_command('lbcfg status sf test lita')
      end

      it 'should render the proper response' do
        send_command('lbcfg status sf test lita')
        expect(replies.last).to eql(
'test-lb01 (42)
  app01  ENABLED  127.0.0.1  142
  app02  DRAINING  127.0.0.2  184
---
test-lb02 (84)
  app01  ENABLED  127.0.0.1  242
  app02  DRAINING  127.0.0.2  284
---
'
        )
      end
    end

    context "when the region isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_region_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command('lbcfg status sf test lita')
        expect(replies.last).to eql("Region 'sf' does not exist in the config")
      end
    end

    context "when the env isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_env_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command('lbcfg status sf test lita')
        expect(replies.last).to eql("Environment 'test' does not exist in the config for sf")
      end
    end

    context "when the balancer isn't found in the bot config" do
      before(:each) do
        lbcfg = double('Lita::', lb_hash: sad_balancer_cfg, credentials: [])
        allow_any_instance_of(Lita::Handlers::Lbcfg).to receive(:config).and_return(lbcfg)
      end

      it 'should return a proper error' do
        send_command('lbcfg status sf test lita')
        expect(replies.last).to eql("Balancer 'lita' does not exist in the config for sf.test")
      end
    end
  end
end
