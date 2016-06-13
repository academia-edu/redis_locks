require 'spec_helper'

describe RedisLocks::Mutex do
  let(:mutex) {
    RedisLocks::Mutex.new('testmutex')
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

    it 'says not expired' do
      expect(mutex.expired?).to be_falsey
    end

    it 'says not expired with small safety margin' do
      expect(mutex.expired?(safety_margin: 2)).to be_falsey
    end

    it 'says expired with large safety margin' do
      expect(mutex.expired?(safety_margin: 60 * 60 * 24 * 365)).to be_truthy
    end

    it 'asserts not_expired!' do
      mutex.not_expired!
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

    it 'says expired' do
      expect(mutex.expired?).to be_truthy
    end

    it 'fails not_expired!' do
      expect { mutex.not_expired! }.to raise_error(RedisLocks::MutexExpired)
    end
  end
end
