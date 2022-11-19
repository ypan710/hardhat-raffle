const {network} = require("hardhat")
const {developmentChains} = require("../helper-hardhat-config")

const BASE_FEE = ethers.utils.parseEther("0.25"); // 0.25 LINK in premium to request a random number
const GAS_PRICE_LINK = 1e9;

module.exports = async function ({getNamedAccounts, deployments}) {

    const {deploy, log} = deployments
    const {deployer} = await getNamedAccounts()
    const name = network.name;
    const args = [BASE_FEE, GAS_PRICE_LINK]

    if (developmentChains.includes(name)) {
        log("Local network detected! Deploying mocks...")
        await deploy("VRFCoordinatorV2Mock", {
            from: deployer,
            log: true,
            args: args
        })
        log("Mocks deployed!")
        log("-------------------------------------------------")
    }
}

module.exports.tags = ["all", "mocks"]
