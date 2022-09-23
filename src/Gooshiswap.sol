// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {toWadUnsafe, toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {LibGOO} from "goo-issuance/LibGOO.sol";
import {LogisticToLinearVRGDA} from "VRGDAs/LogisticToLinearVRGDA.sol";

import "./uniswap/INonfungiblePositionManager.sol";
import "./Gooshi.sol";

address constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

struct Pool {
    uint256 points; // Pool allocation points. The more of these, the higher the emissions multiple.
    uint256 liquidity; // Total liquidity from deposited UNI-V3 positions in this pool.
}

struct Balance {
    uint256 liquidity; // Total liquidity deposited by user.
    uint128 lastBalance; // Last Gooshi balance.
    uint64 lastTimestamp; // Last Gooshi snapshot timestamp.
}

/// @title Gooshiswap
/// @author horsefacts <horsefacts@terminally.online>
/// @notice What if Uniswap V3 gave you a lot of tokens? No, I mean *a lot* of tokens...
contract GooshiSwap is ERC721TokenReceiver, LogisticToLinearVRGDA {
    /// @notice the Gooshi ERC20 token
    Gooshi public immutable gooshi;

    /// @notice Uniswap V3 position manager
    INonfungiblePositionManager constant positionManager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

    int256 internal constant SWITCH_DAY_WAD = 233e18;
    int256 internal constant SOLD_BY_SWITCH_WAD = 8336.760939794622713006e18;

    /// @notice Start timestamp of Gooshi emissions
    uint64 public emissionsStart;
    /// @notice Total "points" purchased to create new pools or increase pool allocation
    uint256 public totalPoints;

    event GooshiBalanceUpdated(address indexed user, uint256 newGooshiBalance);
    event PoolAdded(
        address indexed user, uint256 totalPoints, uint256 price, address token0, address token1, uint24 feeTier
    );
    event PointAdded(
        address indexed user,
        uint256 totalPoints,
        uint256 price,
        address token0,
        address token1,
        uint24 feeTier,
        uint256 points
    );

    /// @notice Pool accounting. (token0 address => token1 address => fee tier => Pool)
    mapping(address => mapping(address => mapping(uint24 => Pool))) public pools;

    /// @notice Tracks owners of UNI-V3 positions by token ID. (tokenId => depositor)
    mapping(uint256 => address) public ownerOf;

    /// @notice Individual user balances by pool. (token0 address => token1 address => fee tier => depositor => Balance)
    mapping(address => mapping(address => mapping(uint24 => mapping(address => Balance)))) public balances;

    constructor()
        LogisticToLinearVRGDA(
            4.2069e18, // Target price.
            0.31e18, // Price decay percent.
            9000e18, // Logistic asymptote.
            0.014e18, // Logistic time scale.
            SOLD_BY_SWITCH_WAD, // Sold by switch.
            SWITCH_DAY_WAD, // Target switch day.
            1e18 // Points to target per day.
        )
    {
        gooshi = new Gooshi(address(this));
        emissionsStart = uint64(block.timestamp);
        pools[DAI][USDC][100] = Pool({points: 1, liquidity: 0});
    }

    /// @notice deposit a UNI-V3 position token to accrue Gooshi.
    function deposit(uint256 tokenId) external {
        // Get pool details and liquidity from UNI-V3 position token
        (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);

        // Ensure pool exists
        require(pools[token0][token1][fee].points > 0, "Pool not found");

        // Store owner by position token ID
        ownerOf[tokenId] = msg.sender;

        // Add liquidity to pool balance
        pools[token0][token1][fee].liquidity += liquidity;

        // Add liquidity to user balance
        balances[token0][token1][fee][msg.sender].liquidity += liquidity;

        // Save deposit timestamp in user balance
        balances[token0][token1][fee][msg.sender].lastTimestamp = uint64(block.timestamp);

        // Transfer in UNI-V3 position token
        positionManager.transferFrom(msg.sender, address(this), tokenId);
    }

    /// @notice Withdraw a deposited UNI-V3 position.
    function withdraw(uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "Unauthorized");

        // Get pool details and liquidity from UNI-V3 position token
        (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);

        // Delete token owner
        delete ownerOf[tokenId];

        // Deduct liquidity from pool balance
        pools[token0][token1][fee].liquidity -= liquidity;

        // Deduct liquidity from user balance
        balances[token0][token1][fee][msg.sender].liquidity -= liquidity;

        // Transfer out UNI-V3 position token
        positionManager.transferFrom(address(this), msg.sender, tokenId);
    }

    /// @notice Spend Gooshi to add an allocation point to a pool. This may be used either to approve a new pool
    /// or to increase allocation to an existing pool
    function addPoint(address token0, address token1, uint24 feeTier, uint256 maxPrice) external {
        // Will revert if prior to mint start.
        uint256 currentPrice = pointPrice();

        // If the current price is above the user's specified max, revert.
        require(currentPrice <= maxPrice, "Price exceeded max");

        // Burn gooshi from caller
        gooshi.burnForGooshiSwap(msg.sender, currentPrice);

        unchecked {
            emit PointAdded(
                msg.sender,
                ++totalPoints,
                currentPrice,
                token0,
                token1,
                feeTier,
                ++pools[token0][token1][feeTier].points
                );
        }
    }

    /// @notice Current price of an allocation point.
    function pointPrice() public view returns (uint256) {
        uint256 timeSinceStart = block.timestamp - emissionsStart;

        unchecked {
            return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), totalPoints);
        }
    }

    /// @notice Get a user's Gooshi balance by pool.
    function gooshiBalance(address token0, address token1, uint24 feeTier, address user)
        public
        view
        returns (uint256)
    {
        // A user's emission multiple for a given pool is a function of the pool's allocation
        // points and the user's share of the pool's total deposited liquidity. I have not done
        // any real math on any of these parameters and they are probably wrong in some horrifying way.
        uint256 emissionMultiple;
        {
            uint256 points = pools[token0][token1][feeTier].points;
            uint256 poolLiquidity = pools[token0][token1][feeTier].liquidity;
            uint256 userLiquidity = balances[token0][token1][feeTier][user].liquidity;
            uint256 poolShare = FixedPointMathLib.divWadDown(userLiquidity, poolLiquidity);
            emissionMultiple = FixedPointMathLib.mulWadUp(points * 10, poolShare);
        }

        return LibGOO.computeGOOBalance(
            emissionMultiple,
            balances[token0][token1][feeTier][user].lastBalance,
            uint256(toDaysWadUnsafe(block.timestamp - balances[token0][token1][feeTier][user].lastTimestamp))
        );
    }

    /// @notice Add Gooshi to pool balance from ERC20.
    function addGooshi(address token0, address token1, uint24 feeTier, uint256 gooshiAmount) external {
        gooshi.burnForGooshiSwap(msg.sender, gooshiAmount);

        // Increase msg.sender's virtual gooshi balance.
        updateUserGooshiBalance(token0, token1, feeTier, msg.sender, gooshiAmount, GooshiBalanceUpdateType.INCREASE);
    }

    /// @notice Withdraw Gooshi from pool balance to ERC20.
    function removeGooshi(address token0, address token1, uint24 feeTier, uint256 gooshiAmount) external {
        // Decrease msg.sender's virtual gooshi balance.
        updateUserGooshiBalance(token0, token1, feeTier, msg.sender, gooshiAmount, GooshiBalanceUpdateType.DECREASE);

        // Mint the corresponding amount of ERC20 gooshi.
        gooshi.mintForGooshiSwap(msg.sender, gooshiAmount);
    }

    enum GooshiBalanceUpdateType {
        INCREASE,
        DECREASE
    }

    function updateUserGooshiBalance(
        address token0,
        address token1,
        uint24 feeTier,
        address user,
        uint256 gooshiAmount,
        GooshiBalanceUpdateType updateType
    ) internal {
        // Will revert due to underflow if we're decreasing by more than the user's current balance.
        // Don't need to do checked addition in the increase case, but we do it anyway for convenience.
        uint256 updatedBalance = updateType == GooshiBalanceUpdateType.INCREASE
            ? gooshiBalance(token0, token1, feeTier, user) + gooshiAmount
            : gooshiBalance(token0, token1, feeTier, user) - gooshiAmount;

        // Snapshot the user's new gooshi balance with the current timestamp.
        balances[token0][token1][feeTier][user].lastBalance = uint128(updatedBalance);
        balances[token0][token1][feeTier][user].lastTimestamp = uint64(block.timestamp);

        emit GooshiBalanceUpdated(user, updatedBalance);
    }
}
