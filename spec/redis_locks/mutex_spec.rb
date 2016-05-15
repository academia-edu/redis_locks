require 'spec_helper'

describe RedisLocks::Mutex do
  let(:mutex) {
    RedisLocks::Mutex.new(
      'testmutex',
      redis: $redis
    )
  }

  it 'allows locking' do
    expect(mutex.lock).to be_truthy
  end

  it 'allows locking via lock!' do
    expect { mutex.lock! }.not_to raise_error
  end

  it 'runs block' do
    ran = false
    mutex.lock { ran = true }
    expect(ran).to be_truthy
  end

  it 'runs two blocks successively' do
    ran = 0
    mutex.lock { ran += 1 }
    mutex.lock { ran += 1 }
    expect(ran).to eq(2)
  end

  context 'when locked' do
    before do
      mutex.lock!
    end

    it 'does not allow locking again' do
      expect(mutex.lock).to be_falsey
    end

    it 'does not run block' do
      ran = false
      mutex.lock { ran = true }
      expect(ran).to be_falsey
    end

    it 'raises error on lock!' do
      expect { mutex.lock! }.to raise_error(RedisLocks::AlreadyLocked)
    end

    context 'and then unlocked' do
      before do
        mutex.unlock
      end

      it 'allows locking' do
        expect(mutex.lock).to be_truthy
      end
    end
  end

  context 'when locked but expired' do
    before do
      mutex.lock!(expires_at: Time.now.utc.to_i+1)
      sleep(2)
    end

    it 'allows lock' do
      expect(mutex.lock).to be_truthy
    end
  end
end
