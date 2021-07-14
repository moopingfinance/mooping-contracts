// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/IBEP20.sol";
import "./libs/IBEP721.sol";
import "./libs/SafeBEP20.sol";
import "./libs/ReentrancyGuard.sol";

import "./MooPingToken.sol";

// MasterChef is the master of MOOPING. He can make MOOPING and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once MOOPING is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of MOOPINGs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMooPingPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMooPingPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. MOOPINGs to distribute per block.
        uint256 lastRewardBlock; // Last block number that MOOPINGs distribution occurs.
        uint256 accMooPingPerShare; // Accumulated MOOPINGs per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        address nftRequiredAddress; // Address of the NFT which is required to use the pool. (Optional)
    }

    // The MOOPING TOKEN!
    MooPingToken public mooping;
    // Dev address.
    address public devaddr;
    // MOOPING tokens created per block.
    uint256 public moopingPerBlock;
    // Bonus muliplier for early mooping makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when MOOPING mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        MooPingToken _mooping,
        address _devaddr,
        address _feeAddress,
        uint256 _moopingPerBlock,
        uint256 _startBlock
    ) public {
        mooping = _mooping;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        moopingPerBlock = _moopingPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    modifier poolExists(uint256 pid) {
        require(pid < poolInfo.length, "pool inexistent");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint16 _depositFeeBP,
        address _nftRequiredAddress,
        bool _withUpdate
    ) public onlyOwner {
        require(
            _depositFeeBP <= 10000,
            "add: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accMooPingPerShare: 0,
                depositFeeBP: _depositFeeBP,
                nftRequiredAddress: _nftRequiredAddress
            })
        );
    }

    // Update the given pool's MOOPING allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        address _nftRequiredAddress,
        bool _withUpdate
    ) public onlyOwner {
        require(
            _depositFeeBP <= 10000,
            "set: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].nftRequiredAddress = _nftRequiredAddress;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending MOOPINGs on frontend.
    function pendingMooPing(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMooPingPerShare = pool.accMooPingPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 moopingReward = multiplier
            .mul(moopingPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
            accMooPingPerShare = accMooPingPerShare.add(
                moopingReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accMooPingPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see if user can use pools
    function canUsePool(uint256 _pid, address _user)
        public
        view
        poolExists(_pid)
        returns (bool)
    {
        PoolInfo storage pool = poolInfo[_pid];
        return
            pool.nftRequiredAddress == address(0) ||
            IBEP721(pool.nftRequiredAddress).balanceOf(_user) >= 1;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 moopingReward = multiplier
        .mul(moopingPerBlock)
        .mul(pool.allocPoint)
        .div(totalAllocPoint);
        mooping.mint(devaddr, moopingReward.div(10));
        mooping.mint(address(this), moopingReward);
        pool.accMooPingPerShare = pool.accMooPingPerShare.add(
            moopingReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for MOOPING allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            pool.nftRequiredAddress == address(0) ||
                IBEP721(pool.nftRequiredAddress).balanceOf(msg.sender) >= 1,
            "deposit: This pool requires a specific NFT in your wallet"
        );
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
            .amount
            .mul(pool.accMooPingPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
            if (pending > 0) {
                safeMooPingTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accMooPingPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        if (
            pool.nftRequiredAddress == address(0) ||
            IBEP721(pool.nftRequiredAddress).balanceOf(msg.sender) >= 1
        ) {
            uint256 pending = user
            .amount
            .mul(pool.accMooPingPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
            if (pending > 0) {
                safeMooPingTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMooPingPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe mooping transfer function, just in case if rounding error causes pool to not have enough MOOPINGs.
    function safeMooPingTransfer(address _to, uint256 _amount) internal {
        uint256 moopingBal = mooping.balanceOf(address(this));
        if (_amount > moopingBal) {
            mooping.transferWithLock(_to, moopingBal);
        } else {
            mooping.transferWithLock(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _moopingPerBlock) public onlyOwner {
        massUpdatePools();
        moopingPerBlock = _moopingPerBlock;
    }

    // Setup MooPingder Token Reward Release
    function setMooPingRewardLock(uint256 lock) public onlyOwner {
        mooping.setRewardLock(lock);
    }

    function setMooPingTotalBlockRelease(uint256 totalBlockRelease)
        public
        onlyOwner
    {
        mooping.setTotalBlockRelease(totalBlockRelease);
    }
}
