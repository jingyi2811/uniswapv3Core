// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../src/IUniswapV3Factory.sol';
import "../src/IUniswapV3Pool.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract StablePoolTest is Test {
    address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address factoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    IUniswapV3Factory factory;
    IUniswapV3Pool pool;

    function setUp() public {
        factory = IUniswapV3Factory(factoryAddress);
        pool = IUniswapV3Pool(factory.getPool(daiAddress, usdtAddress, 3000));
    }

    function testStablePool() public {
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
        = pool.slot0();

        console.log(sqrtPriceX96);
        console.logInt(tick);
    }
}