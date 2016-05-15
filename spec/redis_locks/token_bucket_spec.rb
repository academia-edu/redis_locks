require 'spec_helper'

describe RedisLocks::TokenBucket do
  context 'with two tokens per each two seconds' do
    let(:bucket) {
      RedisLocks::TokenBucket.new(
        "testbucket",
        redis: $redis,
        period: 2,
        number: 2
      )
    }

    it 'allows resource to be used' do
      expect(bucket.take).to be_truthy
    end

    it 'allows resource to be used via take!' do
      expect { bucket.take! }.not_to raise_error
    end

    context 'with one resource used' do
      before do
        bucket.take!
      end

      it 'allows another resource to be used' do
        expect(bucket.take).to be_truthy
      end
    end

    context 'with all resources used' do
      before do
        # three rather than two because the microseconds since the first
        # execution will allow another token to become available
        3.times { bucket.take! }
      end

      it 'does not allow another resource to be used' do
        expect(bucket.take).to be_falsey
      end

      it 'raises error on take!' do
        expect { bucket.take! }.to raise_error(RedisLocks::RateLimitExceeded)
      end

      context 'after waiting' do
        before do
          sleep(2)
        end

        it 'allows another resource to be taken' do
          expect(bucket.take).to be_truthy
        end
      end
    end
  end
end
