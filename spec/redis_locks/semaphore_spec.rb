require 'spec_helper'

describe RedisLocks::Semaphore do
  context 'with one resource' do
    let(:semaphore) {
      RedisLocks::Semaphore.new(
        'testsemaphore',
        redis: $redis,
        resources: 1
      )
    }

    it 'allows locking' do
      expect(semaphore.lock).to be_truthy
    end

    it 'allows locking via lock!' do
      expect { semaphore.lock! }.not_to raise_error
    end

    it 'allows locking with timeout' do
      expect(semaphore.lock timeout: 1).to be_truthy
    end

    it 'allows locking with infinite timeout' do
      expect(semaphore.lock timeout: 0).to be_truthy
    end

    it 'runs block' do
      ran = false
      semaphore.lock { ran = true }
      expect(ran).to be_truthy
    end

    it 'runs two blocks successively' do
      ran = 0
      semaphore.lock { ran += 1 }
      semaphore.lock { ran += 1 }
      expect(ran).to eq(2)
    end

    context 'when locked' do
      before do
        @token = semaphore.lock!
      end

      it 'does not allow locking again' do
        expect(semaphore.lock).to be_falsey
      end

      it 'does not allow locking with timeout' do
        expect(semaphore.lock timeout: 1).to be_falsey
      end

      it 'waits forever with infinite timeout' do
        t = Thread.new do
          semaphore.lock timeout: 0
        end

        sleep(2)
        expect(t).to be_alive
        t.kill
      end

      it 'does not run block' do
        ran = false
        semaphore.lock { ran = true }
        expect(ran).to be_falsey
      end

      it 'raises error on lock!' do
        expect { semaphore.lock! }.to raise_error(RedisLocks::SemaphoreUnavailable)
      end

      context 'and then unlocked' do
        before do
          semaphore.unlock @token
        end

        it 'allows locking' do
          expect(semaphore.lock).to be_truthy
        end
      end
    end
  end

  context 'with two resources' do
    let(:semaphore) {
      RedisLocks::Semaphore.new(
        'testsem',
        redis: $redis,
        resources: 2
      )
    }

    it 'allows locking' do
      expect(semaphore.lock).to be_truthy
    end

    context 'after one lock' do
      before do
        @token = semaphore.lock
      end

      it 'allows locking again' do
        expect(semaphore.lock).to be_truthy
      end

      context 'after another lock' do
        before do
          semaphore.lock
        end

        it 'does not allow locking a third time' do
          expect(semaphore.lock).to be_falsey
        end

        context 'after releasing first lock' do
          before do
            semaphore.unlock @token
          end

          it 'allows locking' do
            expect(semaphore.lock).to be_truthy
          end
        end
      end
    end
  end
end
