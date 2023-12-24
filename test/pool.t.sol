// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MyPool.sol";

contract PriceTest is Test {

    function testPrice() public {
        MyPool myPool = new MyPool();
        bytes memory encoded = abi.encode(myPool.pool(), 6000 * 10, 100);

        {
            myPool.getTimeWeightedTick(address(myPool.pool()), 1);
        }
//
//        {
//            uint price = myPool.getTokenPrice(myPool.secondAddress(), 18, encoded);
//            console.log(price);
//        }
//
//        {
//            uint price = myPool.getTokenTWAP(myPool.firstAddress(), 18, encoded);
//            console.log(price);
//        }
//
//        {
//            uint price = myPool.getTokenTWAP(myPool.secondAddress(), 18, encoded);
//            console.log(price);
//        }

//        (
//            uint160 sqrtPriceX96,
//            int24 tick,
//            uint16 observationIndex,
//            uint16 observationCardinality,
//            uint16 observationCardinalityNext,
//            uint8 feeProtocol,
//            bool unlocked
//        )
//        = pool.slot0();
//
//        console.log(sqrtPriceX96);
//        console.logInt(tick);
    }
}