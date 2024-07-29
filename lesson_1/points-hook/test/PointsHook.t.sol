// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency,CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PointsHook} from "../src/PointsHook.sol";
// import {HookMiner} from "./utils/HookMiner.sol";

contract TestPoinstHook is Test,Deployers{
    using CurrencyLibrary for Currency;

    MockERC20 token; // our token to use in the ETH-TOKEN pool

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    PointsHook hook;

    function setUp() public {
        //Deploy PoolManager and RouterContracts
        deployFreshManagerAndRouters();

        //deploy our TOKEN contract

        token = new MockERC20("TEST TOKEN","TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        //Mint a bunch of TOKEN to outselves and to address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        deployCodeTo(
            "PointsHook.sol",
            abi.encode(manager, "Points Token","TEST_POINTS"),
            address(flags)
        );

        // Deploy our hook
        hook = PointsHook(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidy router
        // These variables are coming from the "Deployers" contract
        token.approve(address(swapRouter),type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize a pool
        (key,) =initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1, //Initial Sqrt(P) value = 1
            ZERO_BYTES // no addiitional "initData"
        );
    }

    function  test_addLiquidityAndSwap() public {
        // Set no referrer in the hook data
        bytes memory hookData = hook.getHookData(address(0),address(this));

        uint256 pointsBalanceOriginal = hook.balanceOf(address(this));

    modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
        key,
        IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: bytes32(0)
        }),
            hookData
        );
        uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));

            // The exact amount of ETH we're adding (x)
    // is roughly 0.299535... ETH
    // Our original POINTS balance was 0
    // so after adding liquidity we should have roughly 0.299535... POINTS tokens
    assertApproxEqAbs(
        pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
        2995354955910434,
        0.0001 ether // error margin for precision loss
    );

      // Now we swap
    // We will swap 0.001 ether for tokens
    // We should get 20% of 0.001 * 10**18 points
    // = 2 * 10**14
    swapRouter.swap{value: 0.001 ether}(
        key,
        IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.001 ether, // Exact input for output swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }),
        PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        }),
        hookData
    );
    uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
    assertEq(
        pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
        2 * 10 ** 14
    );
        }

function test_addLiquidityAndSwapWithReferral() public {
    bytes memory hookData = hook.getHookData(address(1), address(this));

    uint256 pointsBalanceOriginal = hook.balanceOf(address(this));
    uint256 referrerPointsBalanceOriginal = hook.balanceOf(address(1));

    modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
        key,
        IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: bytes32(0)
        }),
        hookData
    );

    uint256 pointsBalanceAfterAddLiquidity = hook.balanceOf(address(this));
    uint256 referrerPointsBalanceAfterAddLiquidity = hook.balanceOf(
        address(1)
    );

    assertApproxEqAbs(
        pointsBalanceAfterAddLiquidity - pointsBalanceOriginal,
        2995354955910434,
        0.00001 ether
    );
    assertApproxEqAbs(
        referrerPointsBalanceAfterAddLiquidity -
            referrerPointsBalanceOriginal -
            hook.POINTS_FOR_REFERRAL(),
        299535495591043,
        0.000001 ether
    );

    // Now we swap
    // We will swap 0.001 ether for tokens
    // We should get 20% of 0.001 * 10**18 points
    // = 2 * 10**14
    // Referrer should get 10% of that - so 2 * 10**13
    swapRouter.swap{value: 0.001 ether}(
        key,
        IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }),
        PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        }),
        hookData
    );
    uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this));
    uint256 referrerPointsBalanceAfterSwap = hook.balanceOf(address(1));

    assertEq(
        pointsBalanceAfterSwap - pointsBalanceAfterAddLiquidity,
        2 * 10 ** 14
    );
    assertEq(
        referrerPointsBalanceAfterSwap -
            referrerPointsBalanceAfterAddLiquidity,
        2 * 10 ** 13
    );
}
}