# 🦄 Gooshiswap 👹

[Uniswap V3](https://uniswap.org/blog/uniswap-v3) introduced a number of innovations in AMM design: concentrated liquidity, multiple fee tiers, advanced on chain oracles, and nonfungible liquidity positions. However, it is still missing one critical feature of modern automated liquidity protocols: it does not emit a bunch of worthless reward tokens.

Gooshiswap aims to solve this problem, by applying [GOO](https://www.paradigm.xyz/2022/09/goo) to Uniswap V3 liquidity positions. Users may deposit [UNI-V3 position NFTs](https://docs.uniswap.org/protocol/reference/periphery/NonfungiblePositionManager) to earn "Gooshi," a worthless reward token. Users may spend Gooshi in order to enable Gooshi emissions for new pools, or increase the emission multiplier for existing pools. The price in Gooshi of these actions varies according to a [logistic-linear VRGDA](https://www.paradigm.xyz/2022/08/vrgda).

Gooshi emissions are initially enabled for only the [DAI/USDC 0.01% pool](https://info.uniswap.org/#/pools/0x5777d92f208679db4b9778590fa3cab3ac9e2168), but anyone with enough Gooshi may spend their tokens to incentivize new pools and spit out more Gooshi, faster. Modern tokenomics in action!

(This is a joke project demonstrating GOO and VRGDAs, please do not actually deploy this. Although it is mostly a goof, it is perhaps also an example of how GOO might be used to align token holders and protocol LPs, while still emitting a bunch of worthless reward tokens.)
