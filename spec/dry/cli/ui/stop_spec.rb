# frozen_string_literal: true

RSpec.describe Dry::CLI::UI::Stop do
  subject(:stop) { described_class.new }

  its(:stopped?) { is_expected.to be(false) }

  describe "#stop!" do
    subject! { stop.stop! }

    it { is_expected.to be(stop) }
    it { expect(stop).to be_stopped }
  end

  describe "#trap" do
    let(:signal) { "USR2" }
    let(:signalled) do
      lambda do
        Process.kill(signal, Process.pid)
        sleep(0.05)
      end
    end

    it "asks for a stop on the first signal" do
      expect(stop.trap(signal) { signalled.call && stop.stopped? }).to be(true)
    end

    it "interrupts on the second" do
      expect { stop.trap(signal) { 2.times { signalled.call } } }.to raise_error(Interrupt)
    end

    it "returns what the block returns" do
      expect(stop.trap(signal) { |given| given }).to be(stop)
    end

    it "puts the previous handler back" do
      previous = proc {}
      Signal.trap(signal, previous)
      stop.trap(signal) { nil }
      expect(Signal.trap(signal, "DEFAULT")).to be(previous)
    end

    context "when there was no handler to put back" do
      before do
        allow(Signal).to receive(:trap).and_return(nil)
        stop.trap(signal) { nil }
      end

      it { expect(Signal).to have_received(:trap).with(signal, "DEFAULT") }
    end
  end
end
