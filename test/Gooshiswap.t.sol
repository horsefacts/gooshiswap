// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Gooshiswap.sol";
import "../src/uniswap/INonfungiblePositionManager.sol";

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
uint24 constant poolFee = 100;
int24 constant MIN_TICK = -887272;
int24 constant MAX_TICK = -MIN_TICK;

contract GooshiswapTest is Test, ERC721TokenReceiver {
    Gooshi public gooshi;
    GooshiSwap public gooshiswap;
    INonfungiblePositionManager public positionManager;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15624000);
        gooshiswap = new GooshiSwap();
        positionManager = INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);
    }

    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, address receiver)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        deal(DAI, address(this), amount0ToMint);
        deal(USDC, address(this), amount1ToMint);
        SafeTransferLib.safeApprove(ERC20(DAI), address(positionManager), amount0ToMint);
        SafeTransferLib.safeApprove(ERC20(USDC), address(positionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: DAI,
            token1: USDC,
            fee: poolFee,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
        (tokenId, liquidity, amount0, amount1) = positionManager.mint(params);
        positionManager.transferFrom(address(this), receiver, tokenId);
    }

    function test_mint_v3_position() public {
        mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);
    }

    function test_deposit_v3_position() public {
        (uint256 tokenId, uint128 liquidity,,) = mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);

        vm.startPrank(alice);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(tokenId);
        vm.stopPrank();

        assertEq(positionManager.balanceOf(alice), 0);
        assertEq(positionManager.balanceOf(address(gooshiswap)), 1);

        assertEq(gooshiswap.ownerOf(tokenId), alice);

        (uint256 userLiquidity,,) = gooshiswap.balances(DAI, USDC, poolFee, alice);
        assertEq(userLiquidity, liquidity);

        (, uint256 poolLiquidity) = gooshiswap.pools(DAI, USDC, poolFee);
        assertEq(poolLiquidity, liquidity);
    }

    function test_withdraw_v3_position() public {
        (uint256 tokenId,,,) = mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);

        vm.startPrank(alice);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(tokenId);
        gooshiswap.withdraw(tokenId);
        vm.stopPrank();

        assertEq(positionManager.balanceOf(alice), 1);
        assertEq(positionManager.balanceOf(address(gooshiswap)), 0);

        assertEq(gooshiswap.ownerOf(tokenId), address(0));

        (uint256 userLiquidity,,) = gooshiswap.balances(DAI, USDC, poolFee, alice);
        assertEq(userLiquidity, 0);

        (, uint256 poolLiquidity) = gooshiswap.pools(DAI, USDC, poolFee);
        assertEq(poolLiquidity, 0);
    }

    function test_cannot_deposit_to_nonexistent_pool() public {
        vm.startPrank(alice);
        vm.expectRevert("Pool not found");
        gooshiswap.deposit(1);
    }

    function test_cannot_deposit_unowned_token() public {
        (uint256 tokenId,,,) = mintNewPosition(10000 ether, 10000 ether, bob);

        vm.startPrank(alice);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        gooshiswap.deposit(tokenId);
    }

    function test_gooshi_balances() public {
        (uint256 aliceToken,,,) = mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);

        (uint256 bobToken,,,) = mintNewPosition(50000 ether, 50000 ether, bob);
        assertEq(positionManager.balanceOf(bob), 1);

        vm.startPrank(alice);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(aliceToken);
        vm.stopPrank();

        vm.startPrank(bob);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(bobToken);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        assertEq(gooshiswap.gooshiBalance(DAI, USDC, poolFee, alice), 0.5 ether);
        assertEq(gooshiswap.gooshiBalance(DAI, USDC, poolFee, bob), 2.25 ether);
        assertGt(gooshiswap.gooshiBalance(DAI, USDC, poolFee, bob), gooshiswap.gooshiBalance(DAI, USDC, poolFee, alice));
    }

    function test_add_new_pool() public {
        (uint256 aliceToken,,,) = mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);

        vm.startPrank(alice);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(aliceToken);

        vm.warp(block.timestamp + 2 days);

        gooshiswap.removeGooshi(DAI, USDC, poolFee, gooshiswap.gooshiBalance(DAI, USDC, poolFee, alice));
        assertEq(gooshiswap.gooshi().balanceOf(alice), 10 ether);

        assertEq(gooshiswap.pointPrice(), 2.014735491399650325 ether);

        gooshiswap.addPoint(USDC, WETH, 300, 10 ether);

        (uint256 points,) = gooshiswap.pools(USDC, WETH, 300);
        assertEq(points, 1);

        assertEq(gooshiswap.pointPrice(), 2.026635770792072641 ether);
        vm.stopPrank();
    }

    function test_add_point_to_pool() public {
        (uint256 aliceToken,,,) = mintNewPosition(10000 ether, 10000 ether, alice);
        assertEq(positionManager.balanceOf(alice), 1);

        vm.startPrank(alice);
        positionManager.setApprovalForAll(address(gooshiswap), true);
        gooshiswap.deposit(aliceToken);

        vm.warp(block.timestamp + 2 days);

        gooshiswap.removeGooshi(DAI, USDC, poolFee, gooshiswap.gooshiBalance(DAI, USDC, poolFee, alice));
        assertEq(gooshiswap.gooshi().balanceOf(alice), 10 ether);

        assertEq(gooshiswap.pointPrice(), 2.014735491399650325 ether);

        gooshiswap.addPoint(DAI, USDC, 100, 3 ether);

        (uint256 points,) = gooshiswap.pools(DAI, USDC, 100);
        assertEq(points, 2);

        assertEq(gooshiswap.pointPrice(), 2.026635770792072641 ether);
        vm.stopPrank();
    }
}
